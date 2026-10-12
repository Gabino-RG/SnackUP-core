"""Pipeline execution and honest GitHub Actions normalization (stdlib only)."""
from __future__ import annotations

import copy
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Callable
import zipfile


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def stage(identifier: str, name: str, command: str, description: str = "") -> dict:
    return {"id": identifier, "name": name, "status": "pending", "command": command,
            "description": description, "started_at": None, "completed_at": None, "logs": []}


def empty_state(mode: str, title: str, repository: str = "") -> dict:
    return {"mode": mode, "repository": repository, "run_id": None, "sha": "", "branch": "",
            "url": "", "title": title, "status": "pending", "conclusion": None, "stages": [],
            "decisions": [], "artifacts": [], "source_notes": []}


def github_stage_status(status: str | None, conclusion: str | None) -> str:
    """Unknown/neutral conclusions must never be turned into a passing test."""
    if status in {"queued", "requested", "waiting", "pending"}:
        return "pending"
    if status == "in_progress":
        return "running"
    return {"success": "success", "failure": "failure", "timed_out": "failure",
            "startup_failure": "failure", "cancelled": "cancelled", "stale": "cancelled",
            "skipped": "skipped", "neutral": "skipped", "action_required": "blocked"}.get(conclusion, "blocked")


def diagnose(state: dict) -> list[dict]:
    """Rules explain observed conclusions; proposed causes are explicit hypotheses."""
    result = []
    failures = [s for s in state["stages"] if s["status"] == "failure"]
    for failed in failures:
        words = (failed["name"] + " " + failed.get("command", "")).lower()
        if any(w in words for w in ("dependenc", "pub get", "npm ci")):
            advice = "Hipótesis: una versión o un archivo lock puede impedir resolver dependencias. Revisar el log antes de cambiar versiones."
        elif any(w in words for w in ("analyze", "lint", "format", "estático", "formato")):
            advice = "Consultar archivo y línea en el log; corregir formato o diagnóstico y repetir el pipeline. No desactivar el control para obtener un verde."
        elif any(w in words for w in ("sonar", "security", "sast")):
            advice = "Hipótesis: configuración o Quality Gate. Revisar el log y los parámetros de SonarQube; el estado por sí solo no prueba una vulnerabilidad."
        elif any(w in words for w in ("unit", "test", "prueba", "integración")):
            advice = "Revisar el aserto que falla y sus datos de entrada. Si falta la suite de integración, agregar pruebas reales antes de declarar validación completa."
        elif any(w in words for w in ("build", "compil", "constru")):
            advice = "Hipótesis: incompatibilidad de SDK, dependencia o error de compilación. La causa exacta debe confirmarse en el log de compilación."
        else:
            advice = "Abrir el log de esta etapa y corregir el primer error observado antes de reintentar."
        result.append({"level": "error", "title": "Falla observada: " + failed["name"],
                       "detail": "La fuente reportó esta etapa como fallida. El agente no deduce una causa exacta únicamente a partir del estado.",
                       "recommendation": advice})
    if failures:
        first = next(i for i, s in enumerate(state["stages"]) if s["status"] == "failure")
        blocked = [s["name"] for s in state["stages"][first + 1:] if s["status"] in {"blocked", "skipped"}]
        if blocked:
            result.append({"level": "warning", "title": "Fail Fast: trabajo posterior detenido",
                           "detail": "Etapas posteriores sin ejecución exitosa: " + ", ".join(blocked) + ".",
                           "recommendation": "Resolver la primera falla y repetir; una etapa omitida no equivale a una prueba aprobada."})
    cancelled = [s["name"] for s in state["stages"] if s["status"] == "cancelled"]
    if cancelled:
        result.append({"level": "warning", "title": "Ejecución cancelada",
                       "detail": "Etapas canceladas: " + ", ".join(cancelled),
                       "recommendation": "Confirmar el motivo de cancelación en GitHub. No reportar esas etapas como validadas."})
    if state["conclusion"] == "success":
        result.append({"level": "success", "title": "Etapas ejecutadas aprobadas",
                       "detail": "La ejecución terminó con éxito según su fuente. La cobertura se limita a las etapas realmente ejecutadas.",
                       "recommendation": "Revisar qué pruebas incluye el workflow antes de afirmar que hay pruebas de integración o cobertura completa."})
    if state["mode"] == "demo":
        result.append({"level": "info", "title": "Demostración didáctica",
                       "detail": "Se ejecutaron comandos Python sobre un ejemplo aislado; esta corrida no valida el repositorio Flutter de SnackUP.",
                       "recommendation": "Usar la evidencia de GitHub o el modo local para demostrar el CI del proyecto real."})
    return result


