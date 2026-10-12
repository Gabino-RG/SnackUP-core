#!/usr/bin/env python3
"""Build main.dart and package it with the supplied Windows embedded runtime."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


REPO = Path(__file__).resolve().parents[2]
APP = REPO / "app"
TEMPLATES = REPO / "scripts" / "pc"
PACKAGE_NAME = "SnackUP-PC"
MAX_ZIP_BYTES = 50 * 1024 * 1024


def command(arguments, cwd=REPO, capture=False):
    return subprocess.run(
        [str(item) for item in arguments], cwd=cwd, check=True, text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    ).stdout


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def extract_runtime(archive, destination):
    with ZipFile(archive) as runtime:
        members = runtime.infolist()
        names = {item.filename for item in members}
        if not {"python.exe", "python3.dll", "LICENSE.txt"}.issubset(names):
            raise ValueError("El ZIP no parece un runtime embedded de Python para Windows.")
        if not any(re.fullmatch(r"python3\d+\._pth", name) for name in names):
            raise ValueError("El runtime no contiene su configuracion aislada ._pth.")
        if sum(item.file_size for item in members) > 150 * 1024 * 1024:
            raise ValueError("El runtime descomprimido supera el tamano esperado.")
        for item in members:
            name = PurePosixPath(item.filename)
            if (name.is_absolute() or ".." in name.parts or "\\" in item.filename
                    or ":" in item.filename or stat.S_ISLNK(item.external_attr >> 16)):
                raise ValueError("El runtime contiene una ruta no permitida.")
        bad_file = runtime.testzip()
        if bad_file:
            raise ValueError(f"El runtime esta danado: {bad_file}")
        runtime.extractall(destination)


def check_source_archive(archive):
    # Only tracked files are archived. Refuse obvious credentials if a future
    # change accidentally commits them; Firebase's public client config is valid.
    with ZipFile(archive) as source:
        for item in source.infolist():
            path = PurePosixPath(item.filename)
            name = path.name.lower()
            if (name == ".env" or (name.startswith(".env.") and not name.endswith(".example"))
                    or path.suffix.lower() in {".pem", ".p12", ".pfx", ".key"}
                    or (name.endswith(".json") and
                        any(part in name for part in ("service-account", "service_account", "serviceaccount")))):
                raise ValueError(f"Revisa el archivo potencialmente sensible versionado: {path}")
            if item.file_size < 5 * 1024 * 1024 and path.suffix.lower() in {".json", ".txt", ".yaml", ".yml"}:
                payload = source.read(item)
                if re.search(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----", payload):
                    raise ValueError(f"No se empaquetan claves privadas: {path}")


def write_package_zip(root, output, timestamp):
    # Fixed ordering, timestamps and permissions make the packaging step stable.
    # Flutter/compiler versions and generated web bytes still affect the result.
    date_time = time.gmtime(max(timestamp, 315532800))[:6]
    with ZipFile(output, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(root.rglob("*")):
            if not path.is_file():
                continue
            info = ZipInfo(str(PurePosixPath(PACKAGE_NAME) / path.relative_to(root).as_posix()), date_time)
            info.compress_type = ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | 0o644) << 16
            archive.writestr(info, path.read_bytes(), compress_type=ZIP_DEFLATED, compresslevel=9)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path,
                        default=REPO.parent / "pc-package" / "python-3.14.8-embed-amd64.zip",
                        help="ZIP oficial de Python embedded Windows x64, previamente descargado.")
    parser.add_argument("--output", type=Path,
                        default=REPO.parent / "pc-package" / "SnackUP-PC.zip",
                        help="Ruta del ZIP final (por defecto, fuera del repositorio).")
    parser.add_argument("--flutter", default=shutil.which("flutter") or
                        str(REPO.parent / "tools" / "flutter" / "bin" / "flutter"),
                        help="Ejecutable Flutter.")
    parser.add_argument("--no-pub", action="store_true",
                        help="Usar dependencias ya resueltas, sin ejecutar pub get durante build.")
    options = parser.parse_args()
    runtime = options.runtime.expanduser().resolve()
    output = options.output.expanduser().resolve()
    if not runtime.is_file():
        raise ValueError(f"Falta el runtime embedded: {runtime}")
    if output.suffix.lower() != ".zip":
        raise ValueError("La ruta de salida debe terminar en .zip.")
    if output == runtime or output.is_relative_to(REPO):
        raise ValueError("Guarda el ZIP fuera del checkout y separado del runtime original.")
    if command(["git", "status", "--porcelain"], capture=True).strip():
        raise ValueError("El checkout debe estar limpio: confirma primero los cambios en nuestra rama.")

    commit = command(["git", "rev-parse", "HEAD"], capture=True).strip()
    branch = command(["git", "branch", "--show-current"], capture=True).strip()
    commit_time = int(command(["git", "show", "-s", "--format=%ct", "HEAD"], capture=True).strip())
    flutter_version = json.loads(command([options.flutter, "--version", "--machine"], capture=True))
    output.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="snackup-pc-", dir=output.parent) as temporary:
        stage = Path(temporary) / PACKAGE_NAME
        stage.mkdir()
        extract_runtime(runtime, stage / "runtime")
        command(["git", "archive", "--format=zip", "--prefix=SnackUP-core/",
                 f"--output={stage / 'codigo_fuente.zip'}", commit])
        check_source_archive(stage / "codigo_fuente.zip")

        arguments = [options.flutter, "build", "web", "--release", "--no-web-resources-cdn",
                     "-t", "lib/main.dart", "-o", "build/pc-release"]
        if options.no_pub:
            arguments.append("--no-pub")
        command(arguments, cwd=APP)
        # A concurrently edited checkout must never be labelled as the old commit.
        if (command(["git", "status", "--porcelain"], capture=True).strip()
                or command(["git", "rev-parse", "HEAD"], capture=True).strip() != commit):
            raise ValueError("El checkout cambio durante la compilacion. Confirma los cambios y repite.")
        shutil.copytree(APP / "build" / "pc-release", stage / "web")
        for name in ("start_snackup.py", "LEEME.txt"):
            shutil.copyfile(TEMPLATES / name, stage / name)
        cmd = (TEMPLATES / "INICIAR_SNACKUP.cmd").read_text(encoding="utf-8")
        (stage / "INICIAR_SNACKUP.cmd").write_bytes(cmd.replace("\r\n", "\n").replace("\n", "\r\n").encode("ascii"))
        (stage / "documentos").mkdir()
        shutil.copyfile(REPO / "docs" / "PC.md", stage / "documentos" / "PC.md")
        shutil.copytree(REPO / "docs" / "admin", stage / "documentos" / "admin")
        for name in ("INTEGRACION.md", "VALIDACION_INTEGRADA.md"):
            source = REPO / "docs" / name
            if source.is_file():
                shutil.copyfile(source, stage / "documentos" / name)
        if (REPO / "docs" / "security").is_dir():
            shutil.copytree(REPO / "docs" / "security", stage / "documentos" / "security")
        metadata = {
            "application": "SnackUP", "entrypoint": "app/lib/main.dart",
            "mode": "firebase_connected", "branch": branch, "commit": commit,
            "default_origin": "http://localhost:8790",
            "flutter_version": flutter_version.get("frameworkVersion"),
            "dart_version": flutter_version.get("dartSdkVersion"),
            "runtime_archive": runtime.name, "runtime_sha256": digest(runtime),
            "native_windows_validation": "pending",
            "firebase_activation": "requires_project_review_see_docs",
        }
        (stage / "VERSION.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        hashes = [f"{digest(path)}  {path.relative_to(stage).as_posix()}"
                  for path in sorted(stage.rglob("*")) if path.is_file()]
        (stage / "SHA256SUMS.txt").write_text("\n".join(hashes) + "\n", encoding="utf-8")
        packed = Path(temporary) / output.name
        write_package_zip(stage, packed, commit_time)
        if packed.stat().st_size >= MAX_ZIP_BYTES:
            raise ValueError("El ZIP alcanza 50 MiB; revisa los assets antes de distribuirlo.")
        with ZipFile(packed) as archive:
            if archive.testzip() is not None:
                raise ValueError("Fallo la comprobacion de integridad del paquete final.")
        os.replace(packed, output)
    print(f"Paquete creado: {output}")
    print(f"Tamano: {output.stat().st_size / 1024 / 1024:.1f} MiB; commit: {commit}")
    print(f"SHA256: {digest(output)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"No se pudo preparar SnackUP-PC: {error}", file=sys.stderr)
        raise SystemExit(1)
