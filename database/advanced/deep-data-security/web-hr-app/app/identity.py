import base64
import hashlib
import json
import os
import time
import uuid
from urllib.parse import urlencode
from urllib.error import HTTPError
from urllib.request import Request, urlopen


SESSIONS = {}


def app_config():
    tenant_id = os.getenv("TENANT_ID", "")
    client_id = os.getenv("WEB_HR_APP_CLIENT_ID", "")
    redirect_uri = os.getenv("WEB_HR_REDIRECT_URI", "http://localhost:8012/callback")
    user_scope = os.getenv("WEB_HR_USER_SCOPE", "")
    token_uri = os.getenv(
        "WEB_HR_TOKEN_URI",
        "https://login.microsoftonline.com/{0}/oauth2/v2.0/token".format(tenant_id),
    )
    auth_uri = os.getenv(
        "WEB_HR_AUTH_URI",
        "https://login.microsoftonline.com/{0}/oauth2/v2.0/authorize".format(tenant_id),
    )
    return {
        "tenant_id": tenant_id,
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "user_scope": user_scope,
        "token_uri": token_uri,
        "auth_uri": auth_uri,
        "db_mode": os.getenv("WEB_HR_DB_MODE", "mock"),
    }


def new_login():
    config = app_config()
    _require_login_config(config)
    state = uuid.uuid4().hex
    verifier = _base64url(os.urandom(48))
    challenge = _base64url(hashlib.sha256(verifier.encode("ascii")).digest())
    SESSIONS[state] = {
        "code_verifier": verifier,
        "created": time.time(),
    }
    params = {
        "client_id": config["client_id"],
        "response_type": "code",
        "redirect_uri": config["redirect_uri"],
        "response_mode": "query",
        "scope": "openid profile email {0}".format(config["user_scope"]).strip(),
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    }
    return "{0}?{1}".format(config["auth_uri"], urlencode(params))


def finish_login(state, code):
    session = SESSIONS.get(state)
    if not session:
        raise RuntimeError("Login session expired or was not found.")

    config = app_config()
    _require_login_config(config)
    token_request = {
        "grant_type": "authorization_code",
        "client_id": config["client_id"],
        "code": code,
        "redirect_uri": config["redirect_uri"],
        "code_verifier": session["code_verifier"],
        "scope": "openid profile email {0}".format(config["user_scope"]).strip(),
    }
    client_secret = os.getenv("WEB_HR_APP_CLIENT_SECRET", "")
    if client_secret:
        token_request["client_secret"] = client_secret
    body = urlencode(token_request).encode("utf-8")
    request = Request(
        config["token_uri"],
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urlopen(request, timeout=30) as response:
            token_response = json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        message = exc.read().decode("utf-8", "replace")
        raise RuntimeError("Token exchange failed: HTTP {0} {1}".format(exc.code, message))

    access_token = token_response.get("access_token", "")
    id_token = token_response.get("id_token", "")
    claims = decode_jwt_without_validation(id_token or access_token)
    session_id = uuid.uuid4().hex
    SESSIONS[session_id] = {
        "access_token": access_token,
        "id_token": id_token,
        "claims": claims,
        "created": time.time(),
    }
    SESSIONS.pop(state, None)
    return session_id


def demo_session(user_name):
    if user_name == "emma":
        subject = os.getenv("EMMA_UPN", "emma@example.com")
        roles = ["EMPLOYEES"]
        name = "Emma"
    else:
        subject = os.getenv("MARVIN_UPN", "marvin@example.com")
        roles = ["EMPLOYEES", "MANAGERS"]
        name = "Marvin"

    session_id = uuid.uuid4().hex
    SESSIONS[session_id] = {
        "access_token": "demo-token",
        "id_token": "",
        "claims": {
            "preferred_username": subject,
            "name": name,
            "roles": roles,
        },
        "created": time.time(),
    }
    return session_id


def session_from_cookie(cookie_header):
    cookies = {}
    for part in (cookie_header or "").split(";"):
        if "=" in part:
            key, value = part.strip().split("=", 1)
            cookies[key] = value
    return SESSIONS.get(cookies.get("web_hr_session", ""))


def clear_session(cookie_header):
    cookies = {}
    for part in (cookie_header or "").split(";"):
        if "=" in part:
            key, value = part.strip().split("=", 1)
            cookies[key] = value
    SESSIONS.pop(cookies.get("web_hr_session", ""), None)


def user_from_session(session):
    claims = (session or {}).get("claims") or {}
    username = (
        claims.get("preferred_username")
        or claims.get("upn")
        or claims.get("email")
        or claims.get("sub")
        or "anonymous"
    )
    return {
        "username": username,
        "name": claims.get("name") or username,
        "roles": extract_roles(claims),
        "access_token": (session or {}).get("access_token", ""),
    }


def extract_roles(claims):
    roles = []
    for key in ("roles", "groups", "scp"):
        raw = claims.get(key)
        if isinstance(raw, list):
            roles.extend(str(v) for v in raw)
        elif isinstance(raw, str):
            roles.extend(raw.split())
    return sorted(set(roles))


def decode_jwt_without_validation(token):
    parts = (token or "").split(".")
    if len(parts) < 2:
        return {}
    payload = parts[1] + "=" * (-len(parts[1]) % 4)
    try:
        return json.loads(base64.urlsafe_b64decode(payload.encode("ascii")).decode("utf-8"))
    except Exception:
        return {}


def _base64url(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _require_login_config(config):
    missing = []
    for key in ("tenant_id", "client_id", "redirect_uri", "user_scope"):
        if not config.get(key):
            missing.append(key)
    if missing:
        raise RuntimeError(
            "Microsoft Entra login is not configured. Missing: {0}. "
            "Run ./00_setup_entra_web_app.sh, then restart ./run.sh. "
            "For a quick local demo, use Demo Marvin or Demo Emma.".format(
                ", ".join(missing)
            )
        )