def normalize_github_run(run: dict, jobs: list[dict], repository: str) -> dict:
    state = empty_state("live", run.get("name") or "GitHub Actions", repository)
    state.update(run_id=run.get("id"), sha=run.get("head_sha", ""), branch=run.get("head_branch", ""),
                 url=run.get("html_url", ""))
    status = run.get("status")
    state["status"] = "running" if status == "in_progress" else "completed" if status == "completed" else "pending"
    conclusion = run.get("conclusion")
    state["conclusion"] = conclusion if conclusion in {"success", "failure", "cancelled"} else "failure" if conclusion in {"timed_out", "startup_failure", "action_required"} else None
    for job in jobs:
        steps = job.get("steps") or [dict(name=job.get("name", "Job"), number=0,
                                        status=job.get("status"), conclusion=job.get("conclusion"),
                                        started_at=job.get("started_at"), completed_at=job.get("completed_at"))]
        for item in steps:
            name = item.get("name", "Etapa sin nombre")
            # GitHub housekeeping has no application validation; unknown project steps remain visible.
            if name.lower().startswith("post ") or name.lower() in {"complete job", "cleanup", "clean up job"}:
                continue
            entry = stage("gh-{}-{}".format(job.get("id", "job"), item.get("number", 0)), name,
                          "GitHub Actions · " + name,
                          "Etapa del job «{}». El API de jobs publica estados, no el comando shell ni el log completo.".format(job.get("name", "Job")))
            entry.update(status=github_stage_status(item.get("status"), item.get("conclusion")),
                         started_at=item.get("started_at"), completed_at=item.get("completed_at"))
            entry["logs"] = ["Estado fuente: {}; conclusión: {}.".format(item.get("status", "desconocido"), item.get("conclusion") or "pendiente"),
                             "Consultar el log completo en GitHub: " + (job.get("html_url") or state["url"])]
            state["stages"].append(entry)
    state["source_notes"] = ["Estados obtenidos de la API pública de GitHub Actions.",
                             "Los pasos desconocidos se conservan. Sólo se omite la limpieza automática de GitHub.",
                             "Omitido, cancelado o bloqueado no significa aprobado; el API no acredita tipos de pruebas que el workflow no ejecuta."]
    state["decisions"] = diagnose(state)
    return state


@dataclass
class StagePlan:
    identifier: str
    name: str
    description: str
    commands: list[list[str]]
    cwd: Path
    timeout: int = 900
    action: Callable[[], tuple[list[str], dict | None]] | None = None
    display_command: str | None = None


