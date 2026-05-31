import os
import sys
from pathlib import Path

import oracledb
from dotenv import load_dotenv


load_dotenv()


def required_env(name):
    value = os.getenv(name)
    if (
        not value
        or value.startswith("replace-")
        or value.startswith("your-")
        or value.startswith("/path/to/")
    ):
        raise RuntimeError(f"Set {name} in .env before running this script.")
    return value


def first_env(*names):
    for name in names:
        value = os.getenv(name)
        if value and not value.startswith("replace-") and not value.startswith("your-"):
            return value
    joined = " or ".join(names)
    raise RuntimeError(f"Set {joined} in .env before running this script.")


def optional_env(*names):
    for name in names:
        value = os.getenv(name)
        if value and not value.startswith("replace-") and not value.startswith("your-"):
            return value
    return None


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
    dsn = optional_env("ADB_DSN", "DB_DSN") or wallet_dsn(wallet_dir)
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
    wallet_password = optional_env(
        "ADB_WALLET_PASSPHRASE",
        "ADB_WALLET_PASSWORD",
        "DB_WALLET_PASSWORD",
    )
    if wallet_password:
        connect_args["wallet_password"] = wallet_password
    return oracledb.connect(**connect_args)


print("DEAL environment check")

with connect() as conn:
    cur = conn.cursor()

    cur.execute("select sys_context('USERENV', 'CURRENT_SCHEMA') from dual")
    print(f"Connected as: {cur.fetchone()[0]}")

    try:
        cur.execute("select banner_full from v$version where rownum = 1")
        version_text = cur.fetchone()[0]
    except oracledb.DatabaseError:
        cur.execute(
            """
            select version_full
            from product_component_version
            where product like 'Oracle Database%'
            fetch first 1 row only
            """
        )
        version_text = cur.fetchone()[0]

    print(f"Database version: {version_text}")

    mode = "Thin" if oracledb.is_thin_mode() else "Thick"
    print(f"python-oracledb mode: {mode}")

    if mode != "Thin":
        print("Deep Data Security requires python-oracledb Thin mode for this demo.")
        sys.exit(1)

    cur.execute(
        """
        select view_name
        from all_views
        where view_name in (
            'DBA_DATA_ROLES',
            'DBA_DATA_ROLE_GRANTS',
            'DBA_DATA_GRANTS',
            'ALL_DATA_GRANTS',
            'USER_DATA_GRANTS'
        )
        order by view_name
        """
    )
    visible_views = [row[0] for row in cur.fetchall()]

    if visible_views:
        print("Deep Sec metadata visible to this schema: " + ", ".join(visible_views))
    else:
        print("Deep Sec metadata views are not visible to this schema.")
        print("Continue only with an administrator-prepared Deep Sec environment.")
