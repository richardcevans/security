from __future__ import annotations

import base64
import json
from dataclasses import dataclass, field


@dataclass(frozen=True)
class UserIdentity:
    subject: str
    display_name: str
    roles: tuple[str, ...]
    token_preview: str
    access_token: str | None = field(default=None, repr=False)


def identity_from_authorization_header(authorization: str | None) -> UserIdentity:
    if not authorization:
        return demo_identity("marvin")

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        return demo_identity("marvin")

    if token.startswith("demo:"):
        return _identity_from_demo_token(token)

    return _identity_from_jwt_without_trust(token)


def demo_identity(name: str) -> UserIdentity:
    identities = {
        "marvin": UserIdentity(
            subject="marvin@example.com",
            display_name="Marvin",
            roles=("HR_VIEWER", "SALES_REGION_US"),
            token_preview="demo:marvin",
            access_token=None,
        ),
        "emma": UserIdentity(
            subject="emma@example.com",
            display_name="Emma",
            roles=("HR_VIEWER", "FINANCE_ANALYST"),
            token_preview="demo:emma",
            access_token=None,
        ),
        "admin": UserIdentity(
            subject="admin@example.com",
            display_name="DeepSec Admin",
            roles=("HR_VIEWER", "HR_ADMIN"),
            token_preview="demo:admin",
            access_token=None,
        ),
    }
    return identities.get(name.lower(), identities["marvin"])


def _identity_from_demo_token(token: str) -> UserIdentity:
    _, _, remainder = token.partition(":")
    subject, _, role_text = remainder.partition(":")
    roles = tuple(role.strip() for role in role_text.split(",") if role.strip())
    display_name = subject.split("@", 1)[0].replace(".", " ").title() or "Demo User"
    return UserIdentity(
        subject=subject or "demo@example.com",
        display_name=display_name,
        roles=roles or ("HR_VIEWER",),
        token_preview=f"demo:{subject}",
        access_token=None,
    )


def _identity_from_jwt_without_trust(token: str) -> UserIdentity:
    """Decode JWT claims for local demos.

    This is not trust validation. Real deployments must validate issuer,
    audience, signature, expiry, and the IdP JWKS before trusting claims.
    """
    claims = _decode_jwt_payload(token)
    subject = str(
        claims.get("preferred_username")
        or claims.get("upn")
        or claims.get("email")
        or claims.get("sub")
        or "unknown-user"
    )
    display_name = str(claims.get("name") or subject)
    roles = _extract_roles(claims)
    return UserIdentity(
        subject=subject,
        display_name=display_name,
        roles=roles,
        token_preview=f"jwt:{subject}",
        access_token=token,
    )


def _decode_jwt_payload(token: str) -> dict:
    parts = token.split(".")
    if len(parts) < 2:
        return {}
    payload = parts[1]
    payload += "=" * (-len(payload) % 4)
    try:
        decoded = base64.urlsafe_b64decode(payload.encode("ascii"))
        return json.loads(decoded.decode("utf-8"))
    except (ValueError, json.JSONDecodeError):
        return {}


def _extract_roles(claims: dict) -> tuple[str, ...]:
    values: list[str] = []
    for key in ("roles", "groups", "scp"):
        raw = claims.get(key)
        if isinstance(raw, str):
            values.extend(raw.split())
        elif isinstance(raw, list):
            values.extend(str(item) for item in raw)
    return tuple(sorted(set(values))) or ("HR_VIEWER",)
