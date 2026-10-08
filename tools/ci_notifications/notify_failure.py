#!/usr/bin/env python3
"""Notify a failed SnackUP CI run through Slack or Discord, without exposing secrets.

The acknowledgement receipt proves server acceptance, not that a person read it.
Only the literal pipeline status ``failure`` sends a message. The webhook stays in
CI_FAILURE_WEBHOOK_URL and is never written to stdout, receipts or error messages.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
from http.client import HTTPException
import json
import os
from pathlib import Path
import re
import sys
from typing import Mapping
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


class UnsafeWebhook(ValueError):
    """The configured secret is not a supported HTTPS webhook."""


class RejectRedirects(HTTPRedirectHandler):
    """Never forward a webhook request, its body, or its secret to another URL."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise HTTPError(req.full_url, code, "Webhook redirect rejected", headers, None)


def webhook_target(secret: str) -> tuple[str, str]:
    """Return provider and request URL. Every validation error is secret-free."""
    try:
        parsed = urlsplit(secret)
        if (parsed.scheme != "https" or parsed.username or parsed.password
                or parsed.port not in (None, 443) or parsed.fragment
                or any(character.isspace() for character in secret)):
            raise UnsafeWebhook("INVALID_WEBHOOK_CONFIGURATION")
        host = (parsed.hostname or "").lower()
        if host == "hooks.slack.com":
            if (not re.fullmatch(r"/services/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+", parsed.path)
                    or parsed.query):
                raise UnsafeWebhook("INVALID_WEBHOOK_CONFIGURATION")
            return "slack", secret
        if host == "discord.com":
            if not re.fullmatch(r"/api/(?:v\d+/)?webhooks/\d+/[A-Za-z0-9._-]+", parsed.path):
                raise UnsafeWebhook("INVALID_WEBHOOK_CONFIGURATION")
            query = parse_qsl(parsed.query, keep_blank_values=True)
            if any(key not in {"wait", "thread_id"} for key, _ in query):
                raise UnsafeWebhook("INVALID_WEBHOOK_CONFIGURATION")
            threads = [value for key, value in query if key == "thread_id"]
            if len(threads) > 1 or any(not re.fullmatch(r"\d+", value) for value in threads):
                raise UnsafeWebhook("INVALID_WEBHOOK_CONFIGURATION")
            confirmed_query = [("wait", "true")]
            if threads:
                confirmed_query.append(("thread_id", threads[0]))
            return "discord", urlunsplit(("https", parsed.netloc, parsed.path, urlencode(confirmed_query), ""))
    except (ValueError, UnicodeError):
        pass
    raise UnsafeWebhook("INVALID_WEBHOOK_CONFIGURATION")


def validate_webhook_url(secret: str) -> str:
    """Validate without network access; return ``slack`` or ``discord``, never the URL."""
    return webhook_target(secret)[0]


def public_text(value: str, maximum: int = 150) -> str:
    """Keep CI metadata readable and prevent URLs, mentions or markup injection."""
    text = re.sub(r"https?://\S+", "[URL omitida]", str(value), flags=re.IGNORECASE)
    text = re.sub(r"[\x00-\x1f\x7f<>@`]", " ", text)
    return " ".join(text.split())[:maximum]


def run_context(env: Mapping[str, str], stage: str) -> dict:
    repository = env.get("GITHUB_REPOSITORY", "")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        repository = "no-disponible/no-disponible"
    run_id = env.get("GITHUB_RUN_ID", "")
    run_id = run_id if re.fullmatch(r"\d+", run_id) else ""
    attempt = env.get("GITHUB_RUN_ATTEMPT", "1")
    attempt = attempt if re.fullmatch(r"\d+", attempt) else "1"
    sha = env.get("GITHUB_SHA", "")
    sha = sha.lower() if re.fullmatch(r"[a-fA-F0-9]{7,40}", sha) else "no-disponible"
    controlled = env.get("CI_EVIDENCE_CONTROLLED_FAILURE", "").lower() in {"true", "1", "yes"}
    return {
        "project": "SnackUP",
        "repository": repository,
        "branch": public_text(env.get("GITHUB_REF_NAME", "no-disponible")),
        "commit": sha,
        "run_id": run_id,
        "run_attempt": attempt,
        "run_url": f"https://github.com/{repository}/actions/runs/{run_id}" if run_id else None,
        "failed_stage": public_text(stage) or "Consultar el registro del pipeline",
        "controlled_failure": controlled,
    }


