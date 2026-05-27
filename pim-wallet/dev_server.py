#!/usr/bin/env python3
"""Dev server for pim-wallet.

Serves the repo root as static files and provides a tiny GitLab proxy to avoid
browser CORS restrictions when exchanging OAuth codes for tokens.

Run:
  python3 pim-wallet/dev_server.py
Then open:
  http://localhost:8000/pim-wallet/index.html

Environment:
  PORT=8000
"""

from __future__ import annotations

import os
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from typing import Optional
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen


def _clean_base_url(raw: str) -> Optional[str]:
    raw = (raw or "").strip()
    if not raw:
        return None
    parsed = urlparse(raw)
    if parsed.scheme != "https" or not parsed.netloc:
        return None
    # Disallow credentials in URL
    if parsed.username or parsed.password:
        return None
    return f"{parsed.scheme}://{parsed.netloc}".rstrip("/")


class Handler(SimpleHTTPRequestHandler):
    def end_headers(self) -> None:
        # Security-ish headers for local dev
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")

        # Allow calls from the app to the local proxy endpoints.
        if self.path.startswith("/gitlab/"):
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type, X-GitLab-Base-Url")

        super().end_headers()

    def do_OPTIONS(self) -> None:
        if self.path.startswith("/gitlab/"):
            self.send_response(204)
            self.end_headers()
            return
        super().do_OPTIONS()

    def _resolve_gitlab_base(self) -> str:
        header_base = self.headers.get("X-GitLab-Base-Url", "")
        env_base = os.getenv("GITLAB_BASE_URL", "https://gitlab.com")
        base = _clean_base_url(header_base) or _clean_base_url(env_base) or "https://gitlab.com"
        return base.rstrip("/")

    def _proxy(self, method: str, upstream_path: str, body: Optional[bytes] = None, extra_headers: Optional[dict] = None) -> None:
        base = self._resolve_gitlab_base()
        upstream_url = base + upstream_path

        headers = {
            "Accept": "application/json",
        }
        if extra_headers:
            headers.update(extra_headers)

        req = Request(upstream_url, data=body, method=method, headers=headers)

        try:
            with urlopen(req, timeout=25) as resp:
                data = resp.read()
                self.send_response(resp.status)
                ct = resp.headers.get("Content-Type")
                if ct:
                    self.send_header("Content-Type", ct)
                self.end_headers()
                self.wfile.write(data)
        except HTTPError as e:
            data = e.read() if hasattr(e, "read") else b""
            self.send_response(getattr(e, "code", 502))
            self.send_header("Content-Type", e.headers.get("Content-Type", "text/plain"))
            self.end_headers()
            self.wfile.write(data or str(e).encode("utf-8", "replace"))
        except URLError as e:
            self.send_response(502)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(f"Upstream error: {e}".encode("utf-8", "replace"))

    def do_POST(self) -> None:
        if self.path.startswith("/gitlab/oauth/token"):
            length = int(self.headers.get("Content-Length", "0") or "0")
            body = self.rfile.read(length) if length > 0 else b""
            self._proxy(
                "POST",
                "/oauth/token",
                body=body,
                extra_headers={"Content-Type": self.headers.get("Content-Type", "application/x-www-form-urlencoded")},
            )
            return

        super().do_POST()

    def do_GET(self) -> None:
        if self.path.startswith("/gitlab/ping"):
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"ok")
            return

        if self.path.startswith("/gitlab/api/v4/user"):
            auth = self.headers.get("Authorization", "")
            extra = {"Authorization": auth} if auth else {}
            self._proxy("GET", "/api/v4/user", extra_headers=extra)
            return

        super().do_GET()


def main() -> int:
    port = int(os.getenv("PORT", "8000"))
    host = os.getenv("HOST", "0.0.0.0")
    # Serve the repo root so /pim-wallet/index.html works.
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    handler = partial(Handler, directory=repo_root)
    httpd = ThreadingHTTPServer((host, port), handler)

    print(f"Serving '{repo_root}' on http://{host}:{port}/")
    print(f"Open: http://localhost:{port}/pim-wallet/index.html")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
