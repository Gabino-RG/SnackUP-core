#!/usr/bin/env python3
"""Poll the exact Sonar task and block CI unless its own Quality Gate is OK."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
from http.client import HTTPException
import json
import os
from pathlib import Path
import re
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import HTTPRedirectHandler, Request, build_opener

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.ci_sonar.preflight import cloud_host


class EvidenceError(ValueError):
    pass


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise EvidenceError("API_REDIRECT_REJECTED")


def report_metadata(path: Path, expected_host: str, expected_key: str) -> dict:
    try:
        values = dict(line.split("=", 1) for line in path.read_text(encoding="utf-8").splitlines()
                      if "=" in line and not line.startswith("#"))
        if (cloud_host(values.get("serverUrl", "")) != expected_host
                or values.get("projectKey") != expected_key
                or not re.fullmatch(r"[A-Za-z0-9_-]+", values.get("ceTaskId", ""))):
            raise EvidenceError("REPORT_METADATA_MISMATCH")
    except (OSError, ValueError):
        raise EvidenceError("REPORT_METADATA_INVALID") from None
    # Do not follow URLs from report-task.txt. Only call the configured origin.
    return {"projectKey": expected_key, "serverUrl": expected_host, "ceTaskId": values["ceTaskId"]}


def api_get(host: str, route: str, query: dict, token: str, opener) -> dict:
    request = Request(host + "/api/" + route + "?" + urlencode(query), headers={
        "Authorization": "Bearer " + token, "Accept": "application/json",
        "User-Agent": "SnackUP-CI-QualityGate/1.0",
    })
    try:
        with opener.open(request, timeout=20) as response:
            if response.getcode() != 200:
                raise EvidenceError("SONAR_API_HTTP_ERROR")
            raw = response.read(1048577)
        if len(raw) > 1048576:
            raise EvidenceError("SONAR_API_RESPONSE_TOO_LARGE")
        result = json.loads(raw)
        if not isinstance(result, dict):
            raise EvidenceError("SONAR_API_INVALID_RESPONSE")
        return result
    except HTTPError as error:
        # Keep only the numeric status. URLs, headers and response bodies may
        # contain credentials or attacker-controlled text and must stay private.
        code = error.code if isinstance(error.code, int) and 100 <= error.code <= 599 else "UNKNOWN"
        raise EvidenceError(f"SONAR_API_HTTP_{code}") from None
    except (URLError, OSError, HTTPException, UnicodeError, json.JSONDecodeError):
        # Never print the response or an exception that may contain credentials.
        raise EvidenceError("SONAR_API_REQUEST_FAILED") from None


def evaluate(report: Path, host: str, key: str, token: str, output: Path,
             timeout: int = 300, opener=None, clock=time.monotonic, pause=time.sleep) -> dict:
    output.mkdir(parents=True, exist_ok=True)
    receipt = {"scan_executed": False, "analysis_id": None, "gate_status": "UNKNOWN",
               "task_status": "UNKNOWN", "commit": os.environ.get("GITHUB_SHA", ""),
               "run_id": os.environ.get("GITHUB_RUN_ID", ""),
               "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "1"),
               "timestamp_utc": datetime.now(timezone.utc).isoformat(timespec="seconds")}
    try:
        if not token:
            raise EvidenceError("SONAR_TOKEN_NOT_SET")
        host = cloud_host(host)
        metadata = report_metadata(report, host, key)
        # Preserve only whitelisted report metadata; scanner tokens are never stored.
        (output / "report-task.txt").write_text("\n".join(f"{k}={v}" for k, v in metadata.items()) + "\n", encoding="utf-8")
        receipt.update(task_id=metadata["ceTaskId"], project_key=key, sonar_host=host)
        opener = opener or build_opener(NoRedirect())
        deadline = clock() + timeout
        while True:
            data = api_get(host, "ce/task", {"id": metadata["ceTaskId"]}, token, opener)
            task = data.get("task", {})
            if (not isinstance(task, dict) or task.get("id") != metadata["ceTaskId"]
                    or task.get("componentKey") != key):
                raise EvidenceError("SONAR_TASK_MISMATCH")
            receipt["task_status"] = task.get("status", "UNKNOWN")
            safe_task = {key: task.get(key) for key in (
                "id", "status", "analysisId", "componentKey", "submittedAt", "startedAt", "executedAt")}
            (output / "background-task.json").write_text(json.dumps({"task": safe_task}, indent=2) + "\n", encoding="utf-8")
            if task.get("status") not in {"PENDING", "IN_PROGRESS"}:
                break
            if clock() >= deadline:
                raise EvidenceError("SONAR_BACKGROUND_TASK_TIMEOUT")
            pause(min(5, max(0, deadline - clock())))
        analysis_id = task.get("analysisId", "")
        if (task.get("status") != "SUCCESS" or not isinstance(analysis_id, str)
                or not re.fullmatch(r"[A-Za-z0-9_-]+", analysis_id)):
            raise EvidenceError("SONAR_BACKGROUND_TASK_NOT_SUCCESSFUL")
        receipt.update(scan_executed=True, analysis_id=analysis_id)
        data = api_get(host, "qualitygates/project_status", {"analysisId": analysis_id}, token, opener)
        project = data.get("projectStatus", {})
        if not isinstance(project, dict):
            raise EvidenceError("SONAR_GATE_INVALID_RESPONSE")
        receipt["gate_status"] = project.get("status", "UNKNOWN")
        conditions = project.get("conditions", [])
        if not isinstance(conditions, list) or any(not isinstance(item, dict) for item in conditions):
            raise EvidenceError("SONAR_GATE_INVALID_RESPONSE")
        receipt["conditions"] = [
            {k: item.get(k) for k in ("status", "metricKey", "comparator", "errorThreshold", "actualValue")}
            for item in conditions]
        receipt["ignored_conditions"] = project.get("ignoredConditions")
        receipt["status"] = "PASSED" if receipt["gate_status"] == "OK" else "FAILED"
    except (EvidenceError, ValueError) as error:
        # Messages originate exclusively in our fixed-code exceptions.
        receipt.update(status="FAILED", reason=str(error) if isinstance(error, EvidenceError) else "INVALID_CONFIGURATION")
    (output / "quality-gate.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, default=Path("app/.scannerwork/report-task.txt"))
    parser.add_argument("--outdir", type=Path, default=Path("sonar-evidence"))
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()
    result = evaluate(args.report, os.environ.get("SONAR_HOST_URL") or "https://sonarcloud.io",
                      os.environ.get("SONAR_PROJECT_KEY", ""), os.environ.get("SONAR_TOKEN", ""),
                      args.outdir, timeout=max(1, min(args.timeout, 600)))
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result.get("status") == "PASSED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