class PipelineRunner:
    """One process at a time, sequential stages, no arbitrary shell execution."""
    def __init__(self, mode: str):
        self.mode = mode
        self._lock = threading.RLock()
        self._state = empty_state(mode, "Sin ejecución " + mode)
        self._thread: threading.Thread | None = None

    def snapshot(self) -> dict:
        with self._lock:
            return copy.deepcopy(self._state)

    def start(self, plans: list[StagePlan], state: dict, background: bool = True) -> dict:
        with self._lock:
            if self._thread and self._thread.is_alive():
                raise RuntimeError("Ya existe una ejecución activa de este modo.")
            state["stages"] = [stage(p.identifier, p.name, p.display_command or " && ".join(" ".join(c) for c in p.commands), p.description) for p in plans]
            self._state = state
            if background:
                self._thread = threading.Thread(target=self._run, args=(plans,), daemon=True)
                self._thread.start()
            else:
                self._run(plans)
        return self.snapshot()

    def _log(self, index: int, lines: list[str]):
        with self._lock:
            logs = self._state["stages"][index]["logs"]
            logs.extend(lines)
            if len(logs) > 2500:
                logs[:] = ["[Log limitado a las últimas 2499 líneas]"] + logs[-2499:]

    def _command(self, index: int, command: list[str], cwd: Path, timeout: int) -> int:
        self._log(index, ["$ " + " ".join(command)])
        try:
            creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0) if os.name == "nt" else 0
            process = subprocess.Popen(command, cwd=str(cwd), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       encoding="utf-8", errors="replace", shell=False, creationflags=creationflags,
                                       start_new_session=os.name != "nt")
            try:
                output, _ = process.communicate(timeout=timeout)
            except subprocess.TimeoutExpired:
                if os.name == "nt":
                    try:
                        subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
                    except (OSError, subprocess.SubprocessError):
                        process.kill()
                else:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                output, _ = process.communicate()
                self._log(index, output.splitlines() + ["Tiempo máximo de etapa agotado: {} segundos.".format(timeout)])
                return 124
            self._log(index, output.splitlines() + ["Código de salida: {}".format(process.returncode)])
            return process.returncode
        except OSError as error:
            self._log(index, ["No se pudo iniciar el comando: " + str(error)])
            return 127

    def _run(self, plans: list[StagePlan]):
        with self._lock:
            self._state["status"] = "running"
        failed = False
        for index, plan in enumerate(plans):
            with self._lock:
                self._state["stages"][index].update(status="running", started_at=utc_now())
            code = 0
            try:
                for command in plan.commands:
                    code = self._command(index, command, plan.cwd, plan.timeout)
                    if code != 0:
                        break
                if code == 0 and plan.action:
                    lines, artifact = plan.action()
                    self._log(index, lines)
                    if artifact:
                        with self._lock:
                            self._state["artifacts"].append(artifact)
            except Exception as error:
                self._log(index, ["Error de etapa: " + str(error)])
                code = 1
            with self._lock:
                self._state["stages"][index].update(status="success" if code == 0 else "failure", completed_at=utc_now())
                if code != 0:
                    for later in self._state["stages"][index + 1:]:
                        later.update(status="blocked", logs=["No ejecutada: una etapa anterior falló (Fail Fast)."])
                    failed = True
                    break
        with self._lock:
            self._state.update(status="completed", conclusion="failure" if failed else "success")
            self._state["decisions"] = diagnose(self._state)


def tool_command(name: str) -> str:
    return shutil.which(name) or (name + (".bat" if name in {"dart", "flutter"} else ".cmd") if os.name == "nt" else name)


def find_flutter_project(repo_path: str) -> tuple[Path, Path]:
    if not isinstance(repo_path, str) or not repo_path.strip():
        raise ValueError("Indica la ruta local de SnackUP que contiene app/pubspec.yaml o pubspec.yaml.")
    root = Path(repo_path).expanduser().resolve()
    if not root.is_dir():
        raise ValueError("La carpeta indicada no existe.")
    app = root / "app" if (root / "app" / "pubspec.yaml").is_file() else root
    if not (app / "pubspec.yaml").is_file():
        raise ValueError("No se encontró app/pubspec.yaml ni pubspec.yaml; esta ruta no es un proyecto Flutter.")
    return root, app


