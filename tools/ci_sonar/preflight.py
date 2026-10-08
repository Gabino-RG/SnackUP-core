#!/usr/bin/env python3
"""Check CI configuration before expensive Flutter steps; never display secrets."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.ci_notifications.notify_failure import UnsafeWebhook, validate_webhook_url


def cloud_host(value: str) -> str:
    parsed = urlsplit(value)
    if (parsed.scheme != "https" or parsed.hostname not in {"sonarcloud.io", "sonarqube.us"}
            or parsed.username or parsed.password or parsed.port not in (None, 443)
            or parsed.path not in {"", "/"} or parsed.query or parsed.fragment):
        raise ValueError("INVALID_SONAR_HOST_CONFIGURATION")
    return "https://" + parsed.hostname


def check(env: dict) -> dict:
    required = ("SONAR_TOKEN", "SONAR_ORGANIZATION", "SONAR_PROJECT_KEY", "CI_FAILURE_WEBHOOK_URL")
    missing = [name for name in required if not env.get(name, "").strip()]
    invalid = []
    provider = None
    try:
        host = cloud_host(env.get("SONAR_HOST_URL") or "https://sonarcloud.io")
    except ValueError:
        host = None
        invalid.append("SONAR_HOST_URL")
    for name in ("SONAR_ORGANIZATION", "SONAR_PROJECT_KEY"):
        if env.get(name) and not re.fullmatch(r"[A-Za-z0-9_.:-]+", env[name]):
            invalid.append(name)
    if env.get("CI_FAILURE_WEBHOOK_URL"):
        try:
            provider = validate_webhook_url(env["CI_FAILURE_WEBHOOK_URL"].strip())
        except UnsafeWebhook:
            invalid.append("CI_FAILURE_WEBHOOK_URL")
    return {
        "status": "BLOCKED" if missing or invalid else "READY",
        "missing": missing, "invalid": invalid,
        "sonar_host": host, "notification_provider": provider,
        "sonar_analysis_executed": False,
        "commit": env.get("GITHUB_SHA", ""),
        "note": "READY confirma configuración local; no acredita análisis ni entrega de mensajes.",
    }


def main() -> int:
    result = check(dict(os.environ))
    output = Path("sonar-evidence/preflight.json")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["status"] == "READY" else 1


if __name__ == "__main__":
    raise SystemExit(main())
