"""Contract checks use mocked HTTP only; these tests never contact chat providers."""

from contextlib import redirect_stdout, redirect_stderr
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError


SCRIPT = Path(__file__).resolve().parents[1] / "notify_failure.py"
SPEC = importlib.util.spec_from_file_location("notify_failure", SCRIPT)
notifier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(notifier)

DISCORD_URL = "https://discord.com/api/webhooks/123456789/TEST_SECRET_NOT_REAL"
SLACK_URL = "https://hooks.slack.com/services/TTEST/BTEST/TEST_SECRET_NOT_REAL"
BASE_ENV = {
    "GITHUB_REPOSITORY": "Gabino-RG/SnackUP-core",
    "GITHUB_REF_NAME": "feature/ci-part2",
    "GITHUB_SHA": "a" * 40,
    "GITHUB_RUN_ID": "1234",
    "GITHUB_RUN_ATTEMPT": "2",
}


class Response:
    def __init__(self, code=200, body=b"ok"):
        self.code = code
        self.body = body

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def getcode(self):
        return self.code

    def read(self, limit):
        return self.body[:limit]


class FakeOpener:
    def __init__(self, response=None, error=None):
        self.response = response or Response()
        self.error = error
        self.requests = []

    def open(self, request, timeout):
        self.requests.append((request, timeout))
        if self.error:
            raise self.error
        return self.response


