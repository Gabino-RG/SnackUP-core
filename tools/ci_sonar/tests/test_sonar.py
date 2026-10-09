import json
from pathlib import Path
import sys
import tempfile
import unittest
from urllib.error import HTTPError, URLError

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from tools.ci_sonar.preflight import check
from tools.ci_sonar.quality_gate import evaluate
from tools.ci_sonar.evidence_mode import requested


class Response:
    def __init__(self, data):
        self.data = data
    def __enter__(self):
        return self
    def __exit__(self, *args):
        return False
    def getcode(self):
        return 200
    def read(self, *args):
        return json.dumps(self.data).encode()


class Api:
    def __init__(self, *answers):
        self.answers = list(answers)
        self.requests = []
    def open(self, request, timeout):
        self.requests.append(request)
        value = self.answers.pop(0)
        if isinstance(value, Exception):
            raise value
        return Response(value)


def task(status="SUCCESS", analysis="analysis123", component="snackup"):
    return {"task": {"id": "task123", "status": status, "analysisId": analysis, "componentKey": component}}


class SonarTests(unittest.TestCase):
    def test_push_marker_only_applies_to_evidence_branch(self):
        env = {"GITHUB_EVENT_NAME": "push", "GITHUB_REF_NAME": "feature/ci-sonar-notifications"}
        self.assertTrue(requested(env, {"enabled": True}))
        self.assertFalse(requested({**env, "GITHUB_REF_NAME": "main"}, {"enabled": True}))
        self.assertFalse(requested(env, {"enabled": False}))

    def test_manual_failure_requires_explicit_true_input(self):
        self.assertFalse(requested({"GITHUB_EVENT_NAME": "workflow_dispatch"}, {"enabled": True}))
        self.assertTrue(requested({"GITHUB_EVENT_NAME": "workflow_dispatch", "EVIDENCE_FAILURE_INPUT": "true"}, {}))
    def evaluate(self, api, **kwargs):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        report = root / "report-task.txt"
        report.write_text("serverUrl=https://sonarcloud.io\nprojectKey=snackup\nceTaskId=task123\nceTaskUrl=https://wrong.invalid/steal\n")
        result = evaluate(report, "https://sonarcloud.io", "snackup", "mock-token-not-real", root / "out", opener=api, **kwargs)
        self.assertEqual(result, json.loads((root / "out/quality-gate.json").read_text()))
        return result

    def test_missing_configuration_is_blocked_and_secret_free(self):
        result = check({})
        self.assertEqual(result["status"], "BLOCKED")
        self.assertIn("SONAR_TOKEN", result["missing"])
        self.assertFalse(result["sonar_analysis_executed"])

    def test_ready_is_not_a_claim_of_analysis(self):
        result = check({"SONAR_TOKEN": "mock-secret", "SONAR_ORGANIZATION": "classroom", "SONAR_PROJECT_KEY": "snackup",
                        "CI_FAILURE_WEBHOOK_URL": "https://hooks.slack.com/services/MOCK/TEST/NOT_A_REAL_WEBHOOK"})
        self.assertEqual(result["status"], "READY")
        self.assertFalse(result["sonar_analysis_executed"])
        self.assertNotIn("mock-secret", json.dumps(result))

    def test_unsafe_cloud_host_and_webhook_block_configuration(self):
        result = check({"SONAR_HOST_URL": "https://evil.invalid", "CI_FAILURE_WEBHOOK_URL": "http://discord.com/api/webhooks/1/secret"})
        self.assertIn("SONAR_HOST_URL", result["invalid"])
        self.assertIn("CI_FAILURE_WEBHOOK_URL", result["invalid"])

    def test_gate_is_pinned_to_this_analysis_and_ignores_untrusted_task_url(self):
        api = Api(task(), {"projectStatus": {"status": "OK", "conditions": []}})
        result = self.evaluate(api)
        self.assertEqual(result["status"], "PASSED")
        self.assertEqual(result["analysis_id"], "analysis123")
        self.assertTrue(result["scan_executed"])
        self.assertEqual(api.requests[1].full_url, "https://sonarcloud.io/api/qualitygates/project_status?analysisId=analysis123")
        self.assertTrue(all(r.full_url.startswith("https://sonarcloud.io/api/") for r in api.requests))

    def test_red_quality_gate_blocks_the_pipeline(self):
        result = self.evaluate(Api(task(), {"projectStatus": {"status": "ERROR", "conditions": [{"metricKey": "new_coverage", "status": "ERROR"}]}}))
        self.assertEqual(result["status"], "FAILED")
        self.assertEqual(result["gate_status"], "ERROR")
        self.assertTrue(result["scan_executed"])

    def test_other_project_background_task_cannot_pass(self):
        result = self.evaluate(Api(task(component="another-project")))
        self.assertFalse(result["scan_executed"])
        self.assertEqual(result["reason"], "SONAR_TASK_MISMATCH")

    def test_missing_analysis_id_fails_with_a_receipt(self):
        result = self.evaluate(Api(task(analysis=None)))
        self.assertEqual(result["status"], "FAILED")
        self.assertFalse(result["scan_executed"])

    def test_malformed_conditions_fail_closed(self):
        result = self.evaluate(Api(task(), {"projectStatus": {"status": "OK", "conditions": None}}))
        self.assertEqual(result["status"], "FAILED")

    def test_pending_task_timeout_is_not_scan_success(self):
        result = self.evaluate(Api(task("PENDING")), timeout=1, clock=iter([0, 2]).__next__, pause=lambda _: None)
        self.assertEqual(result["reason"], "SONAR_BACKGROUND_TASK_TIMEOUT")
        self.assertFalse(result["scan_executed"])

    def test_network_error_never_leaks_token(self):
        result = self.evaluate(Api(URLError("mock-token-not-real")))
        self.assertEqual(result["status"], "FAILED")
        self.assertNotIn("mock-token-not-real", json.dumps(result))

    def test_forbidden_gate_reports_status_without_leaking_error_details(self):
        api = Api(task(), HTTPError("https://sonarcloud.io/mock-token-not-real", 403,
                                   "mock-token-not-real", {}, None))
        result = self.evaluate(api)
        self.assertEqual(result["reason"], "SONAR_API_HTTP_403")
        self.assertEqual(result["status"], "FAILED")
        self.assertEqual(result["analysis_id"], "analysis123")
        self.assertNotIn("mock-token-not-real", json.dumps(result))

    def test_unauthorized_task_cannot_be_reported_as_an_executed_scan(self):
        result = self.evaluate(Api(HTTPError("https://sonarcloud.io/private", 401,
                                             "sensitive-response", {}, None)))
        self.assertEqual(result["reason"], "SONAR_API_HTTP_401")
        self.assertFalse(result["scan_executed"])
        self.assertNotIn("sensitive-response", json.dumps(result))


if __name__ == "__main__":
    unittest.main()
