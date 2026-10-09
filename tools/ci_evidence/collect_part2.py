#!/usr/bin/env python3
"""Collect authenticated CI evidence without inventing a scan or notification.

Reads two completed GitHub Actions runs and their public audit artifacts. The
token is used only with api.github.com. ZIP files are inspected in memory; no
untrusted member is extracted. Only selected, verified public fields are saved.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timedelta
from http.client import HTTPException
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
import zipfile


API_ROOT = "https://api.github.com"
MAX_JSON_BYTES = 8 * 1024 * 1024
MAX_ZIP_BYTES = 25 * 1024 * 1024
MAX_MEMBER_BYTES = 4 * 1024 * 1024
AUDIT_FILES = {"quality-gate.json", "background-task.json", "report-task.txt", "pipeline-result.json"}


class EvidenceError(ValueError):
    """A generic error safe for CI logs; never include a secret URL or token."""


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def repository_name(value: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
        raise EvidenceError("INVALID_REPOSITORY")
    return value


def download_host(url: str) -> bool:
    """Artifact redirects are allowed only to GitHub's expected storage hosts."""
    try:
        value = urlsplit(url)
        host = (value.hostname or "").lower()
        return (value.scheme == "https" and value.port in (None, 443)
                and not value.username and not value.password and not value.fragment
                and (host == "api.github.com" or host.endswith(".blob.core.windows.net")
                     or host.endswith(".amazonaws.com") or host.endswith(".githubusercontent.com")))
    except ValueError:
        return False


class GitHubClient:
    def __init__(self, token: str, opener=None):
        if not token:
            raise EvidenceError("GITHUB_TOKEN_NOT_SET")
        self._token = token
        self._opener = opener or build_opener(NoRedirect())

    def _get(self, url: str, limit: int, authorized: bool = True) -> bytes:
        if authorized and not url.startswith(API_ROOT + "/"):
            raise EvidenceError("UNSAFE_API_ORIGIN")
        if not authorized and not download_host(url):
            raise EvidenceError("UNSAFE_ARTIFACT_ORIGIN")
        headers = {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28",
                   "User-Agent": "SnackUP-CI-Evidence/2.0"}
        if authorized:
            headers["Authorization"] = "Bearer " + self._token
        request = Request(url, headers=headers, method="GET")
        try:
            with self._opener.open(request, timeout=45) as response:
                payload = response.read(limit + 1)
            if len(payload) > limit:
                raise EvidenceError("RESPONSE_TOO_LARGE")
            return payload
        except HTTPError as error:
            if error.code in (301, 302, 303, 307, 308) and limit == MAX_ZIP_BYTES and authorized:
                target = error.headers.get("Location", "")
                # Deliberately drop Authorization when following storage redirects.
                return self._get(target, limit, authorized=False)
            raise EvidenceError("GITHUB_HTTP_ERROR_" + str(error.code)) from None
        except EvidenceError:
            raise
        except (URLError, OSError, ValueError, HTTPException):
            raise EvidenceError("GITHUB_REQUEST_FAILED") from None

    def get_json(self, path: str) -> dict:
        if not path.startswith("/repos/") or "#" in path:
            raise EvidenceError("INVALID_API_PATH")
        try:
            result = json.loads(self._get(API_ROOT + path, MAX_JSON_BYTES))
        except (UnicodeError, json.JSONDecodeError):
            raise EvidenceError("INVALID_GITHUB_JSON") from None
        if not isinstance(result, dict):
            raise EvidenceError("INVALID_GITHUB_JSON")
        return result

    def pages(self, path: str, key: str) -> list[dict]:
        result = []
        separator = "&" if "?" in path else "?"
        for page in range(1, 101):
            response = self.get_json(path + separator + f"per_page=100&page={page}")
            items = response.get(key)
            if not isinstance(items, list) or not all(isinstance(item, dict) for item in items):
                raise EvidenceError("INVALID_GITHUB_LIST")
            result.extend(items)
            if len(items) < 100:
                return result
        raise EvidenceError("GITHUB_PAGINATION_LIMIT")

    def artifact(self, repository: str, artifact_id: int) -> bytes:
        return self._get(f"{API_ROOT}/repos/{repository}/actions/artifacts/{artifact_id}/zip", MAX_ZIP_BYTES)