class NotificationTests(unittest.TestCase):
    def env(self, url):
        return {**BASE_ENV, "CI_FAILURE_WEBHOOK_URL": url}

    def test_discord_requires_confirmation_and_persists_only_public_ids(self):
        response = Response(body=json.dumps({"id": "987654321", "channel_id": "123456789", "token": "DO_NOT_STORE"}).encode())
        opener = FakeOpener(response)
        env = {**self.env(DISCORD_URL + "?wait=false&thread_id=345"), "CI_EVIDENCE_CONTROLLED_FAILURE": "true"}
        receipt, code = notifier.notify("failure", "SonarQube Quality Gate", env, opener)
        self.assertEqual((code, receipt["status"]), (0, "DELIVERED"))
        self.assertEqual(receipt["acknowledgement"], "discord_created_message")
        self.assertEqual(receipt["message_id"], "987654321")
        self.assertEqual(receipt["channel_id"], "123456789")
        request, timeout = opener.requests[0]
        self.assertEqual(request.method, "POST")
        self.assertTrue(request.full_url.endswith("?wait=true&thread_id=345"))
        self.assertEqual(request.get_header("Content-type"), "application/json; charset=utf-8")
        self.assertEqual(request.get_header("User-agent"), "SnackUP-CI-Notifier/1.0")
        payload = json.loads(request.data)
        self.assertEqual(payload["allowed_mentions"], {"parse": []})
        for expected in ("SnackUP", "FALLO CONTROLADO PARA EVIDENCIA", "feature/ci-part2", "aaaaaaaaaaaa", "SonarQube Quality Gate", "https://github.com/Gabino-RG/SnackUP-core/actions/runs/1234"):
            self.assertIn(expected, payload["content"])
        self.assertLessEqual(len(payload["content"]), 2000)
        self.assertNotIn("DO_NOT_STORE", json.dumps(receipt))
        self.assertNotIn("TEST_SECRET_NOT_REAL", json.dumps(receipt))

    def test_slack_requires_literal_http_200_ok(self):
        opener = FakeOpener(Response(body=b"ok"))
        receipt, code = notifier.notify("failure", "Build", self.env(SLACK_URL), opener)
        self.assertEqual((code, receipt["status"], receipt["provider"]), (0, "DELIVERED", "slack"))
        self.assertEqual(receipt["acknowledgement"], "slack_ok")
        self.assertNotIn("message_id", receipt)
        payload = json.loads(opener.requests[0][0].data)
        self.assertIn("SnackUP CI", payload["text"])
        self.assertFalse(payload["mrkdwn"])
        self.assertFalse(payload["unfurl_links"])
        for response in (Response(200, b"invalid_token"), Response(204, b"ok"), Response(200, b'{"ok":true}')):
            receipt, code = notifier.notify("failure", "Build", self.env(SLACK_URL), FakeOpener(response))
            self.assertEqual((code, receipt["status"]), (1, "FAILED"))

    def test_discord_http_success_alone_does_not_claim_message_delivery(self):
        for body in (b"", b"{}", b"[]", b'{"id": "secret token"}', b'{"id": 123}', b"invalid JSON"):
            receipt, code = notifier.notify("failure", "Build", self.env(DISCORD_URL), FakeOpener(Response(200, body)))
            self.assertEqual((code, receipt["status"]), (1, "FAILED"))
            self.assertEqual(receipt["reason"], "INVALID_SERVER_ACKNOWLEDGEMENT")

    def test_http_and_network_errors_never_write_url_token_or_server_body(self):
        errors = [
            HTTPError(DISCORD_URL, 429, DISCORD_URL, {}, io.BytesIO(DISCORD_URL.encode())),
            URLError("failed contacting " + DISCORD_URL),
            TimeoutError(DISCORD_URL),
        ]
        for error in errors:
            receipt, code = notifier.notify("failure", "Build", self.env(DISCORD_URL), FakeOpener(error=error))
            self.assertEqual((code, receipt["status"]), (1, "FAILED"))
            self.assertNotIn(DISCORD_URL, json.dumps(receipt))
            self.assertNotIn("TEST_SECRET_NOT_REAL", json.dumps(receipt))

    def test_missing_or_unsafe_configuration_stops_before_http(self):
        urls = ["", "http://discord.com/api/webhooks/123/token", "https://evil.example/api/webhooks/123/token", "https://discord.com.evil.example/api/webhooks/123/token", "https://user:secret@discord.com/api/webhooks/123/token", "https://discord.com:8443/api/webhooks/123/token", "https://discord.com/api/webhooks/123/token#secret", "https://discord.com/api/webhooks/123/token?destination=secret", "https://hooks.slack.com/services/token", "https://hooks.slack.com/services/T/B/token?query=secret"]
        for url in urls:
            opener = FakeOpener()
            receipt, code = notifier.notify("failure", "Build", self.env(url), opener)
            self.assertEqual(code, 2)
            self.assertEqual(receipt["status"], "MISSING_CONFIGURATION" if not url else "FAILED")
            self.assertEqual(opener.requests, [])
            self.assertNotIn("secret@", json.dumps(receipt))

    def test_public_preflight_validation_returns_provider_without_network(self):
        self.assertEqual(notifier.validate_webhook_url(SLACK_URL), "slack")
        self.assertEqual(notifier.validate_webhook_url(DISCORD_URL), "discord")
        with self.assertRaises(notifier.UnsafeWebhook) as caught:
            notifier.validate_webhook_url("https://evil.example/SECRET")
        self.assertEqual(str(caught.exception), "INVALID_WEBHOOK_CONFIGURATION")

    def test_redirect_handler_never_follows_and_receipt_redacts_location(self):
        handler = notifier.RejectRedirects()
        request = notifier.Request(DISCORD_URL, data=b"{}", method="POST")
        with self.assertRaises(HTTPError) as caught:
            handler.redirect_request(request, None, 307, "redirect", {"Location": "https://evil.example/SECRET"}, "https://evil.example/SECRET")
        receipt, code = notifier.notify("failure", "Build", self.env(DISCORD_URL), FakeOpener(error=caught.exception))
        self.assertEqual((code, receipt["status"], receipt["reason"], receipt["http_code"]), (1, "FAILED", "REDIRECT_REJECTED", 307))
        self.assertNotIn("SECRET", json.dumps(receipt))

    def test_success_cancelled_skipped_unknown_never_send_even_with_secret(self):
        for status in ("success", "cancelled", "skipped", "unknown", "FAILURE"):
            opener = FakeOpener()
            receipt, code = notifier.notify(status, "Build", self.env(DISCORD_URL), opener)
            self.assertEqual((code, receipt["status"]), (0, "SKIPPED"))
            self.assertEqual(opener.requests, [])

    def test_cli_receipt_and_output_never_include_webhook(self):
        opener = FakeOpener(Response(body=b"ok"))
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "evidence" / "notification-receipt.json"
            stdout, stderr = io.StringIO(), io.StringIO()
            with patch.dict(notifier.os.environ, self.env(SLACK_URL), clear=True), patch.object(notifier, "build_opener", return_value=opener), redirect_stdout(stdout), redirect_stderr(stderr):
                code = notifier.main(["--status", "failure", "--stage", "Tests", "--receipt", str(target)])
            self.assertEqual(code, 0)
            saved = json.loads(target.read_text())
            self.assertEqual(saved["status"], "DELIVERED")
            self.assertEqual(saved, json.loads(stdout.getvalue()))
            self.assertNotIn("TEST_SECRET_NOT_REAL", stdout.getvalue() + stderr.getvalue() + target.read_text())

    def test_metadata_cannot_emit_chat_mentions_or_webhook_url(self):
        env = {**self.env(SLACK_URL), "GITHUB_REF_NAME": "feature/@everyone <@U123> " + SLACK_URL}
        opener = FakeOpener()
        receipt, code = notifier.notify("failure", "Build " + SLACK_URL, env, opener)
        self.assertEqual(code, 0)
        payload = json.loads(opener.requests[0][0].data)
        self.assertNotIn("@", payload["text"])
        self.assertNotIn(SLACK_URL, json.dumps(receipt) + payload["text"])


if __name__ == "__main__":
    unittest.main()
