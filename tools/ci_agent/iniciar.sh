#!/usr/bin/env bash
set -eu
cd -- "$(dirname -- "$0")"
if command -v python3 >/dev/null 2>&1; then
  exec python3 server.py "$@"
fi
echo "Instala Python 3.10 o posterior para iniciar el agente." >&2
exit 1