def payload_for(provider: str, context: dict) -> dict:
    label = "FALLO CONTROLADO PARA EVIDENCIA" if context["controlled_failure"] else "PIPELINE FALLIDO"
    lines = [
        f"SnackUP CI — {label}",
        f"Repositorio: {context['repository']}",
        f"Rama: {context['branch']}",
        f"Commit: {context['commit'][:12]}",
        f"Etapa fallida: {context['failed_stage']}",
        f"Ejecución: #{context['run_id'] or 'no disponible'} · intento {context['run_attempt']}",
        "El flujo se detuvo. Revisar el registro y corregir antes de integrar.",
    ]
    if context["run_url"]:
        lines.append(f"Ver pipeline: {context['run_url']}")
    message = "\n".join(lines)
    if provider == "discord":
        return {"content": message, "username": "SnackUP CI", "allowed_mentions": {"parse": []}}
    # Disable mrkdwn and unfurls so branch metadata cannot trigger Slack mentions.
    return {"text": message, "mrkdwn": False, "unfurl_links": False, "unfurl_media": False}


def notify(status: str, stage: str, env: Mapping[str, str] | None = None,
           opener=None, timeout: float = 20) -> tuple[dict, int]:
    """Return a public receipt and exit code. No real sending is done by tests."""
    env = os.environ if env is None else env
    receipt = {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "pipeline_status": public_text(status, 30),
        "status": "SKIPPED",
        "provider": None,
        "http_code": None,
        "acknowledgement": None,
        "delivery_scope": "server_acknowledgement_only",
        **run_context(env, stage),
    }
    if status != "failure":
        receipt["reason"] = "PIPELINE_NOT_FAILED"
        return receipt, 0

    secret = env.get("CI_FAILURE_WEBHOOK_URL", "").strip()
    if not secret:
        receipt.update(status="MISSING_CONFIGURATION", reason="CI_FAILURE_WEBHOOK_URL_NOT_SET")
        return receipt, 2
    try:
        provider, target = webhook_target(secret)
    except UnsafeWebhook:
        receipt.update(status="FAILED", reason="INVALID_WEBHOOK_CONFIGURATION")
        return receipt, 2
    receipt["provider"] = provider
    body = json.dumps(payload_for(provider, receipt), ensure_ascii=False).encode("utf-8")
    request = Request(target, data=body, method="POST", headers={
        "Content-Type": "application/json; charset=utf-8",
        "Accept": "application/json" if provider == "discord" else "text/plain",
        "User-Agent": "SnackUP-CI-Notifier/1.0",
    })
    opener = build_opener(RejectRedirects()) if opener is None else opener
    try:
        with opener.open(request, timeout=timeout) as response:
            http_code = response.getcode()
            # The response may include secrets or message content: never preserve it.
            response_body = response.read(65537)
        receipt["http_code"] = http_code
        if not 200 <= http_code < 300:
            receipt.update(status="FAILED", reason="HTTP_ERROR")
            return receipt, 1
        if len(response_body) > 65536:
            receipt.update(status="FAILED", reason="INVALID_SERVER_ACKNOWLEDGEMENT")
            return receipt, 1
        if provider == "slack":
            if http_code != 200 or response_body.strip() != b"ok":
                receipt.update(status="FAILED", reason="INVALID_SERVER_ACKNOWLEDGEMENT")
                return receipt, 1
            receipt["acknowledgement"] = "slack_ok"
        else:
            try:
                confirmation = json.loads(response_body)
                message_id = confirmation.get("id") if isinstance(confirmation, dict) else None
                if not isinstance(message_id, str) or not re.fullmatch(r"\d{1,30}", message_id):
                    raise ValueError("No message acknowledgement")
            except (ValueError, UnicodeError):
                receipt.update(status="FAILED", reason="INVALID_SERVER_ACKNOWLEDGEMENT")
                return receipt, 1
            receipt["message_id"] = message_id
            channel_id = confirmation.get("channel_id")
            if isinstance(channel_id, str) and re.fullmatch(r"\d{1,30}", channel_id):
                receipt["channel_id"] = channel_id
            receipt["acknowledgement"] = "discord_created_message"
        receipt.update(status="DELIVERED", reason="SERVER_CONFIRMED_MESSAGE")
        return receipt, 0
    except HTTPError as error:
        receipt.update(status="FAILED", http_code=error.code,
                       reason="REDIRECT_REJECTED" if 300 <= error.code < 400 else "HTTP_ERROR")
    except (URLError, TimeoutError, OSError, ValueError, HTTPException):
        # Never format an exception: urllib exceptions can include the secret URL.
        receipt.update(status="FAILED", reason="NETWORK_NO_ACKNOWLEDGEMENT")
    return receipt, 1


def write_receipt(path: Path, receipt: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Notifica únicamente un fallo del CI de SnackUP.")
    parser.add_argument("--status", default=os.environ.get("CI_PIPELINE_STATUS", "unknown"))
    parser.add_argument("--stage", default=os.environ.get("CI_FAILED_STAGE", ""))
    parser.add_argument("--receipt", type=Path, default=Path("evidence/notification-receipt.json"))
    args = parser.parse_args(argv)
    receipt, code = notify(args.status, args.stage)
    try:
        write_receipt(args.receipt, receipt)
    except OSError:
        print("No se pudo escribir el comprobante de notificación.", file=sys.stderr)
        return 1
    print(json.dumps(receipt, ensure_ascii=False))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
