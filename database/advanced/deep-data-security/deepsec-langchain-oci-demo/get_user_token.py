# Copyright (c) 2026, Oracle and/or its affiliates.
# Authenticates an end user with OCI IAM using the Authorization Code flow and
# returns an access token for the requested agent scope. The token is attached
# to Oracle Deep Data Security sessions as the end-user identity.
#
# Dependencies:
# - Python standard library (urllib)
# - python-dotenv
# - <HR|COMP>_OCI_DOMAIN_URL, <HR|COMP>_APP_CLIENT_ID,
#   <HR|COMP>_APP_CLIENT_SECRET, <HR|COMP>_APP_SCOPE, and
#   <HR|COMP>_REDIRECT_URI environment variables

from __future__ import annotations

import base64
import json
import urllib.error
import urllib.parse
import urllib.request

from dotenv import load_dotenv

load_dotenv()


def _extract_authorization_code(value: str) -> str:
    value = value.strip()
    if not value:
        raise RuntimeError("No authorization code or redirect URL was provided.")

    # Accept either the authorization code itself or the full redirect URL.
    parsed = urllib.parse.urlparse(value)
    if parsed.scheme and parsed.query:
        query = urllib.parse.parse_qs(parsed.query)
        code = query.get("code", [""])[0]
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
    """
    Authenticate the current user with OCI IAM and return an access token.
    This uses the authorization-code flow and works in a headless workflow
    where the user copies the final redirect URL back into the terminal.
    """
    if not all([domain_url, client_id, client_secret, scope, redirect_uri]):
        raise RuntimeError(
            "Missing OCI IAM auth config: "
            f"domain_url={domain_url!r}, client_id={client_id!r}, "
            f"client_secret={'***' if client_secret else ''!r}, "
            f"scope={scope!r}, redirect_uri={redirect_uri!r}"
        )

    base = domain_url.rstrip("/")
    authorize_params = {
        "client_id": client_id,
        "response_type": "code",
        "redirect_uri": redirect_uri,
        "scope": scope,
    }
    authorize_url = (
        f"{base}/oauth2/v1/authorize?"
        + urllib.parse.urlencode(authorize_params, quote_via=urllib.parse.quote)
    )

    print(
        "\nOpen this URL in a browser, sign in as the OCI IAM user, then paste the final redirect URL back here:\n"
    )
    print(authorize_url)
    redirect_response = input("\nRedirect URL or authorization code: ").strip()
    authorization_code = _extract_authorization_code(redirect_response)

    token_url = f"{base}/oauth2/v1/token"
    token_body = urllib.parse.urlencode(
        {
            "grant_type": "authorization_code",
            "code": authorization_code,
            "redirect_uri": redirect_uri,
        }
    ).encode("utf-8")

    headers = {
        "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
    }
    basic = base64.b64encode(f"{client_id}:{client_secret}".encode("utf-8")).decode("ascii")
    headers["Authorization"] = f"Basic {basic}"

    request = urllib.request.Request(
        token_url,
        data=token_body,
        headers=headers,
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"OCI IAM token request failed: {exc.code} {exc.reason}: {details}") from exc

    access_token = payload.get("access_token")
    if not access_token:
        raise RuntimeError(
            f"OCI IAM token response did not include access_token: {payload!r}"
        )

    return access_token
