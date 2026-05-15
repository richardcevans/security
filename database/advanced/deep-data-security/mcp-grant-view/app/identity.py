import base64
import json
from typing import Dict, Optional, Tuple


class UserIdentity:
    def __init__(self, subject, display_name, roles, token_preview, access_token=None):
        # type: (str, str, Tuple[str, ...], str, Optional[str]) -> None
        self.subject = subject
        self.display_name = display_name
        self.roles = roles
        self.token_preview = token_preview
        self.access_token = access_token


def identity_from_authorization_header(authorization):
    # type: (Optional[str]) -> UserIdentity
    if not authorization:
        return demo_identity("marvin")

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        return demo_identity("marvin")

    if token.startswith("demo:"):
        return _identity_from_demo_token(token)

    return _identity_from_jwt_without_trust(token)


def demo_identity(name):
    # type: (str) -> UserIdentity
    identities = {
        "marvin": UserIdentity(
            "marvin@example.com",
            "Marvin",
            ("HR_VIEWER", "SALES_REGION_US"),
            "demo:marvin",
        ),
        "emma": UserIdentity(
            "emma@example.com",
            "Emma",
            ("HR_VIEWER", "FINANCE_ANALYST"),
            "demo:emma",
        ),
        "admin": UserIdentity(
            "admin@example.com",
            "DeepSec Admin",
            ("HR_VIEWER", "HR_ADMIN"),
            "demo:admin",
        ),
    }
    return identities.get(name.lower(), identities["marvin"])


def _identity_from_demo_token(token):
    # type: (str) -> UserIdentity
    _, _, remainder = token.partition(":")
    subject, _, role_text = remainder.partition(":")
    roles = tuple(role.strip() for role in role_text.split(",") if role.strip())
    display_name = subject.split("@", 1)[0].replace(".", " ").title() or "Demo User"
    return UserIdentity(
        subject or "demo@example.com",
        display_name,
        roles or ("HR_VIEWER",),
        "demo:{0}".format(subject),
    )


def _identity_from_jwt_without_trust(token):
    # type: (str) -> UserIdentity
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
        subject,
        display_name,
        roles,
        "jwt:{0}".format(subject),
        token,
    )


def _decode_jwt_payload(token):
    # type: (str) -> Dict
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


def _extract_roles(claims):
    # type: (Dict) -> Tuple[str, ...]
    values = []  # type: list
    for key in ("roles", "groups", "scp"):
        raw = claims.get(key)
        if isinstance(raw, str):
            values.extend(raw.split())
        elif isinstance(raw, list):
            values.extend(str(item) for item in raw)
    return tuple(sorted(set(values))) or ("HR_VIEWER",)
