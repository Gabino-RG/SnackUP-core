"""Check the three apps through the CI proxy without accounts or external I/O.

Install the exact websockets requirement from requirements.lock before running.
The TCP destination is loopback HTTP; Host and Origin exercise the configured
production domain. Reports contain response metadata, never cookies or bodies.
"""
import argparse
import hashlib
import json
import socket
import sys
from datetime import UTC, datetime
from html.parser import HTMLParser
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener

from websockets.sync.client import connect


class SmokeFailure(Exception):
    pass


def require(condition, message):
    if not condition:
        raise SmokeFailure(message)


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class IndexMetadata(HTMLParser):
    def __init__(self):
        super().__init__()
        self.bases = []
        self.scripts = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "base":
            self.bases.append(attrs.get("href"))
        if tag == "script" and attrs.get("src"):
            self.scripts.append(attrs["src"])


class Smoke:
    def __init__(self, url, host, origin):
        self.url, self.host, self.origin = url.rstrip("/"), host, origin
        self.opener = build_opener(ProxyHandler({}), NoRedirect())
        self.results = []

    def get(self, path, expected=200, method="GET"):
        request = Request(self.url + path, method=method,
                          headers={"Host": self.host, "Origin": self.origin,
                                   "Accept-Encoding": "identity"})
        try:
            response = self.opener.open(request, timeout=15)
        except HTTPError as error:
            response = error
        with response:
            # Two main.dart.js files are the only potentially large responses.
            body = response.read(64 * 1024 * 1024 + 1)
            item = {"method": method, "path": path, "status": response.status,
                    "contentType": response.headers.get("Content-Type", ""),
                    "bytes": len(body), "sha256": hashlib.sha256(body).hexdigest(),
                    "ok": False}
            self.results.append(item)
            require(response.status == expected,
                    f"{method} {path}: expected {expected}, received {response.status}")
            require(len(body) <= 64 * 1024 * 1024, f"{path}: response exceeds smoke limit")
            item["ok"] = True
            return response.headers, body

    def json(self, path, expected=200):
        headers, body = self.get(path, expected)
        require(headers.get_content_type() == "application/json", f"{path}: expected JSON")
        try:
            return json.loads(body)
        except (ValueError, UnicodeError) as error:
            raise SmokeFailure(f"{path}: invalid JSON") from error

    def asset(self, path, expected_type):
        headers, body = self.get(path)
        require(headers.get_content_type() in expected_type, f"{path}: unexpected asset type")
        require(bool(body), f"{path}: empty asset")
        require(not body.lstrip().lower().startswith((b"<!doctype html", b"<html")),
                f"{path}: SPA HTML returned in place of an asset")
        require("no-cache" in headers.get("Cache-Control", ""), f"{path}: expected revalidation")
        return body

    def frontend(self, base, pwa=False):
        headers, body = self.get(base)
        require(headers.get_content_type() == "text/html", f"{base}: expected HTML")
        metadata = IndexMetadata()
        metadata.feed(body.decode("utf-8"))
        require(metadata.bases == [base], f"{base}: incorrect or duplicate base href")
        require("flutter_bootstrap.js" in metadata.scripts, f"{base}: missing Flutter bootstrap")
        require(self.get(base + "__ci_deep_link__")[1] == body, f"{base}: broken SPA deep link")
        self.get(base + "__ci_missing_asset__.js", 404)
        js_types = {"application/javascript", "text/javascript"}
        self.asset(base + "flutter_bootstrap.js", js_types)
        self.asset(base + "main.dart.js", js_types)
        manifest_body = self.asset(base + "manifest.json", {"application/json", "application/manifest+json"})
        manifest = json.loads(manifest_body)
        require(isinstance(manifest, dict), f"{base}: invalid manifest")
        # Fetch a real image with the same prefix, without following remote URLs.
        icons = manifest.get("icons", [])
        require(bool(icons), f"{base}: manifest lacks an icon")
        icon = icons[0].get("src", "")
        require(isinstance(icon, str) and icon.startswith("icons/")
                and ".." not in icon and "?" not in icon and "#" not in icon,
                f"{base}: unexpected icon path")
        self.asset(base + icon, {"image/png", "image/webp", "image/svg+xml"})
        if pwa:
            require(manifest.get("scope") == "." and manifest.get("id") == ".",
                    "Student manifest has incorrect scope/id")
            self.asset(base + "pwa.js", js_types)
            self.asset(base + "snackup_service_worker.js", js_types)
            headers, _ = self.get(base + "offline.html")
            require(headers.get_content_type() == "text/html", "Missing student offline page")

    def socketio(self):
        path = "/socket.io/?EIO=4&transport=websocket"
        error = self.json(path, 400)
        require(error.get("error", {}).get("code") == "WEBSOCKET_REQUIRED",
                "Socket.IO HTTP error was replaced or changed by the proxy")
        endpoint = urlsplit(self.url)
        item = {"method": "WEBSOCKET", "path": path, "ok": False}
        self.results.append(item)
        # Explicit socket bypasses DNS; the public domain remains the HTTP Host.
        with (
            socket.create_connection((endpoint.hostname, endpoint.port or 80), timeout=15) as tcp,
            connect("ws://" + self.host + path, sock=tcp, origin=self.origin,
                    proxy=None, compression=None, open_timeout=15, close_timeout=3,
                    ping_interval=None, max_size=16384) as websocket,
        ):
            item["status"] = websocket.response.status_code
            require(item["status"] == 101, "Socket.IO upgrade did not return HTTP 101")
            opened = websocket.recv(timeout=10)
            require(isinstance(opened, str) and opened.startswith("0{"),
                    "Missing Engine.IO open packet")
            handshake = json.loads(opened[1:])
            require(bool(handshake.get("sid")) and handshake.get("upgrades") == [],
                    "Unexpected Engine.IO handshake")
            # No token, user, order or topic is supplied. Authentication must fail.
            websocket.send("40")
            packet = websocket.recv(timeout=10)
            require(isinstance(packet, str) and packet.startswith("44"),
                    "Socket.IO accepted or failed to reject an unauthenticated connect")
            rejection = json.loads(packet[2:])
            require(rejection.get("message") == "UNAUTHENTICATED"
                    and rejection.get("data", {}).get("code") == "UNAUTHENTICATED",
                    "Unexpected Socket.IO authentication rejection")
            item.update(ok=True, engineIO="open", socketIO="UNAUTHENTICATED")

    def run(self):
        require(self.json("/health/live") == {"status": "ok"}, "Liveness failed")
        require(self.json("/health/ready") == {"status": "ready"}, "Database/Redis readiness failed")
        self.frontend("/", pwa=True)
        headers, _ = self.get("/paneles", 308)
        require(headers.get("Location") == "/paneles/", "Panel prefix redirect is incorrect")
        self.frontend("/paneles/")
        canonical = self.json("/api/v1/auth/options")
        legacy = self.json("/api/legacy/v1/auth/options")
        expected_options = {"passwordLogin": True, "selfRegistration": False, "googleEnabled": False}
        require(canonical == legacy == expected_options,
                "Auth options differ from the empty CI installation or legacy adapter")
        # Missing endpoints/assets must reach FastAPI, never either Flutter SPA.
        for path in ["/api/v1/__ci_missing__", "/api/legacy/v1/__ci_missing__",
                     "/media/__ci_missing__.webp"]:
            self.json(path, 404)
        self.socketio()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:18080")
    parser.add_argument("--host", default="snackup.example.test")
    parser.add_argument("--origin", default="https://snackup.example.test")
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    endpoint = urlsplit(args.url)
    if (endpoint.scheme != "http" or endpoint.hostname not in {"127.0.0.1", "localhost", "::1"}
            or endpoint.path not in {"", "/"} or endpoint.username or endpoint.password
            or endpoint.query or endpoint.fragment):
        parser.error("--url must be a loopback HTTP origin for the isolated CI proxy")
    if args.host != "snackup.example.test" or args.origin != "https://snackup.example.test":
        parser.error("This smoke is restricted to the synthetic CI host and HTTPS origin")
    smoke = Smoke(args.url, args.host, args.origin)
    report = {"version": 1, "timestamp": datetime.now(UTC).isoformat(),
              "destination": args.url, "host": args.host, "origin": args.origin,
              "success": False, "checks": smoke.results}
    try:
        smoke.run()
        report["success"] = True
    except Exception as error:  # noqa: BLE001 - every failed check must leave its CI report.
        # No response body, cookie, socket SID, authentication packet or env dump.
        report["error"] = f"{type(error).__name__}: {error}"
    finally:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if not report["success"]:
        print(report["error"], file=sys.stderr)
        return 1
    print(f"Common proxy smoke passed: {len(smoke.results)} HTTP/WebSocket checks; no account used.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
