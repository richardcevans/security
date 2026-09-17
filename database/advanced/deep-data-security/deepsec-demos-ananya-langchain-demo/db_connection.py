# Copyright (c) 2026, Oracle and/or its affiliates.
# Creates an Oracle Database connection pool for the LangChain Agent sample
# application and configures end-user identity propagation using Oracle Deep
# Data Security.
#
# Dependencies:
# - python-oracledb
# - Oracle Deep Data Security end-user security provider
# - python-dotenv
# - app_config.py
# - get_user_token.py

from __future__ import annotations

import os
import ssl

import oracledb
import oracledb.plugins.end_user_sec_provider as deepsec_provider
from dotenv import load_dotenv

from app_config import AppConfig
from get_user_token import get_access_token

load_dotenv()

# SSL context used for Oracle Database connectivity.

ssl_ctx = ssl.create_default_context()
ssl_ctx.check_hostname = False
ssl_ctx.verify_mode = ssl.CERT_NONE


def _auth_settings_for_mode(cfg: AppConfig, agent_mode: str) -> dict[str, str]:
    """
    Return the authentication settings associated with the selected
    agent mode.
    """
    if agent_mode == "compensation":
        return {
            "DB_CLIENT_ID": cfg.COMP_DB_CLIENT_ID,
            "DB_CLIENT_CREDENTIAL": cfg.COMP_DB_CLIENT_CREDENTIAL,
            "DB_AUTHORITY": cfg.COMP_DB_AUTHORITY,
            "DB_SCOPES": cfg.COMP_DB_SCOPES,
            "END_USER_SCOPE": cfg.COMP_AZURE_SCOPES,
    }

    return {
        "DB_CLIENT_ID": cfg.DB_CLIENT_ID,
        "DB_CLIENT_CREDENTIAL": cfg.DB_CLIENT_CREDENTIAL,
        "DB_AUTHORITY": cfg.DB_AUTHORITY,
        "DB_SCOPES": cfg.DB_SCOPES,
        "END_USER_SCOPE": cfg.AZURE_SCOPES,
    }


def _env_int(name: str, default: int) -> int:
    value = os.getenv(name, "").strip()
    if not value:
        return default
    try:
        return int(value)
    except ValueError as exc:
        raise RuntimeError(f"{name} must be an integer.") from exc


def get_end_user_identity(agent_mode: str = "hr") -> str:
    """
    Authenticate the current user and register the identity with the
    Deep Data Security provider.
    """
    cfg = AppConfig()
    auth_values = _auth_settings_for_mode(cfg, agent_mode)
    end_user_token = get_access_token(scope=auth_values["END_USER_SCOPE"])
    deepsec_provider.set_end_user_identity(end_user_token)
    return end_user_token


def _connect_kwargs(agent_mode: str) -> dict:
    """Build the Azure Deep Data Security settings for the connection pool."""
    cfg = AppConfig()
    auth_values = _auth_settings_for_mode(cfg, agent_mode)
    return {
        "user": cfg.DB_USER,
        "password": cfg.DB_PASSWORD,
        "dsn": cfg.DB_DSN,
        "ssl_context": ssl_ctx,
        "ssl_server_dn_match": True,
        "ssl_server_cert_dn": "CN=server",
        "config_dir": cfg.SSL_CONFIG_DIR,
        "extra_auth_params": {
            "end_user_sec_params": {
                "spi_type": "azure_tokens",
                "auth_flow": "on_behalf_of",
                "client_id": auth_values["DB_CLIENT_ID"],
                "client_credential": auth_values["DB_CLIENT_CREDENTIAL"],
                "authority": auth_values["DB_AUTHORITY"],
                "scopes": auth_values["DB_SCOPES"],
            }
        },
    }


def create_connection_pool(agent_mode: str = "hr"):
    """
    Create an Oracle Database connection pool for the requested agent mode.

    The caller must set the end-user identity immediately before each
    acquisition, as langchain_app.py does through its connection factory.
    """
    return oracledb.create_pool(
        min=_env_int("DB_POOL_MIN", 1),
        max=_env_int("DB_POOL_MAX", 4),
        increment=_env_int("DB_POOL_INCREMENT", 1),
        **_connect_kwargs(agent_mode),
    )
