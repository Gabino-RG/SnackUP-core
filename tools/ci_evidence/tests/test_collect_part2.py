"""Security and provenance checks; HTTP is mocked and no messages are sent."""
import importlib.util
import io
import json
from pathlib import Path
import unittest
from urllib.error import HTTPError
from email.message import Message
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / "collect_part2.py"
SPEC = importlib.util.spec_from_file_location("collect_part2", SCRIPT)
ci = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ci)

REPO = "Gabino-RG/SnackUP-core"
SHA = "a" * 40


def zip_data(files):
    result = io.BytesIO()
    with zipfile.ZipFile(result, "w") as archive:
        for name, value in files.items():
            archive.writestr(name, json.dumps(value) if isinstance(value, dict) else value)
    return result.getvalue()


def step(number, name, conclusion, start, end):
    return {"number": number, "name": name, "status": "completed", "conclusion": conclusion,
            "started_at": f"2026-10-08T00:00:{start:02d}Z", "completed_at": f"2026-10-08T00:00:{end:02d}Z"}


def fixture(success=True):
    run_id = 100 if success else 200
    run = {"id": run_id, "status": "completed", "conclusion": "success" if success else "failure",
           "head_sha": SHA, "head_branch": "feature/ci-sonar-notifications", "run_attempt": 1,
           "name": "Flutter CI", "html_url": f"https://github.com/{REPO}/actions/runs/{run_id}"}
    steps = [step(1, "Análisis SonarQube", "success", 1, 2), step(2, "Quality Gate SonarQube bloqueante", "success", 3, 4)]
    outcomes = {"sonar": {"outcome": "success"}, "gate": {"outcome": "success"}}
    if not success:
        steps += [step(3, "Prueba controlada de fallo para evidencia", "failure", 5, 6)]
        outcomes["controlled_failure"] = {"outcome": "failure"}
    jobs = [{"id": 11, "name": "Validate", "status": "completed", "steps": steps}]
    if not success:
        jobs += [{"id": 12, "name": "Notificación de fallo", "status": "completed", "steps": [
            step(1, "Descargar código del notificador", "success", 7, 7),
            step(2, "Notificar fallo en Slack o Discord", "success", 8, 9),
            step(3, "Conservar comprobante de notificación", "success", 10, 11)]}]
    audit = {
        "sonar-evidence/pipeline-result.json": {"repository": REPO, "run_id": str(run_id), "run_attempt": "1", "commit": SHA,
            "failed_stage": "" if success else "controlled_failure", "controlled_failure": not success, "steps": outcomes},
        "sonar-evidence/background-task.json": {"task": {"id": "task_123", "status": "SUCCESS", "analysisId": "analysis_123", "componentKey": "snackup"}},
        "sonar-evidence/report-task.txt": "ceTaskId=task_123\nprojectKey=snackup\nserverUrl=https://sonarcloud.io\n",
        "sonar-evidence/quality-gate.json": {"analysis_id": "analysis_123", "scan_executed": True,
            "gate_status": "OK", "task_status": "SUCCESS", "task_id": "task_123", "project_key": "snackup",
            "commit": SHA, "status": "PASSED", "sonar_host": "https://sonarcloud.io"},
    }
    receipt = {"repository": REPO, "run_id": str(run_id), "run_attempt": "1", "commit": SHA,
        "run_url": run["html_url"], "status": "DELIVERED", "pipeline_status": "failure", "provider": "discord",
        "http_code": 200, "acknowledgement": "discord_created_message", "message_id": "123456789",
        "timestamp_utc": "2026-10-08T00:00:08+00:00", "failed_stage": "controlled_failure",
        "controlled_failure": True, "delivery_scope": "server_acknowledgement_only"}
    artifacts = [{"id": 900, "name": "snackup-ci-audit", "expired": False,
                  "workflow_run": {"id": run_id, "head_sha": SHA}}]
    if success:
        artifacts += [{"id": 899, "name": "snackup-integrated-web", "expired": False,
                       "workflow_run": {"id": run_id, "head_sha": SHA}}]
    if not success:
        artifacts += [{"id": 901, "name": "snackup-ci-notification", "expired": False,
                       "workflow_run": {"id": run_id, "head_sha": SHA}}]
    return run, jobs, audit, receipt, artifacts


class FakeClient:
    def __init__(self, values):
        self.run, self.jobs, self.audit, self.receipt, self.artifacts = values

    def get_json(self, path):
        return self.run

    def pages(self, path, key):
        return self.jobs if key == "jobs" else self.artifacts

    def artifact(self, repository, artifact_id):
        return zip_data(self.audit if artifact_id == 900 else {"notification-receipt.json": self.receipt})