def zip_members(payload: bytes, wanted: set[str]) -> dict[str, bytes]:
    """Reject traversal, symlinks, duplicate evidence, bombs and oversized ZIPs."""
    if len(payload) > MAX_ZIP_BYTES:
        raise EvidenceError("ARTIFACT_TOO_LARGE")
    result = {}
    try:
        with zipfile.ZipFile(io.BytesIO(payload)) as archive:
            members = archive.infolist()
            if len(members) > 250 or sum(item.file_size for item in members) > MAX_ZIP_BYTES:
                raise EvidenceError("UNSAFE_ARTIFACT_SIZE")
            for member in members:
                name = member.filename
                path = PurePosixPath(name)
                if (path.is_absolute() or ".." in path.parts or "\\" in name
                        or "\x00" in name or re.match(r"^[A-Za-z]:", name)
                        or stat.S_ISLNK(member.external_attr >> 16)):
                    raise EvidenceError("UNSAFE_ARTIFACT_MEMBER")
                if member.is_dir():
                    continue
                if member.file_size > MAX_MEMBER_BYTES or member.flag_bits & 1:
                    raise EvidenceError("UNSAFE_ARTIFACT_MEMBER")
                if path.name in wanted:
                    if path.name in result:
                        raise EvidenceError("DUPLICATE_EVIDENCE_MEMBER")
                    result[path.name] = archive.read(member)
    except (zipfile.BadZipFile, RuntimeError, OSError):
        raise EvidenceError("INVALID_ARTIFACT_ZIP") from None
    return result


def read_object(payload: bytes | None, name: str) -> dict:
    if payload is None:
        raise EvidenceError("MISSING_EVIDENCE_" + name.upper().replace(".", "_"))
    try:
        value = json.loads(payload)
    except (UnicodeError, json.JSONDecodeError):
        raise EvidenceError("INVALID_EVIDENCE_JSON") from None
    if not isinstance(value, dict):
        raise EvidenceError("INVALID_EVIDENCE_JSON")
    return value


def github_status(status, conclusion) -> str:
    if status in {"queued", "requested", "waiting", "pending"}:
        return "pending"
    if status == "in_progress":
        return "running"
    return {"success": "success", "failure": "failure", "timed_out": "failure",
            "startup_failure": "failure", "cancelled": "cancelled", "stale": "cancelled",
            "skipped": "skipped", "neutral": "skipped", "action_required": "blocked"}.get(conclusion, "blocked")


def normalize(run: dict, jobs: list[dict], repository: str) -> dict:
    """Same state contract as tools/ci_agent/engine.py; unknown steps stay visible."""
    stages = []
    for job in jobs:
        for item in job.get("steps") or []:
            name = item.get("name", "Etapa sin nombre")
            if name.lower().startswith("post ") or name.lower() in {"complete job", "cleanup", "clean up job"}:
                continue
            stages.append({
                "id": f"gh-{job.get('id')}-{item.get('number')}", "name": name,
                "status": github_status(item.get("status"), item.get("conclusion")),
                "command": "GitHub Actions · " + name,
                "description": "Paso publicado por GitHub del job «" + job.get("name", "") + "».",
                "started_at": item.get("started_at"), "completed_at": item.get("completed_at"),
                "job_id": job.get("id"), "step_number": item.get("number"),
                "logs": ["Estado fuente: " + str(item.get("status")) + "; conclusión: " + str(item.get("conclusion")),
                         "Log original: " + (job.get("html_url") or run["html_url"])],
            })
    state = {
        "mode": "live", "repository": repository, "run_id": run["id"],
        "sha": run["head_sha"], "branch": run.get("head_branch", ""), "url": run["html_url"],
        "title": run.get("name", "SnackUP CI"), "status": "completed", "conclusion": run["conclusion"],
        "stages": stages, "decisions": [], "artifacts": [],
        "source_notes": ["Estados y tiempos originales de la API de GitHub Actions; limpieza automática omitida.",
                         "Escaneo y Quality Gate acreditados por artefactos del mismo run y commit.",
                         "DELIVERED acredita aceptación del servidor; no acredita lectura de una persona."],
    }
    return state


