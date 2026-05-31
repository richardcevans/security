import os
from pathlib import Path

import oracledb
from dotenv import load_dotenv


load_dotenv()


def required_env(name):
    value = os.getenv(name)
    if value:
        value = value.strip().strip('"').strip("'")
    if (
        not value
        or value.startswith("replace-")
        or value.startswith("your-")
        or value.startswith("/path/to/")
    ):
        raise RuntimeError(f"Set {name} in .env before running this script.")
    return value


def optional_env(name, default=None):
    value = os.getenv(name)
    if value:
        value = value.strip().strip('"').strip("'")
    if not value or value.startswith("replace-") or value.startswith("your-"):
        return default
    return value


def first_env(*names):
    for name in names:
        value = optional_env(name)
        if value is not None:
            return value
    joined = " or ".join(names)
    raise RuntimeError(f"Set {joined} in .env before running this script.")


def wallet_dsn(wallet_dir):
    tnsnames = Path(wallet_dir) / "tnsnames.ora"
    if not tnsnames.exists():
        raise RuntimeError("Set ADB_DSN, DB_DSN, or provide a wallet with tnsnames.ora.")
    aliases = []
    for line in tnsnames.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if "=" in stripped and not stripped.startswith("#"):
            aliases.append(stripped.split("=", 1)[0].strip())
    for alias in aliases:
        if alias.endswith("_high"):
            return alias
    if aliases:
        return aliases[0]
    raise RuntimeError("No TNS aliases found in wallet tnsnames.ora.")


def connect():
    wallet_dir = first_env("ADB_WALLET_LOCATION", "DB_WALLET_DIR")
    dsn = (
        optional_env("ADB_DSN")
        or optional_env("DB_DSN")
        or wallet_dsn(wallet_dir)
    )
    connect_args = dict(
        user=first_env("ADB_USERNAME", "DB_USER"),
        password=first_env(
            "ADB_PASSWORD",
            "ADB_PASSOWRD",
            "DB_PASSWORD",
        ),
        dsn=dsn,
        config_dir=wallet_dir,
        wallet_location=wallet_dir,
    )
    wallet_password = (
        optional_env("ADB_WALLET_PASSPHRASE")
        or optional_env("ADB_WALLET_PASSWORD")
        or optional_env("DB_WALLET_PASSWORD")
    )
    if wallet_password:
        connect_args["wallet_password"] = wallet_password
    return oracledb.connect(**connect_args)


def direct_logon_connect(end_user):
    passwords = {
        "linda": required_env("DEEPSEC_LINDA_KEY"),
        "wendy": required_env("DEEPSEC_WENDY_KEY"),
    }
    if end_user not in passwords:
        raise ValueError(f"Unknown DEAL end user: {end_user}")

    wallet_dir = first_env("ADB_WALLET_LOCATION", "DB_WALLET_DIR")
    dsn = (
        optional_env("ADB_DSN")
        or optional_env("DB_DSN")
        or wallet_dsn(wallet_dir)
    )
    connect_args = dict(
        user=end_user.upper(),
        password=passwords[end_user],
        dsn=dsn,
        config_dir=wallet_dir,
        wallet_location=wallet_dir,
    )
    wallet_password = (
        optional_env("ADB_WALLET_PASSPHRASE")
        or optional_env("ADB_WALLET_PASSWORD")
        or optional_env("DB_WALLET_PASSWORD")
    )
    if wallet_password:
        connect_args["wallet_password"] = wallet_password
    return oracledb.connect(**connect_args)


def context_for(end_user):
    if end_user not in {"linda", "wendy"}:
        raise ValueError(f"Unknown DEAL end user: {end_user}")

    mode = optional_env("DEEPSEC_CONTEXT_MODE", "external_token")

    if mode == "local_tuple":
        identity = optional_env(f"DEEPSEC_{end_user.upper()}_IDENTITY", end_user.upper())
        key_name = f"DEEPSEC_{end_user.upper()}_KEY"
        identity = (identity, required_env(key_name))
    elif mode != "external_token":
        raise ValueError(
            "DEEPSEC_CONTEXT_MODE must be external_token or local_tuple."
        )
    else:
        identity = required_env(f"DEEPSEC_{end_user.upper()}_IDENTITY")

    return oracledb.create_end_user_security_context(
        end_user_identity=identity,
        database_access_token=required_env("DEEPSEC_DATABASE_ACCESS_TOKEN"),
    )


def run_for_user(end_user, work):
    if optional_env("DEEPSEC_CONTEXT_MODE", "direct_logon") == "direct_logon":
        with direct_logon_connect(end_user) as conn:
            return work(conn)

    with connect() as conn:
        context = context_for(end_user)
        try:
            conn.set_end_user_security_context(context)
            return work(conn)
        finally:
            conn.clear_end_user_security_context()


def object_name(name):
    owner = optional_env("DEAL_OBJECT_OWNER", "DEEPSEC_ADMIN")
    if optional_env("DEEPSEC_CONTEXT_MODE", "direct_logon") == "direct_logon":
        return f"{owner}.{name}"
    return name