class CollectorTests(unittest.TestCase):
    def test_completed_success_and_real_failure_receipt_keep_exact_timestamps(self):
        success = ci.collect_run(FakeClient(fixture()), REPO, 100, True)
        failure = ci.collect_run(FakeClient(fixture(False)), REPO, 200, False)
        self.assertTrue(success["sonar"]["scan_executed"])
        self.assertEqual(success["notification"]["status"], "SKIPPED")
        self.assertEqual(failure["notification"]["http_status"], 200)
        self.assertEqual(failure["notification"]["message_id"], "123456789")
        self.assertEqual(failure["state"]["stages"][0]["started_at"], "2026-10-08T00:00:01Z")
        self.assertEqual(len(failure["state"]["stages"]), 6)
        self.assertEqual(success["state"]["artifacts"][0]["name"], "snackup-integrated-web")
        self.assertEqual(failure["state"]["artifacts"], [])

    def test_quality_gate_from_another_analysis_is_rejected(self):
        values = fixture()
        values[2]["sonar-evidence/quality-gate.json"]["analysis_id"] = "another_analysis"
        with self.assertRaisesRegex(ci.EvidenceError, "ANALYSIS_ID_MISMATCH"):
            ci.collect_run(FakeClient(values), REPO, 100, True)

    def test_success_without_build_artifact_cannot_be_presented_as_ready(self):
        values = fixture()
        values[4].pop()
        with self.assertRaisesRegex(ci.EvidenceError, "REQUIRED_ARTIFACT_MISSING"):
            ci.collect_run(FakeClient(values), REPO, 100, True)

    def test_real_failed_quality_gate_is_retained_as_error(self):
        values = fixture(False)
        values[2]["sonar-evidence/quality-gate.json"].update(gate_status="ERROR", status="FAILED")
        pipeline = values[2]["sonar-evidence/pipeline-result.json"]
        pipeline.update(failed_stage="gate", controlled_failure=False)
        pipeline["steps"]["gate"]["outcome"] = "failure"
        del pipeline["steps"]["controlled_failure"]
        values[1][0]["steps"][1]["conclusion"] = "failure"
        values[1][0]["steps"].pop()
        values[3].update(failed_stage="gate", controlled_failure=False)
        collected = ci.collect_run(FakeClient(values), REPO, 200, False)
        self.assertEqual(collected["sonar"]["gate_status"], "ERROR")
        self.assertEqual(collected["notification"]["status"], "DELIVERED")

    def test_preflight_failure_cannot_be_reported_as_executed_sonar(self):
        values = fixture(False)
        values[2]["sonar-evidence/quality-gate.json"]["scan_executed"] = False
        with self.assertRaises(ci.EvidenceError):
            ci.collect_run(FakeClient(values), REPO, 200, False)

    def test_receipt_from_another_attempt_is_rejected(self):
        values = fixture(False)
        values[3]["run_attempt"] = "2"
        with self.assertRaisesRegex(ci.EvidenceError, "NOTIFICATION_SOURCE_MISMATCH"):
            ci.collect_run(FakeClient(values), REPO, 200, False)

    def test_slack_requires_body_ack_and_discord_requires_message_id(self):
        for changed in ({"message_id": ""}, {"provider": "slack", "acknowledgement": None}, {"http_code": 204}):
            with self.subTest(changed=changed):
                values = fixture(False)
                values[3].update(changed)
                if changed == {"http_code": 204}:
                    values[3]["provider"] = "slack"
                    values[3]["acknowledgement"] = "slack_ok"
                with self.assertRaises(ci.EvidenceError):
                    ci.collect_run(FakeClient(values), REPO, 200, False)

    def test_notification_must_follow_observed_failure(self):
        values = fixture(False)
        values[1][1]["steps"][1]["started_at"] = "2026-10-08T00:00:04Z"
        with self.assertRaisesRegex(ci.EvidenceError, "PRECEDES_FAILURE"):
            ci.collect_run(FakeClient(values), REPO, 200, False)

    def test_zip_traversal_duplicates_and_symlink_are_rejected(self):
        for files in ({"../quality-gate.json": "{}"}, {"/quality-gate.json": "{}"},
                      {"a/quality-gate.json": "{}", "b/quality-gate.json": "{}"}):
            with self.subTest(files=list(files)):
                with self.assertRaises(ci.EvidenceError):
                    ci.zip_members(zip_data(files), {"quality-gate.json"})
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            entry = zipfile.ZipInfo("quality-gate.json")
            entry.create_system = 3
            entry.external_attr = 0o120777 << 16
            archive.writestr(entry, "elsewhere")
        with self.assertRaises(ci.EvidenceError):
            ci.zip_members(buffer.getvalue(), {"quality-gate.json"})

    def test_artifact_redirect_drops_authorization_and_errors_hide_url(self):
        class Response:
            def __enter__(self):
                return self
            def __exit__(self, *args):
                pass
            def read(self, size):
                return b"zip"

        class Opener:
            def __init__(self):
                self.requests = []
            def open(self, request, timeout):
                self.requests.append(request)
                if len(self.requests) == 1:
                    headers = Message()
                    headers["Location"] = "https://artifacts.blob.core.windows.net/file?signature=PRIVATE"
                    raise HTTPError(request.full_url, 302, "redirect", headers, None)
                return Response()

        opener = Opener()
        client = ci.GitHubClient("SUPER_PRIVATE_TOKEN", opener=opener)
        self.assertEqual(client.artifact(REPO, 123), b"zip")
        self.assertIn("Authorization", opener.requests[0].headers)
        self.assertNotIn("Authorization", opener.requests[1].headers)
        self.assertFalse(ci.download_host("https://evil.example/file"))

    def test_all_pages_are_read_without_using_incomplete_first_page(self):
        class Pages(ci.GitHubClient):
            def __init__(self):
                self.paths = []
            def get_json(self, path):
                self.paths.append(path)
                return {"jobs": [{"id": i} for i in range(100)] if path.endswith("&page=1") else [{"id": 101}]}
        client = Pages()
        self.assertEqual(len(client.pages("/repos/o/r/actions/runs/1/jobs", "jobs")), 101)
        self.assertEqual(len(client.paths), 2)


if __name__ == "__main__":
    unittest.main()
