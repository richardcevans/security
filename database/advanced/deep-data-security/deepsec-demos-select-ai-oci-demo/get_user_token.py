# Copyright (c) 2026, Oracle and/or its affiliates.
# Runs the OCI IAM Authorization Code flow and returns the end-user token.

from __future__ import annotations

import base64
import json
import os
import ssl
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

import certifi


def _ssl_context():
    """Return a verified TLS context for OCI IAM token requests.

    TLS_CA_BUNDLE is useful on hardened VMs that trust an enterprise CA rather
    than the public CA bundle. Otherwise use certifi so minimal Python builds
    still trust OCI IAM's public certificate chain.
    """
    ca_bundle = os.getenv("TLS_CA_BUNDLE") or os.getenv("SSL_CERT_FILE")
    return ssl.create_default_context(cafile=ca_bundle or certifi.where())


def _extract_authorization_code(value: str) -> str:
    """Accept either the authorization code or the complete redirect URL."""
    value = value.strip()
    if not value:
        raise RuntimeError("No authorization code or redirect URL was provided.")

    parsed = urllib.parse.urlparse(value)
    if parsed.scheme and parsed.query:
        code = urllib.parse.parse_qs(parsed.query).get("code", [""])[0]
        if code:
            return code

    if "code=" in value:
        query = urllib.parse.urlparse(value).query or value.split("?", 1)[-1]
        code = urllib.parse.parse_qs(query).get("code", [""])[0]
        if code:
            return code

    return value


def get_access_token(
    *,
    domain_url: str,
    client_id: str,
    client_secret: str,
    scope: str,
    redirect_uri: str,
) -> str:
    """Run the OCI IAM authorization-code flow and return an end-user token."""
    missing = [
        name
        for name, value in {
            "OCI_DOMAIN_URL": domain_url,
            "APP_CLIENT_ID": client_id,
            "APP_CLIENT_SECRET": client_secret,
            "APP_SCOPE": scope,
            "REDIRECT_URI": redirect_uri,
        }.items()
        if not value
    ]
    if missing:
        raise RuntimeError("Missing OCI IAM login configuration: " + ", ".join(missing))

    base = domain_url.rstrip("/")
    authorize_url = f"{base}/oauth2/v1/authorize?" + urllib.parse.urlencode(
        {
            "client_id": client_id,
            "response_type": "code",
            "redirect_uri": redirect_uri,
            "scope": scope,
        },
        quote_via=urllib.parse.quote,
    )
    print("\nOpen this URL in a browser, sign in, then paste the final redirect URL here:\n")
    print(authorize_url)
    try:
        webbrowser.open(authorize_url, new=1, autoraise=True)
    except Exception:
        pass

    authorization_code = _extract_authorization_code(input("\nRedirect URL or authorization code: "))
    request = urllib.request.Request(
        f"{base}/oauth2/v1/token",
        data=urllib.parse.urlencode(
            {
                "grant_type": "authorization_code",
                "code": authorization_code,
                "redirect_uri": redirect_uri,
            }
        ).encode("utf-8"),
        headers={
            "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
            "Authorization": "Basic "
            + base64.b64encode(f"{client_id}:{client_secret}".encode("utf-8")).decode("ascii"),
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(
            request,
            timeout=30,
            context=_ssl_context(),
        ) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"OCI IAM token request failed: {exc.code} {exc.reason}: {details}") from exc

    if not (access_token := payload.get("access_token")):
        raise RuntimeError("OCI IAM token response did not include access_token.")
    return access_token