def observed_step(state: dict, pattern: str, status: str = "success") -> dict:
    matching = [step for step in state["stages"] if re.search(pattern, step["name"], re.I) and step["status"] == status]
    if len(matching) != 1:
        raise EvidenceError("REQUIRED_STEP_NOT_UNAMBIGUOUS")
    return matching[0]


def safe_dashboard(value) -> str | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = urlsplit(value)
        if (parsed.scheme == "https" and parsed.hostname and not parsed.username and not parsed.password
                and parsed.port in (None, 443) and not parsed.fragment
                and not re.search(r"(?:token|password|secret|auth)=", parsed.query, re.I)):
            return value
    except ValueError:
        pass
    return None


def parse_report(payload: bytes | None) -> dict:
    if payload is None:
        raise EvidenceError("MISSING_REPORT_TASK")
    try:
        content = payload.decode("utf-8")
    except UnicodeError:
        raise EvidenceError("INVALID_REPORT_TASK") from None
    result = {}
    for line in content.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            if key in {"ceTaskId", "dashboardUrl", "projectKey", "serverUrl"}:
                if key in result:
                    raise EvidenceError("DUPLICATE_REPORT_TASK_FIELD")
                result[key] = value.strip()
    if not re.fullmatch(r"[A-Za-z0-9_-]{5,200}", result.get("ceTaskId", "")):
        raise EvidenceError("INVALID_CE_TASK_ID")
    return result


def confirm_source(source: dict, run: dict, repository: str, label: str) -> None:
    required = {"repository": repository, "run_id": str(run["id"]),
                "run_attempt": str(run.get("run_attempt", 1)), "commit": run["head_sha"]}
    aliases = {"repository": ("repository",), "run_id": ("run_id",),
               "run_attempt": ("run_attempt",), "commit": ("commit", "sha", "head_sha")}
    for key, expected in required.items():
        value = next((source[name] for name in aliases[key] if name in source), None)
        if str(value) != expected:
            raise EvidenceError(label + "_SOURCE_MISMATCH")


