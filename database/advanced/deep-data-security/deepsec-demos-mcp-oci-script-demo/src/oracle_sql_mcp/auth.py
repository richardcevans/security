# Copyright (c) 2026, Oracle and/or its affiliates.
# Implements the client-owned OCI IAM authorization-code browser-login flow.
# Depends on the Python standard library HTTP, TLS, URL, and browser modules.

"""OCI IAM authorization-code login used by an MCP client before it connects."""

from __future__ import annotations

import base64
import json
import os
import secrets
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer

from .config import Settings


def _oci_iam_ssl_context() -> ssl.SSLContext:
    """Use an organization-provided CA bundle when OCI IAM is behind TLS inspection."""
    ca_bundle = os.getenv("OCI_IAM_CA_BUNDLE", "").strip()
    if ca_bundle:
        return ssl.create_default_context(cafile=ca_bundle)
    return ssl.create_default_context()


def _receive_callback(redirect_uri: str, authorize_url: str, expected_state: str) -> str:
    """Wait for OCI IAM to redirect the browser to the registered localhost URI."""
    parsed = urllib.parse.urlparse(redirect_uri)
    if parsed.scheme != "http" or parsed.hostname not in {"localhost", "127.0.0.1"}:
        raise RuntimeError("REDIRECT_URI must be an http localhost callback URI for client login.")
    port = parsed.port or 80
    callback_path = parsed.path or "/"
    received: dict[str, str] = {}

    class CallbackHandler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802 - required by BaseHTTPRequestHandler
            request = urllib.parse.urlparse(self.path)
            if request.path == callback_path:
                received.update({key: values[0] for key, values in urllib.parse.parse_qs(request.query).items()})
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.end_headers()
                self.wfile.write(b"<h1>Sign-in complete</h1><p>You may close this window.</p>")
            else:
                self.send_error(404)

        def log_message(self, format: str, *args: object) -> None:
            return

    server = HTTPServer((parsed.hostname, port), CallbackHandler)
    server.timeout = 300
    try:
        print("Open this URL and sign in; the registered localhost callback will complete login:", file=sys.stderr)
        print(authorize_url, file=sys.stderr)
        webbrowser.open(authorize_url, new=1, autoraise=True)
        server.handle_request()
    finally:
        server.server_close()
    if "error" in received:
        raise RuntimeError(f"OCI IAM authorization failed: {received['error']}")
    if not secrets.compare_digest(received.get("state", ""), expected_state):
        raise RuntimeError("OCI IAM authorization response had an invalid state value.")
    code = received.get("code")
    if not code:
        raise RuntimeError("Timed out waiting for the OCI IAM browser callback.")
    return code


def login(settings: Settings) -> str:
    """Open OCI IAM sign-in and exchange the returned code for an MCP client token."""
    settings.require_login()
    base = settings.oci_domain_url.rstrip("/")
    state = secrets.token_urlsafe(32)
    authorize_url = f"{base}/oauth2/v1/authorize?" + urllib.parse.urlencode(
        {
            "client_id": settings.app_client_id,
            "response_type": "code",
            "redirect_uri": settings.redirect_uri,
            "scope": settings.app_scope,
            "state": state,
        },
        quote_via=urllib.parse.quote,
    )
    code = _receive_callback(settings.redirect_uri, authorize_url, state)
    basic = base64.b64encode(
        f"{settings.app_client_id}:{settings.app_client_secret}".encode()
    ).decode()
    request = urllib.request.Request(
        f"{base}/oauth2/v1/token",
        data=urllib.parse.urlencode(
            {"grant_type": "authorization_code", "code": code, "redirect_uri": settings.redirect_uri}
        ).encode(),
        headers={
            "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
            "Authorization": f"Basic {basic}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(
            request, timeout=30, context=_oci_iam_ssl_context()
        ) as response:
            payload = json.loads(response.read().decode())
    except urllib.error.HTTPError as exc:
        details = exc.read().decode(errors="replace")
        raise RuntimeError(f"OCI IAM token request failed: {exc.code} {exc.reason}: {details}") from exc
    except urllib.error.URLError as exc:
        if isinstance(exc.reason, ssl.SSLCertVerificationError):
            raise RuntimeError(
                "OCI IAM TLS certificate validation failed. Configure "
                "OCI_IAM_CA_BUNDLE to a PEM bundle that trusts your organization/proxy CA."
            ) from exc
        raise
    token = payload.get("access_token")
    if not token:
        raise RuntimeError("OCI IAM token response did not include access_token.")
    return token
