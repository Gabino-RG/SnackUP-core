#!/usr/bin/env python3
"""SnackUP CI visual agent: local HTTP server with no third-party dependency."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

from engine import PipelineRunner, demo_pipeline, local_pipeline, normalize_github_run

ROOT = Path(__file__).resolve().parent
LOCAL = PipelineRunner("local")
DEMO = PipelineRunner("demo")
REPO_PATTERN = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
RUN_CACHE = {}
RUN_CACHE_LOCK = threading.Lock()


def github_get(path: str):
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "SnackUP-CI-Agent",
               "X-GitHub-Api-Version": "2022-11-28"}
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if token:
        headers["Authorization"] = "Bearer " + token
    request = urllib.request.Request("https://api.github.com" + path, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code in {403, 429}:
            raise RuntimeError("GitHub rechazó la consulta (permisos o límite de peticiones). Espera o configura GITHUB_TOKEN con acceso de lectura.") from error
        if error.code == 404:
            raise RuntimeError("GitHub no encontró el repositorio o la ejecución, o requiere permiso de lectura.") from error
        raise RuntimeError("GitHub devolvió HTTP {}.".format(error.code)) from error
    except (urllib.error.URLError, TimeoutError, ValueError) as error:
        raise RuntimeError("No se pudo consultar GitHub. Revisa tu conexión o usa la evidencia guardada.") from error


def read_repository(query: dict) -> str:
    repository = query.get("repo", ["Gabino-RG/SnackUP-core"])[0]
    if not REPO_PATTERN.fullmatch(repository):
        raise ValueError("Repositorio inválido. Usa propietario/repositorio.")
    return repository


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT / "web"), **kwargs)

    def json_response(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urllib.parse.urlsplit(self.path)
        if not parsed.path.startswith("/api/"):
            return super().do_GET()
        query = urllib.parse.parse_qs(parsed.query)
        try:
            if parsed.path == "/api/evidence":
                case = query.get("case", ["success"])[0]
                if case not in {"success", "failure"}:
                    raise ValueError("case debe ser success o failure.")
                filename = "evidence-failure.json" if case == "failure" else "evidence.json"
                path = ROOT / "evidence" / filename
                if not path.is_file():
                    return self.json_response({"error": "No se encontró la evidencia guardada de este caso."}, 404)
                return self.json_response(json.loads(path.read_text(encoding="utf-8")))
            if parsed.path == "/api/local":
                return self.json_response(LOCAL.snapshot())
            if parsed.path == "/api/demo":
                return self.json_response(DEMO.snapshot())
            if parsed.path == "/api/runs":
                repository = read_repository(query)
                data = github_get("/repos/" + repository + "/actions/runs?per_page=20")
                fields = ("id", "name", "status", "conclusion", "head_branch", "head_sha", "html_url", "created_at")
                return self.json_response({"runs": [{key: run.get(key) for key in fields} for run in data.get("workflow_runs", [])]})
            if parsed.path == "/api/run":
                repository = read_repository(query)
                run_id = query.get("id", [""])[0]
                if not run_id.isdigit():
                    raise ValueError("Falta un id numérico de ejecución.")
                cache_key = repository + "/" + run_id
                with RUN_CACHE_LOCK:
                    cached = RUN_CACHE.get(cache_key)
                    if cached and cached[0] > time.monotonic():
                        return self.json_response(cached[1])
                base = "/repos/" + repository + "/actions/runs/" + run_id
                run = github_get(base)
                jobs = []
                for page in range(1, 11):
                    data = github_get(base + "/jobs?per_page=100&page=" + str(page))
                    page_jobs = data.get("jobs", [])
                    jobs.extend(page_jobs)
                    if len(page_jobs) < 100:
                        break
                result = normalize_github_run(run, jobs, repository)
                if result["status"] == "completed":
                    try:
                        artifacts = github_get(base + "/artifacts?per_page=100").get("artifacts", [])
                        result["artifacts"] = [{"name": item.get("name", "Artefacto"), "url": run.get("html_url", ""),
                                                 "expired": bool(item.get("expired")), "size_in_bytes": item.get("size_in_bytes")} for item in artifacts]
                    except RuntimeError:
                        result["source_notes"].append("No se pudo consultar la lista de artefactos; no se asume que no existan.")
                result["source_notes"].append("Consulta en vivo con caché de 15 segundos durante ejecución y 60 segundos al terminar.")
                with RUN_CACHE_LOCK:
                    RUN_CACHE[cache_key] = (time.monotonic() + (60 if result["status"] == "completed" else 15), result)
                return self.json_response(result)
            return self.json_response({"error": "Ruta API desconocida."}, 404)
        except ValueError as error:
            return self.json_response({"error": str(error)}, 400)
        except RuntimeError as error:
            return self.json_response({"error": str(error)}, 502)
        except Exception as error:
            return self.json_response({"error": "Error al leer los datos: " + str(error)}, 500)

    def do_POST(self):
        # Only the visible local page may start commands. Cross-site requests are rejected.
        host = self.headers.get("Host", "")
        if host not in {"127.0.0.1:" + str(self.server.server_port), "localhost:" + str(self.server.server_port)}:
            return self.json_response({"error": "Origen local requerido."}, 403)
        origin = self.headers.get("Origin")
        if origin and origin not in {"http://127.0.0.1:" + str(self.server.server_port), "http://localhost:" + str(self.server.server_port)}:
            return self.json_response({"error": "Origen local requerido."}, 403)
        if self.headers.get("Content-Type", "").split(";")[0].strip() != "application/json":
            return self.json_response({"error": "Usa Content-Type application/json."}, 415)
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length < 0 or length > 16384:
                raise ValueError("Solicitud demasiado grande.")
            data = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
            if not isinstance(data, dict):
                raise ValueError("Se requiere un objeto JSON.")
            path = urllib.parse.urlsplit(self.path).path
            if path == "/api/demo":
                plans, state = demo_pipeline(data.get("fail_at"))
                return self.json_response(DEMO.start(plans, state), 202)
            if path == "/api/local":
                plans, state = local_pipeline(data.get("repo_path", ""))
                return self.json_response(LOCAL.start(plans, state), 202)
            return self.json_response({"error": "Ruta API desconocida."}, 404)
        except (ValueError, UnicodeError) as error:
            return self.json_response({"error": str(error)}, 400)
        except RuntimeError as error:
            return self.json_response({"error": str(error)}, 409)


def main():
    parser = argparse.ArgumentParser(description="Agente gráfico de CI SnackUP")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--no-browser", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("El puerto debe estar entre 1 y 65535.")
    try:
        server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    except OSError as error:
        parser.exit(1, "No se pudo abrir el servidor: {}\nPrueba: python server.py --port 8766\n".format(error))
    url = "http://127.0.0.1:{}/".format(args.port)
    print("SnackUP CI Agent: " + url, flush=True)
    print("Ctrl+C para cerrar. Evidencia guardada disponible sin internet.", flush=True)
    if not args.no_browser:
        threading.Timer(0.4, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServidor cerrado.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