def _git_value(root: Path, args: list[str]) -> str:
    try:
        return subprocess.check_output([tool_command("git"), "-C", str(root)] + args,
                                       stderr=subprocess.DEVNULL, encoding="utf-8", timeout=5).strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def package_web(app: Path, output: Path, sha: str) -> tuple[list[str], dict]:
    source = app / "build" / "web"
    if not (source / "index.html").is_file():
        raise RuntimeError("No existe build/web/index.html; no se puede empaquetar una compilación inexistente.")
    output.mkdir(parents=True, exist_ok=True)
    tag = re.sub(r"[^A-Za-z0-9_.-]", "_", sha[:12] or "local")
    destination = output / ("SnackUP-web-" + tag + ".zip")
    manifest = {"project": "SnackUP", "sha": sha, "created_at": utc_now(), "files": []}
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(source.rglob("*")):
            if path.is_file() and not path.is_symlink():
                relative = path.relative_to(source).as_posix()
                data = path.read_bytes()
                archive.writestr(relative, data)
                manifest["files"].append({"path": relative, "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)})
        archive.writestr("ci-manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    destination.with_suffix(".sha256").write_text(digest + "  " + destination.name + "\n", encoding="utf-8")
    return ["Artefacto: " + str(destination), "SHA-256: " + digest, "Archivos: " + str(len(manifest["files"]))], {"name": destination.name, "url": "", "path": str(destination), "sha256": digest}


def local_pipeline(repo_path: str) -> tuple[list[StagePlan], dict]:
    root, app = find_flutter_project(repo_path)
    flutter, dart, npm = tool_command("flutter"), tool_command("dart"), tool_command("npm")
    state = empty_state("local", "SnackUP · Pipeline local real", str(root))
    state.update(run_id="local-" + datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S"),
                 sha=_git_value(root, ["rev-parse", "HEAD"]), branch=_git_value(root, ["branch", "--show-current"]))
    state["source_notes"] = ["Comandos reales ejecutados secuencialmente en tu equipo. El agente no realiza push ni despliegue.",
                             "El SHA identifica HEAD; la ejecución usa el contenido local actual, que puede incluir cambios sin commit.",
                             "Flutter crea build/ y coverage/; el paquete final y su hash se guardan en .snackup-ci/.",
                             "El análisis permite warnings e infos para mantener compatibilidad con la línea base actual; los errores sí bloquean.",
                             "Si no existe tests/api/package.json con test:ci, la integración falla explícitamente."]
    format_targets = [folder for folder in ("lib", "test") if (app / folder).is_dir()]
    def require_format_targets():
        if not format_targets:
            raise RuntimeError("No existen lib/ ni test/ para verificar formato.")
        return [], None
    integration = root / "tests" / "api"
    def validate_integration():
        package = integration / "package.json"
        if not package.is_file():
            raise RuntimeError("Falta tests/api/package.json. No se ejecutaron pruebas de integración; agregar la suite antes de aprobar esta etapa.")
        data = json.loads(package.read_text(encoding="utf-8"))
        if not data.get("scripts", {}).get("test:ci"):
            raise RuntimeError("tests/api/package.json no define test:ci. No hay comando de integración verificable.")
        return ["Suite de integración detectada: " + str(package)], None
    # Check the integration suite inside its stage, so earlier results remain visible.
    integration_exists = (integration / "package.json").is_file()
    if integration_exists:
        try:
            integration_exists = bool(json.loads((integration / "package.json").read_text(encoding="utf-8")).get("scripts", {}).get("test:ci"))
        except (OSError, ValueError):
            integration_exists = False
    plans = [
        StagePlan("dependencies", "Dependencias", "Resolver dependencias Flutter con el lock del proyecto.", [[flutter, "pub", "get"]], app),
        StagePlan("format", "Formato Dart", "Verificar formato sin escribir cambios.", [[dart, "format", "--output=none", "--set-exit-if-changed"] + format_targets] if format_targets else [], app, action=require_format_targets),
        StagePlan("analyze", "Análisis estático", "Los errores bloquean; warnings e infos de la línea base quedan visibles.", [[flutter, "analyze", "--no-fatal-infos", "--no-fatal-warnings"]], app),
        StagePlan("unit", "Pruebas unitarias y widgets", "Ejecutar las pruebas Flutter existentes y generar cobertura, sin asumir que son de integración.", [[flutter, "test", "--coverage"]], app),
        StagePlan("build", "Compilación web", "Construir Flutter Web en release sin recursos CDN.", [[flutter, "build", "web", "--release", "--no-web-resources-cdn"]], app, timeout=1800),
        StagePlan("integration", "Pruebas de integración API", "Suite real tests/api con npm ci y npm run test:ci; ausencia de suite bloquea.", [[npm, "ci"], [npm, "run", "test:ci"]] if integration_exists else [], integration if integration_exists else root,
                  action=None if integration_exists else validate_integration,
                  display_command="npm ci && npm run test:ci · tests/api"),
        StagePlan("artifact", "Artefacto versionado", "Crear ZIP de build/web con manifest y SHA-256.", [], root,
                  action=lambda: package_web(app, root / ".snackup-ci", state["sha"]),
                  display_command="ZIP + manifest + SHA-256 (Python estándar)"),
    ]
    return plans, state


def demo_pipeline(fail_at: str | None) -> tuple[list[StagePlan], dict]:
    if fail_at not in {None, "unit"}:
        raise ValueError("fail_at debe ser unit o null.")
    directory = Path(tempfile.mkdtemp(prefix="snackup-ci-demo-"))
    fixture = 'def total(precio, cantidad):\n    return precio * cantidad\n'
    (directory / "pedido.py").write_text(fixture, encoding="utf-8")
    state = empty_state("demo", "SnackUP · Demostración aislada (no valida Flutter)", "Ejemplo Python aislado")
    state["run_id"] = "demo-" + datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    state["source_notes"] = ["DEMO: comandos Python reales sobre un ejemplo mínimo en una carpeta temporal.",
                             "No se ejecuta flutter analyze, flutter test ni el build de SnackUP.",
                             "El fallo de prueba se produce mediante un aserto real. Las etapas siguientes quedan bloqueadas."]
    def command(code: str) -> list[list[str]]:
        return [[sys.executable, "-c", "import time; time.sleep(0.65); " + code]]
    plans = [
        StagePlan("trigger", "Disparador de ejemplo", "Registrar una corrida didáctica, sin enviar commits.", command("print('DEMO: cambio de ejemplo recibido; no hubo push real.')"), directory, display_command="Python · registrar disparador de ejemplo"),
        StagePlan("dependencies", "Dependencias del ejemplo", "Comprobar módulos de la biblioteca estándar.", command("import json, zipfile, hashlib; print('DEMO: json, zipfile y hashlib disponibles.')"), directory, display_command="Python · importar módulos estándar"),
        StagePlan("analyze", "Análisis del ejemplo", "Validar sintaxis del archivo Python aislado mediante AST.", command("import ast, pathlib; ast.parse(pathlib.Path('pedido.py').read_text()); print('DEMO: sintaxis válida del ejemplo.')"), directory, display_command="Python · ast.parse(pedido.py)"),
        StagePlan("build", "Compilación del ejemplo", "Compilar a bytecode el archivo aislado.", command("import py_compile; py_compile.compile('pedido.py', doraise=True); print('DEMO: bytecode generado.')"), directory, display_command="Python · py_compile.compile(pedido.py)"),
        StagePlan("unit", "Prueba unitaria del ejemplo", "Comprobar el total de un pedido en el ejemplo mínimo.", command("from pedido import total; assert total(25, 2) == " + ("999" if fail_at == "unit" else "50") + ", 'El total esperado no coincide'; print('DEMO: total(25, 2) = 50 verificado.')"), directory, display_command="Python · assert total(25, 2) == " + ("999" if fail_at == "unit" else "50")),
        StagePlan("integration", "Integración del ejemplo", "Comprobar función + serialización JSON del ejemplo, sin Firebase ni API de SnackUP.", command("import json; from pedido import total; payload = json.loads(json.dumps({'total': total(25, 2)})); assert payload['total'] == 50; print('DEMO: cálculo y serialización JSON verificados.')"), directory, display_command="Python · cálculo + JSON del ejemplo"),
        StagePlan("artifact", "Artefacto del ejemplo", "Empaquetar sólo el archivo de ejemplo, sin generar artefactos Flutter.", command("import zipfile; z = zipfile.ZipFile('demo-pedido.zip', 'w'); z.write('pedido.py'); z.close(); print('DEMO: demo-pedido.zip generado en carpeta temporal.')"), directory, display_command="Python · ZIP del ejemplo aislado"),
    ]
    return plans, state