def verify_sonar(files: dict[str, bytes], run: dict, repository: str, state: dict, success: bool) -> dict:
    pipeline = read_object(files.get("pipeline-result.json"), "pipeline-result.json")
    confirm_source(pipeline, run, repository, "PIPELINE")
    outcomes = pipeline.get("steps", {})
    if (not isinstance(outcomes, dict) or not all(isinstance(value, dict) for value in outcomes.values())
            or outcomes.get("sonar", {}).get("outcome") != "success"):
        raise EvidenceError("PIPELINE_SCAN_OUTCOME_MISMATCH")
    background = read_object(files.get("background-task.json"), "background-task.json")
    task = background.get("task", background)
    if not isinstance(task, dict) or task.get("status") != "SUCCESS":
        raise EvidenceError("SONAR_BACKGROUND_TASK_NOT_SUCCESSFUL")
    analysis_id = task.get("analysisId") or task.get("analysis_id")
    if not isinstance(analysis_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{5,200}", analysis_id):
        raise EvidenceError("SONAR_ANALYSIS_ID_MISSING")
    report = parse_report(files.get("report-task.txt"))
    if task.get("id") != report["ceTaskId"]:
        raise EvidenceError("SONAR_TASK_ID_MISMATCH")
    gate = read_object(files.get("quality-gate.json"), "quality-gate.json")
    gate_status = gate.get("gate_status")
    if gate_status not in {"OK", "ERROR"} or (success and gate_status != "OK"):
        raise EvidenceError("QUALITY_GATE_NOT_VALIDATED")
    expected_gate_outcome = "success" if gate_status == "OK" else "failure"
    if outcomes.get("gate", {}).get("outcome") != expected_gate_outcome:
        raise EvidenceError("PIPELINE_GATE_OUTCOME_MISMATCH")
    failed_stage = pipeline.get("failed_stage")
    if (success and failed_stage) or (not success and (not isinstance(failed_stage, str)
            or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{0,79}", failed_stage)
            or outcomes.get(failed_stage, {}).get("outcome") != "failure")):
        raise EvidenceError("PIPELINE_FAILURE_OUTCOME_MISMATCH")
    # The gate collector embeds the queried analysisId; checking this prevents a
    # project's most recent (different commit) result from being used as proof.
    recorded_analysis_id = gate.get("analysis_id") or gate.get("analysisId")
    if recorded_analysis_id != analysis_id:
        raise EvidenceError("QUALITY_GATE_ANALYSIS_ID_MISMATCH")
    if (gate.get("scan_executed") is not True or gate.get("task_status") != "SUCCESS"
            or gate.get("task_id") != report["ceTaskId"] or gate.get("commit") != run["head_sha"]
            or gate.get("project_key") != report.get("projectKey")
            or gate.get("project_key") != task.get("componentKey")
            or gate.get("status") != ("PASSED" if gate_status == "OK" else "FAILED")
            or gate.get("sonar_host") != report.get("serverUrl")):
        raise EvidenceError("QUALITY_GATE_SOURCE_MISMATCH")
    scan = observed_step(state, r"(?:sonar.*(?:scan|escaneo|an[aá]lisis)|(?:scan|escaneo|an[aá]lisis).*sonar)")
    gate_step = observed_step(state, r"quality[ _-]*gate|puerta de calidad", "success" if gate_status == "OK" else "failure")
    if scan["completed_at"] and gate_step["started_at"] and gate_step["started_at"] < scan["completed_at"]:
        raise EvidenceError("SONAR_STAGE_ORDER_MISMATCH")
    result = {"analysis_id": analysis_id, "ce_task_id": task["id"], "gate_status": gate_status,
              "scan_executed": True, "scan_stage_id": scan["id"], "gate_stage_id": gate_step["id"]}
    scan["logs"].append("Análisis real recibido por SonarQube: " + analysis_id + "; tarea: " + task["id"])
    gate_step["logs"].append("Quality Gate del analysisId anterior: " + gate_status + ". Commit: " + run["head_sha"])
    dashboard = safe_dashboard(report.get("dashboardUrl"))
    if dashboard:
        result["dashboard_url"] = dashboard
    return result


def verify_notification(files: dict[str, bytes], run: dict, repository: str, state: dict) -> dict:
    receipt = read_object(files.get("notification-receipt.json"), "notification-receipt.json")
    confirm_source(receipt, run, repository, "NOTIFICATION")
    code = receipt.get("http_code", receipt.get("http_status"))
    provider = receipt.get("provider")
    if receipt.get("status") != "DELIVERED" or receipt.get("pipeline_status") != "failure":
        raise EvidenceError("NOTIFICATION_NOT_DELIVERED")
    if not isinstance(code, int) or isinstance(code, bool) or not 200 <= code < 300:
        raise EvidenceError("NOTIFICATION_NO_HTTP_ACKNOWLEDGEMENT")
    if receipt.get("run_url") != run["html_url"] or receipt.get("delivery_scope") != "server_acknowledgement_only":
        raise EvidenceError("NOTIFICATION_CONTEXT_MISMATCH")
    if not isinstance(receipt.get("controlled_failure"), bool):
        raise EvidenceError("NOTIFICATION_CONTEXT_MISMATCH")
    if provider == "slack":
        if code != 200 or receipt.get("acknowledgement") != "slack_ok":
            raise EvidenceError("NOTIFICATION_INVALID_ACKNOWLEDGEMENT")
    elif provider == "discord":
        if (receipt.get("acknowledgement") != "discord_created_message"
                or not re.fullmatch(r"\d{1,30}", str(receipt.get("message_id", "")))):
            raise EvidenceError("NOTIFICATION_INVALID_ACKNOWLEDGEMENT")
    else:
        raise EvidenceError("NOTIFICATION_PROVIDER_NOT_SUPPORTED")
    step = observed_step(state, r"^(?:notify\b|notificar\b|enviar.*alerta|send.*alert)")
    failures = [item for item in state["stages"] if item["status"] == "failure"]
    if not failures or not step["started_at"] or not step["completed_at"]:
        raise EvidenceError("NOTIFICATION_FAILURE_SOURCE_MISSING")
    if not any(item["completed_at"] and item["completed_at"] <= step["started_at"] for item in failures):
        raise EvidenceError("NOTIFICATION_PRECEDES_FAILURE")
    timestamp = receipt.get("timestamp_utc", receipt.get("timestamp"))
    try:
        recorded = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
        start = datetime.fromisoformat(step["started_at"].replace("Z", "+00:00"))
        end = datetime.fromisoformat(step["completed_at"].replace("Z", "+00:00"))
        if recorded.tzinfo is None or not start - timedelta(seconds=5) <= recorded <= end + timedelta(seconds=5):
            raise ValueError
    except (TypeError, AttributeError, ValueError):
        raise EvidenceError("NOTIFICATION_TIMESTAMP_MISMATCH") from None
    public_keys = {"status", "provider", "message_id", "channel_id", "acknowledgement", "repository", "run_id",
                   "run_attempt", "commit", "run_url", "controlled_failure", "failed_stage", "delivery_scope", "timestamp_utc"}
    result = {key: receipt[key] for key in public_keys if key in receipt}
    if "channel_id" in result and not re.fullmatch(r"\d{1,30}", str(result["channel_id"])):
        raise EvidenceError("NOTIFICATION_CONTEXT_MISMATCH")
    result.update(http_status=code, http_code=code, notification_stage_id=step["id"])
    step["logs"].append(f"Aceptación real del servidor {provider}: HTTP {code}; {receipt['acknowledgement']}.")
    if provider == "discord":
        step["logs"].append("ID de mensaje creado: " + receipt["message_id"])
    step["logs"].append("Comprobante de aceptación del servidor; no demuestra lectura por una persona.")
    return result


def selected_artifact(artifacts: list[dict], name: str, run: dict) -> dict:
    matching = [item for item in artifacts if item.get("name") == name and not item.get("expired")]
    if not matching:
        raise EvidenceError("REQUIRED_ARTIFACT_MISSING_" + name.upper().replace("-", "_"))
    latest = max(matching, key=lambda item: item.get("id", 0))
    artifact_run = latest.get("workflow_run") or {}
    if artifact_run and (artifact_run.get("id") != run["id"] or artifact_run.get("head_sha") != run["head_sha"]):
        raise EvidenceError("ARTIFACT_RUN_MISMATCH")
    if not isinstance(latest.get("id"), int):
        raise EvidenceError("INVALID_ARTIFACT_ID")
    return latest


def collect_run(client: GitHubClient, repository: str, run_id: int, success: bool) -> dict:
    run = client.get_json(f"/repos/{repository}/actions/runs/{run_id}")
    wanted_conclusion = "success" if success else "failure"
    if (run.get("id") != run_id or run.get("status") != "completed"
            or run.get("conclusion") != wanted_conclusion
            or not re.fullmatch(r"[a-f0-9]{40}", str(run.get("head_sha", "")))
            or run.get("html_url") != f"https://github.com/{repository}/actions/runs/{run_id}"):
        raise EvidenceError("RUN_NOT_COMPLETED_AS_EXPECTED")
    attempt = run.get("run_attempt", 1)
    if not isinstance(attempt, int) or attempt < 1:
        raise EvidenceError("INVALID_RUN_ATTEMPT")
    jobs = client.pages(f"/repos/{repository}/actions/runs/{run_id}/attempts/{attempt}/jobs", "jobs")
    if not jobs or any(job.get("status") != "completed" for job in jobs):
        raise EvidenceError("RUN_JOBS_NOT_COMPLETE")
    state = normalize(run, jobs, repository)
    artifacts = client.pages(f"/repos/{repository}/actions/runs/{run_id}/artifacts", "artifacts")
    audit = selected_artifact(artifacts, "snackup-ci-audit", run)
    files = zip_members(client.artifact(repository, audit["id"]), AUDIT_FILES)
    sonar = verify_sonar(files, run, repository, state, success)
    selected = [audit]
    if success:
        # No failure alert is expected in a successful run; do not invent an ACK.
        notification = {"status": "SKIPPED", "reason": "PIPELINE_NOT_FAILED"}
        if any(item.get("name") == "snackup-ci-notification" for item in artifacts):
            raise EvidenceError("UNEXPECTED_SUCCESS_NOTIFICATION_ARTIFACT")
        build = selected_artifact(artifacts, "snackup-integrated-web", run)
        selected.append(build)
    else:
        alert = selected_artifact(artifacts, "snackup-ci-notification", run)
        notification = verify_notification(zip_members(client.artifact(repository, alert["id"]), {"notification-receipt.json"}), run, repository, state)
        pipeline = read_object(files.get("pipeline-result.json"), "pipeline-result.json")
        if (notification.get("failed_stage") != pipeline.get("failed_stage")
                or notification.get("controlled_failure") != pipeline.get("controlled_failure")):
            raise EvidenceError("NOTIFICATION_FAILED_STAGE_MISMATCH")
        selected.append(alert)
    public_artifacts = [{key: item.get(key) for key in ("id", "name", "size_in_bytes", "created_at", "expires_at", "digest")} for item in selected]
    for item in public_artifacts:
        item["html_url"] = f"https://github.com/{repository}/actions/runs/{run_id}/artifacts/{item['id']}"
    # The agent's CI output card represents the validated application package.
    # Audit/notification ZIPs remain source records, not a successful web build.
    state["artifacts"] = [dict(item, url=item["html_url"]) for item in public_artifacts
                          if item["name"] == "snackup-integrated-web"]
    return {"schema_version": 1, "state": state, "sonar": sonar, "notification": notification,
            "source": {"repository": repository, "run_id": run_id, "sha": run["head_sha"],
                       "url": run["html_url"], "run_attempt": attempt, "created_at": run.get("created_at"),
                       "updated_at": run.get("updated_at"), "artifacts": public_artifacts}}


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Recupera dos ejecuciones reales de CI con SonarQube y aviso de fallo.")
    parser.add_argument("--repo", required=True)
    parser.add_argument("--success-run", required=True, type=int)
    parser.add_argument("--failure-run", required=True, type=int)
    parser.add_argument("--outdir", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        repository = repository_name(args.repo)
        if args.success_run <= 0 or args.failure_run <= 0 or args.success_run == args.failure_run:
            raise EvidenceError("INVALID_RUN_IDS")
        client = GitHubClient(os.environ.get("GITHUB_TOKEN", ""))
        # Validate both completely before publishing either as usable evidence.
        success = collect_run(client, repository, args.success_run, True)
        failure = collect_run(client, repository, args.failure_run, False)
        args.outdir.mkdir(parents=True, exist_ok=True)
        write_json(args.outdir / "success.json", success)
        write_json(args.outdir / "failure.json", failure)
        print(json.dumps({"status": "VERIFIED", "success_run": args.success_run, "failure_run": args.failure_run,
                          "sonar_analysis_ids": [success["sonar"]["analysis_id"], failure["sonar"]["analysis_id"]],
                          "notification_provider": failure["notification"]["provider"]}, ensure_ascii=False))
        return 0
    except (EvidenceError, OSError) as error:
        reason = str(error) if isinstance(error, EvidenceError) else "OUTPUT_WRITE_FAILED"
        print("Evidencia no validada: " + reason, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
