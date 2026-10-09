#!/usr/bin/env python3
"""Load actual run IDs for manual or branch-only video recording."""
import json
import os
from pathlib import Path
import re


def main() -> int:
    if os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch":
        data = {"success_run": os.environ.get("EVIDENCE_SUCCESS_RUN"), "failure_run": os.environ.get("EVIDENCE_FAILURE_RUN")}
    else:
        data = json.loads(Path("docs/ci-parte-2/evidence-runs.json").read_text(encoding="utf-8"))
    if not isinstance(data, dict) or any(not re.fullmatch(r"[1-9][0-9]{0,19}", str(data.get(key, "")))
                                         for key in ("success_run", "failure_run")):
        print("INVALID_EVIDENCE_RUN_IDS")
        return 1
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        for key in ("success_run", "failure_run"):
            output.write(key + "=" + str(data[key]) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
