import os
import hmac
import time
import uuid


SESSIONS = {}


LOCAL_USERS = {
    "emma": {
        "username": "emma",
        "name": "Emma Baker",
        "roles": ["HRAPP_EMPLOYEES"],
    },
    "marvin": {
        "username": "marvin",
        "name": "Marvin Morgan",
        "roles": ["HRAPP_EMPLOYEES", "HRAPP_MANAGERS"],
    },
}


def app_config():
    return {
        "db_mode": os.getenv("WEB_HR_DB_MODE", "mock"),
        "auth_mode": "local-end-user",
        "tns_alias": default_tns_alias(),
        "pdb_name": os.getenv("PDB_NAME", "FREEPDB1"),
    }


def default_tns_alias():
    return os.getenv("WEB_HR_TNS_ALIAS") or os.getenv("PDB_NAME") or "FREEPDB1"


def expected_password(user_name):
    key = (user_name or "").lower()
    if key not in LOCAL_USERS:
        return None
    specific = os.getenv("WEB_HR_{0}_PASSWORD".format(key.upper()))
    return specific or os.getenv("WEB_HR_END_USER_PASSWORD", "Oracle123")


def local_session(user_name, password):
    key = (user_name or "").lower()
    user = LOCAL_USERS.get(key)
    if not user:
        raise RuntimeError("Invalid username or password.")
    expected = expected_password(key)
    if not hmac.compare_digest(str(password or ""), str(expected or "")):
        raise RuntimeError("Invalid username or password.")

    session_user = dict(user)
    session_user["roles"] = list(user.get("roles", []))

    session_id = uuid.uuid4().hex
    SESSIONS[session_id] = {
        "user": session_user,
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
    user = dict((session or {}).get("user") or {})
    if not user:
        return None
    user["password_env"] = "WEB_HR_{0}_PASSWORD".format(user["username"].upper())
    return user


def token_debug_from_session(session):
    if not session:
        return None
    return {
        "auth_mode": "local-end-user",
        "message": "This app does not use Entra ID or OAuth tokens. The selected end user authenticates directly to Oracle Database.",
        "user": user_from_session(session),
    }
