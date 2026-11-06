#!/usr/bin/env python3
"""Validate a reviewed Flutter web build for same-origin REST.

Historical callers may pass --mode firebase. Both spellings validate REST.
"""
from __future__ import annotations

import argparse
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sys


class Index(HTMLParser):
    def __init__(self):
        super().__init__()
        self.bases = []
        self.scripts = []

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == "base":
            self.bases.append(attributes.get("href"))
        if tag == "script" and "src" in attributes:
            self.scripts.append(attributes["src"])


def validate(directory: Path, base: str) -> None:
    if not base.startswith("/") or not base.endswith("/") or "//" in base or ".." in base.split("/"):
        raise ValueError("--base must be a local absolute directory path ending in '/'.")
    required = ["index.html", "flutter_bootstrap.js", "flutter.js", "main.dart.js", "assets/FontManifest.json", "assets/AssetManifest.bin"]
    required.extend(["snackup-push.js", "snackup-push-sw.js"])
    for name in required:
        path = directory / name
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"Missing or empty Flutter build asset: {name}")
    index = Index()
    index.feed((directory / "index.html").read_text(encoding="utf-8"))
    if index.bases != [base]:
        raise ValueError(f"Expected one base href={base!r}; found {index.bases!r}.")
    if not any(source.split("?")[0] in {"flutter_bootstrap.js", base + "flutter_bootstrap.js"} for source in index.scripts):
        raise ValueError("index.html does not load the local Flutter bootstrap.")
    if "snackup-push.js" not in index.scripts:
        raise ValueError("index.html does not load the local browser push bridge.")
    if any(re.match(r"(?:https?:)?//", source) for source in index.scripts):
        raise ValueError("index.html contains a remote bootstrap script.")
    bootstrap = (directory / "flutter_bootstrap.js").read_text(encoding="utf-8")
    if "main.dart.js" not in bootstrap:
        raise ValueError("Flutter bootstrap does not reference the JavaScript entrypoint.")
    # Disabling CDN and service workers is part of the unchanged unified build.
    # The engine loader includes an unused CDN fallback even in local builds;
    # inspect the emitted build setting rather than rejecting that code string.
    if not re.search(r'["\']?useLocalCanvasKit["\']?\s*:\s*true', bootstrap):
        raise ValueError("The build does not select local CanvasKit; use --no-web-resources-cdn.")
    if not any((directory / "canvaskit").rglob("*.wasm")):
        raise ValueError("The local CanvasKit WebAssembly assets are missing.")
    if re.search(r'["\']?serviceWorkerVersion["\']?\s*:\s*["\'][^"\']+["\']', bootstrap):
        raise ValueError("A generated service worker is enabled; rebuild with --pwa-strategy=none.")
    program = (directory / "main.dart.js").read_text(encoding="utf-8")
    api_root = "/api/legacy/v1/" if base == "/paneles/" else "/api/v1"
    if api_root not in program:
        raise ValueError(f"The compiled client does not contain its expected REST API root {api_root}.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--base", required=True)
    parser.add_argument("--mode", choices=["rest", "firebase"], default="rest")
    args = parser.parse_args()
    try:
        validate(args.directory.resolve(), args.base)
    except (OSError, ValueError) as error:
        print(f"Web build validation failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"build": str(args.directory), "base": args.base, "transport": "REST", "status": "passed"}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
