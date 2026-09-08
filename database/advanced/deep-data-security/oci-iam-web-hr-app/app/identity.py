"""OCI IAM Authorization Code + PKCE login for the Web HR sample."""

import base64
import hashlib
import json
import os
import time
import uuid
from urllib.parse import urlencode
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import jwt
from jwt import PyJWKClient


SESSIONS = {}


def app_config():
    domain_url = os.getenv("OCI_DOMAIN_URL", "").rstrip("/")
    client_id = os.getenv("OCI_CLIENT_ID", "")
    redirect_uri = os.getenv("WEB_HR_REDIRECT_URI", "http://localhost:8012/callback")
    resource_scope = os.getenv("OCI_SCOPE", "")
    return {
        "domain_url": domain_url,
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "resource_scope": resource_scope,
        "auth_uri": "{0}/oauth2/v1/authorize".format(domain_url),
        "token_uri": "{0}/oauth2/v1/token".format(domain_url),
        "db_mode": "oci_iam_oauth",
    }


def new_login(prompt=None):
    config = app_config()
    _require_login_config(config)
    state = uuid.uuid4().hex
    verifier = _base64url(os.urandom(48))
    challenge = _base64url(hashlib.sha256(verifier.encode("ascii")).digest())
    SESSIONS[state] = {"code_verifier": verifier, "created": time.time()}
    params = {
        "client_id": config["client_id"],
        "response_type": "code",
        "redirect_uri": config["redirect_uri"],
        "response_mode": "query",
        "scope": "openid profile email {0}".format(config["resource_scope"]).strip(),
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    }
    if prompt:
        params["prompt"] = prompt
    return "{0}?{1}".format(config["auth_uri"], urlencode(params))


def finish_login(state, code):
    session = SESSIONS.get(state)
    if not session or not code:
        raise RuntimeError("Login session expired or the authorization code is missing.")
    config = app_config()
    _require_login_config(config)
    request_data = {
        "grant_type": "authorization_code",
        "client_id": config["client_id"],
        "code": code,
        "redirect_uri": config["redirect_uri"],
        "code_verifier": session["code_verifier"],
    }
    body = urlencode(request_data).encode("utf-8")
    request = Request(config["token_uri"], data=body, headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urlopen(request, timeout=30) as response:
            token_response = json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        raise RuntimeError("OCI IAM token exchange failed: HTTP {0} {1}".format(exc.code, exc.read().decode("utf-8", "replace")))

    access_token = token_response.get("access_token", "")
    id_token = token_response.get("id_token", "")
    if not access_token or not id_token:
        raise RuntimeError("OCI IAM did not return both an access token and ID token.")
    claims = _verify_id_token(id_token, config)
    session_id = uuid.uuid4().hex
    SESSIONS[session_id] = {"access_token": access_token, "id_token": id_token, "claims": claims, "created": time.time()}
    SESSIONS.pop(state, None)
    return session_id


def session_from_cookie(cookie_header):
    return SESSIONS.get(_cookies(cookie_header).get("web_hr_session", ""))


def clear_session(cookie_header):
    SESSIONS.pop(_cookies(cookie_header).get("web_hr_session", ""), None)


def user_from_session(session):
    claims = (session or {}).get("claims") or {}
    username = claims.get("user_name") or claims.get("preferred_username") or claims.get("email") or claims.get("sub") or "anonymous"
    return {"username": username, "name": claims.get("name") or username, "roles": extract_roles(claims), "access_token": (session or {}).get("access_token", "")}


def token_debug_from_session(session):
    if not session:
        return None
    return {"id_token": public_claims((session or {}).get("claims") or {}), "user_access_token": public_claims(decode_jwt_without_validation((session or {}).get("access_token", "")))}


def public_claims(claims):
    keys = ("aud", "client_id", "iss", "name", "sub", "user_name", "preferred_username", "email", "groups", "app_roles", "scope")
    return {key: claims[key] for key in keys if key in claims}


def extract_roles(claims):
    roles = []
    for key in ("groups", "app_roles", "roles", "scp"):
        value = claims.get(key)
        roles.extend(str(item) for item in value) if isinstance(value, list) else roles.extend(str(value).split()) if value else None
    return sorted(set(roles))


def decode_jwt_without_validation(token):
    try:
        return jwt.decode(token, options={"verify_signature": False, "verify_aud": False})
    except jwt.PyJWTError:
        return {}


def _verify_id_token(token, config):
    metadata_uri = "{0}/.well-known/openid-configuration".format(config["domain_url"])
    with urlopen(metadata_uri, timeout=30) as response:
        metadata = json.loads(response.read().decode("utf-8"))
    key = PyJWKClient(metadata["jwks_uri"]).get_signing_key_from_jwt(token).key
    return jwt.decode(token, key, algorithms=["RS256", "RS384", "RS512"], audience=config["client_id"], issuer=metadata["issuer"])


def _cookies(cookie_header):
    return dict(part.strip().split("=", 1) for part in (cookie_header or "").split(";") if "=" in part)


def _base64url(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _require_login_config(config):
    missing = [key for key in ("domain_url", "client_id", "redirect_uri", "resource_scope") if not config.get(key)]
    if missing:
        raise RuntimeError("OCI IAM login is not configured. Missing: {0}. Source ../deep-sec-mcp/.deep-sec-mcp.env and configure WEB_HR_REDIRECT_URI.".format(", ".join(missing)))
