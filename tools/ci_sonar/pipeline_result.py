#!/usr/bin/env python3
"""Preserve public step outcomes and emit the first failure for the alert job."""
import json
import os
from pathlib import Path

steps = json.loads(os.environ.get("CI_STEPS_JSON", "{}"))
public = {name: {"outcome": value.get("outcome"), "conclusion": value.get("conclusion")}
          for name, value in steps.items()}
failures = [name for name, value in public.items() if value["outcome"] == "failure"]
record = {
    "repository": os.environ.get("GITHUB_REPOSITORY"),
    "run_id": os.environ.get("GITHUB_RUN_ID"),
    "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "1"),
    "commit": os.environ.get("GITHUB_SHA"),
    "failed_stage": failures[0] if failures else "",
    "controlled_failure": "controlled_failure" in failures,
    "controlled_failure_requested": os.environ.get("CI_EVIDENCE_CONTROLLED_FAILURE") == "true",
    "steps": public,
}
Path("sonar-evidence").mkdir(exist_ok=True)
Path("sonar-evidence/pipeline-result.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
if os.environ.get("GITHUB_OUTPUT"):
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as stream:
        stream.write("failed_stage=" + record["failed_stage"] + "\n")
        stream.write("controlled_failure=" + ("true" if record["controlled_failure"] else "false") + "\n")
print(json.dumps(record))
