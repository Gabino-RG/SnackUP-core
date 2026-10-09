#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Uso: $0 PORCENTAJE_MINIMO [RUTA_LCOV]" >&2
  exit 2
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
coverage_file="${2:-$repo_root/app/coverage/lcov.info}"

python3 - "$1" "$coverage_file" <<'PY'
import math
import sys
from pathlib import Path


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(2)


try:
    threshold = float(sys.argv[1])
except ValueError:
    fail("El porcentaje mínimo debe ser un número entre 0 y 100.")
if not math.isfinite(threshold) or not 0 <= threshold <= 100:
    fail("El porcentaje mínimo debe ser un número entre 0 y 100.")

try:
    report = Path(sys.argv[2]).read_text(encoding="utf-8")
except (OSError, UnicodeError) as exc:
    fail(f"No se pudo leer el informe de cobertura: {exc}")

source = None
lines = {}
for entry in report.splitlines():
    if entry.startswith("SF:"):
        source = entry[3:]
        if not source:
            fail("Informe LCOV inválido: falta la ruta del archivo fuente.")
    elif entry == "end_of_record":
        source = None
    elif entry.startswith("DA:"):
        if source is None:
            fail("Informe LCOV inválido: línea DA sin archivo fuente.")
        try:
            fields = entry[3:].split(",")
            if len(fields) not in (2, 3):
                raise ValueError
            line_number, hits = int(fields[0]), int(fields[1])
            if line_number < 1 or hits < 0:
                raise ValueError
        except ValueError:
            fail(f"Informe LCOV inválido: {entry}")
        key = (source, line_number)
        lines[key] = lines.get(key, False) or hits > 0

if not lines:
    fail("El informe LCOV no contiene líneas de cobertura válidas.")

covered = sum(lines.values())
percentage = covered / len(lines) * 100
print(f"Cobertura: {percentage:.2f}% ({covered}/{len(lines)} líneas); "
      f"mínimo: {threshold:g}%.")
if percentage < threshold:
    print("La cobertura no alcanza el umbral solicitado.", file=sys.stderr)
    sys.exit(1)
PY
