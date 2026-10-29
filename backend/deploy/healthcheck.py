"""Loopback probe preserving the configured Host allowlist."""
import os
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

origin = urlsplit(os.environ.get("SNACKUP_PUBLIC_ORIGIN", "http://localhost:8000"))
request = Request("http://127.0.0.1:8000/health/ready", headers={"Host": origin.netloc})
with urlopen(request, timeout=4) as response:
    if response.status != 200:
        raise SystemExit(1)
