# Copyright (c) 2026, Oracle and/or its affiliates.
# Creates pooled Oracle Autonomous AI Database connections for the LangChain
# Agent sample and configures OCI IAM end-user identity propagation through
# Oracle Deep Data Security.
#
# Dependencies:
# - python-oracledb
# - Oracle Deep Data Security end-user security provider
# - python-dotenv
# - app_config.py

from __future__ import annotations

import os

import oracledb
from dotenv import load_dotenv

from app_config import AppConfig

load_dotenv()


def _mode_prefix(agent_mode: str) -> str:
    return "COMP" if agent_mode.lower() == "compensation" else "HR"


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


def _database_auth_values(agent_mode: str) -> dict[str, str]:
    """Return the database-access-token settings for one agent mode."""
    cfg = AppConfig()
    prefix = _mode_prefix(agent_mode)
    values = {
        "OCI_DOMAIN_URL": _env(f"{prefix}_OCI_DOMAIN_URL", _env("OCI_DOMAIN_URL")),
        "DB_CLIENT_ID": _env(f"{prefix}_DB_CLIENT_ID"),
        "DB_CLIENT_CREDENTIAL": _env(f"{prefix}_DB_CLIENT_SECRET"),
        "DB_SCOPES": _env(f"{prefix}_DB_SCOPE"),
        "WALLET_PASSWORD": _env("WALLET_PWD", _env("WALLET_PASSWORD")),
        "DB_USER": cfg.DB_USER,
        "DB_PASSWORD": cfg.DB_PASSWORD,
        "DB_DSN": cfg.DB_DSN,
        "SSL_CONFIG_DIR": cfg.SSL_CONFIG_DIR,
    }
    missing = [name for name, value in values.items() if not value]
    if missing:
        raise RuntimeError(
            "Missing Oracle Database configuration for {} mode: {}".format(
                agent_mode, ", ".join(missing)
            )
        )
    return values


def _connect_kwargs(agent_mode: str) -> dict:
    """Build python-oracledb pool settings for Deep Data Security."""
    values = _database_auth_values(agent_mode)
    return {
        "user": values["DB_USER"],
        "password": values["DB_PASSWORD"],
        "dsn": values["DB_DSN"],
        "ssl_server_dn_match": False,
        "config_dir": values["SSL_CONFIG_DIR"],
        "wallet_location": values["SSL_CONFIG_DIR"],
        "wallet_password": values["WALLET_PASSWORD"],
        "extra_auth_params": {
            "end_user_sec_params": {
                "spi_type": "oci_tokens",
                "auth_flow": "client_credentials",
                "client_id": values["DB_CLIENT_ID"],
                "client_credential": values["DB_CLIENT_CREDENTIAL"],
                "authority": values["OCI_DOMAIN_URL"].rstrip("/") + "/oauth2/v1/token",
                "scopes": values["DB_SCOPES"],
            }
        },
    }


def create_connection_pool(agent_mode: str = "hr"):
    """
    Create a pool whose acquired connections attach the current end-user identity.

    langchain_app.py sets that identity immediately before each acquisition.
    """
    return oracledb.create_pool(
        min=_env_int("DB_POOL_MIN", 1),
        max=_env_int("DB_POOL_MAX", 4),
        increment=_env_int("DB_POOL_INCREMENT", 1),
        **_connect_kwargs(agent_mode),
    )
