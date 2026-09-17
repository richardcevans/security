# Copyright (c) 2026, Oracle and/or its affiliates.
# Creates the wallet-based python-oracledb pool with Deep Sec token support.

from __future__ import annotations

import oracledb

from app_config import AppConfig


def _required_connection_values(cfg: AppConfig) -> dict[str, str]:
    values = {
        "DB_USER": cfg.DB_USER,
        "DB_PASSWORD": cfg.DB_PASSWORD,
        "DB_DSN": cfg.DB_DSN,
        "SSL_CONFIG_DIR": cfg.SSL_CONFIG_DIR,
        "WALLET_PASSWORD": cfg.WALLET_PASSWORD,
        "OCI_DOMAIN_URL": cfg.OCI_DOMAIN_URL,
        "DB_CLIENT_ID": cfg.DB_CLIENT_ID,
        "DB_CLIENT_SECRET": cfg.DB_CLIENT_SECRET,
        "DB_SCOPE": cfg.DB_SCOPE,
    }
    missing = [name for name, value in values.items() if not value]
    if missing:
        raise RuntimeError("Missing Oracle Database configuration: " + ", ".join(missing))
    return values


def create_connection_pool():
    """Create the OCI-token Deep Data Security pool used by Select AI."""
    cfg = AppConfig()
    values = _required_connection_values(cfg)
    return oracledb.create_pool(
        min=cfg.DB_POOL_MIN,
        max=cfg.DB_POOL_MAX,
        increment=cfg.DB_POOL_INCREMENT,
        user=values["DB_USER"],
        password=values["DB_PASSWORD"],
        dsn=values["DB_DSN"],
        ssl_server_dn_match=False,
        config_dir=values["SSL_CONFIG_DIR"],
        wallet_location=values["SSL_CONFIG_DIR"],
        wallet_password=values["WALLET_PASSWORD"],
        extra_auth_params={
            "end_user_sec_params": {
                "spi_type": "oci_tokens",
                "auth_flow": "client_credentials",
                "client_id": values["DB_CLIENT_ID"],
                "client_credential": values["DB_CLIENT_SECRET"],
                "authority": values["OCI_DOMAIN_URL"].rstrip("/") + "/oauth2/v1/token",
                "scopes": values["DB_SCOPE"],
            }
        },
    )
