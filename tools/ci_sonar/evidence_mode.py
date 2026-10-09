#!/usr/bin/env python3
"""Opt-in controlled failure confined to evidence-branch push and PR events."""
import json
import os
from pathlib import Path


def requested(env: dict, marker: dict) -> bool:
    if env.get("GITHUB_EVENT_NAME") == "workflow_dispatch":
        return env.get("EVIDENCE_FAILURE_INPUT", "false") == "true"
    if marker.get("enabled") is not True:
        return False
    if env.get("GITHUB_EVENT_NAME") == "push":
        return env.get("GITHUB_REF_NAME") == "feature/ci-sonar-notifications"
    return (env.get("GITHUB_EVENT_NAME") == "pull_request"
            and env.get("GITHUB_HEAD_REF") == "feature/ci-sonar-notifications"
            and env.get("GITHUB_BASE_REF") in {"main", "master"})


def main() -> int:
    path = Path("docs/ci-parte-2/failure-test.json")
    marker = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"enabled": False}
    if not isinstance(marker, dict) or type(marker.get("enabled")) is not bool:
        print("INVALID_CONTROLLED_FAILURE_MARKER")
        return 1
    value = "true" if requested(dict(os.environ), marker) else "false"
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write("enabled=" + value + "\n")
    print("Fallo controlado solicitado: " + value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
