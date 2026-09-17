# Copyright (c) 2026, Oracle and/or its affiliates.
# Validates OCI IAM bearer tokens presented to the Streamable HTTP MCP endpoint.
# Depends on httpx for OAuth token introspection and MCP auth types.

"""OAuth token introspection for the MCP server's resource-server role."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

import httpx
from mcp.server.auth.provider import AccessToken, TokenVerifier

from .config import Settings


class OciIamTokenVerifier(TokenVerifier):
    """Validate bearer tokens through OCI IAM introspection."""

    def __init__(self, settings: Settings) -> None:
        settings.require_http_auth()
        self._issuer = settings.mcp_token_issuer
        self._audience = settings.mcp_auth_audience
        self._url = settings.mcp_introspection_url
        self._client_id = settings.mcp_introspection_client_id
        self._client_secret = settings.mcp_introspection_client_secret

    async def verify_token(self, token: str) -> AccessToken | None:
        try:
            async with httpx.AsyncClient(timeout=20) as client:
                response = await client.post(
                    self._url,
                    data={"token": token, "token_type_hint": "access_token"},
                    auth=(self._client_id, self._client_secret),
                )
            response.raise_for_status()
            claims = response.json()
        except (httpx.HTTPError, ValueError):
            return None

        if not claims.get("active"):
            return None
        if claims.get("iss") != self._issuer:
            return None
        if self._audience not in _as_list(claims.get("aud")):
            return None
        if _expired(claims.get("exp")):
            return None
        scopes = _scopes_from_claims(claims)
        subject = str(claims.get("sub") or claims.get("user_id") or "")
        client_id = str(claims.get("client_id") or claims.get("azp") or subject)
        if not subject or not client_id:
            return None
        return AccessToken(token=token, client_id=client_id, scopes=scopes, subject=subject)


def _scopes_from_claims(claims: dict[str, Any]) -> list[str]:
    """Normalize common OAuth scope claim formats to the MCP SDK representation."""
    scope = claims.get("scope", claims.get("scp", []))
    if isinstance(scope, str):
        return scope.split()
    if isinstance(scope, list) and all(isinstance(value, str) for value in scope):
        return scope
    return []


def _as_list(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, list) and all(isinstance(item, str) for item in value):
        return value
    return []


def _expired(value: Any) -> bool:
    """Reject expired or malformed expiry values even if an upstream server says active."""
    try:
        expiry = datetime.fromtimestamp(float(value), tz=UTC)
    except (TypeError, ValueError, OverflowError):
        return True
    return expiry <= datetime.now(tz=UTC)
