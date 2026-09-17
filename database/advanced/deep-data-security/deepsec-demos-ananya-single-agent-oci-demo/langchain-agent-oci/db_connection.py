from __future__ import annotations

import os

import oracledb
from dotenv import load_dotenv

from app_config import AppConfig

load_dotenv()


def _env(name: str, default: str = "") -> str:
    value = os.getenv(name, default)
    return value.strip() if isinstance(value, str) else default


def _env_int(name: str, default: int) -> int:
    value = _env(name)
    if not value:
        return default
    try:
        return int(value)
    except ValueError as exc:
        raise RuntimeError(f"{name} must be an integer.") from exc


def _database_auth_values() -> dict[str, str]:
    cfg = AppConfig()
    auth_values = {
        "OCI_DOMAIN_URL": _env("HR_OCI_DOMAIN_URL", _env("OCI_DOMAIN_URL")),
        "DB_CLIENT_ID": _env("HR_MIDTIER_CLIENT_ID", _env("HR_DB_CLIENT_ID")),
        "DB_CLIENT_CREDENTIAL": _env(
            "HR_MIDTIER_CLIENT_SECRET",
            _env("HR_DB_CLIENT_SECRET"),
        ),
        "DB_SCOPES": _env("HR_DB_SCOPE"),
        "WALLET_PASSWORD": _env("WALLET_PWD", _env("WALLET_PASSWORD")),
        "DB_USER": cfg.DB_USER,
        "DB_PASSWORD": cfg.DB_PASSWORD,
        "DB_DSN": cfg.DB_DSN,
        "SSL_CONFIG_DIR": cfg.SSL_CONFIG_DIR,
    }

    required = [
        "OCI_DOMAIN_URL",
        "DB_CLIENT_ID",
        "DB_CLIENT_CREDENTIAL",
        "DB_SCOPES",
        "WALLET_PASSWORD",
        "DB_USER",
        "DB_PASSWORD",
        "DB_DSN",
        "SSL_CONFIG_DIR",
    ]
    missing = [key for key in required if not auth_values[key]]
    if missing:
        raise RuntimeError(
            "Missing HR OCI IAM configuration: {}".format(
                ", ".join(missing)
            )
        )

    return auth_values


def _connect_kwargs() -> dict:
    auth_values = _database_auth_values()
    return {
        "user": auth_values["DB_USER"],
        "password": auth_values["DB_PASSWORD"],
        "dsn": auth_values["DB_DSN"],
        "ssl_server_dn_match": False,
        "config_dir": auth_values["SSL_CONFIG_DIR"],
        "wallet_location": auth_values["SSL_CONFIG_DIR"],
        "wallet_password": auth_values["WALLET_PASSWORD"],
        "extra_auth_params": {
            "end_user_sec_params": {
                "spi_type": "oci_tokens",
                "auth_flow": "client_credentials",
                "client_id": auth_values["DB_CLIENT_ID"],
                "client_credential": auth_values["DB_CLIENT_CREDENTIAL"],
                "authority": (
                    auth_values["OCI_DOMAIN_URL"].rstrip("/")
                    + "/oauth2/v1/token"
                ),
                "scopes": auth_values["DB_SCOPES"],
            }
        },
    }


def create_connection_pool():
    """
    Create an Oracle Database connection pool for the LangChain tools.

    The pool is configured with application-mediated Deep Data Security
    parameters. The end-user identity is still set by langchain_app.py
    immediately before acquiring a connection from this pool.
    """
    return oracledb.create_pool(
        min=_env_int("DB_POOL_MIN", 1),
        max=_env_int("DB_POOL_MAX", 4),
        increment=_env_int("DB_POOL_INCREMENT", 1),
        **_connect_kwargs(),
    )


def get_connection():
    """
    Create an Oracle Database connection using application-mediated
    end-user security parameters.

    The end-user token is acquired by langchain_app.main() and registered
    with the Oracle end-user security provider before tools acquire
    connections through this factory.
    """
    return oracledb.connect(**_connect_kwargs())
