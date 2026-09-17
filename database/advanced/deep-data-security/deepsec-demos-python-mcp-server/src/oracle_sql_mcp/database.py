# Copyright (c) 2026, Oracle and/or its affiliates.
# Creates Oracle Database pools and propagates the OCI IAM end-user identity.
# Depends on python-oracledb and its end_user_sec_provider Deep Data Security plugin.

"""Oracle pool and results helpers for Deep Data Security sessions."""

from __future__ import annotations

from contextlib import contextmanager
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Iterator

import oracledb
import oracledb.plugins.end_user_sec_provider as deepsec_provider

from .config import Settings


class Database:
    def __init__(self, settings: Settings) -> None:
        settings.require_database()
        self._default_schema = settings.default_schema
        self._pool = oracledb.create_pool(
            min=settings.pool_min,
            max=settings.pool_max,
            increment=settings.pool_increment,
            user=settings.db_user,
            password=settings.db_password,
            dsn=settings.db_dsn,
            ssl_server_dn_match=False,
            config_dir=settings.ssl_config_dir,
            wallet_location=settings.ssl_config_dir,
            wallet_password=settings.wallet_password,
            extra_auth_params={"end_user_sec_params": {
                "spi_type": "oci_tokens", "auth_flow": "client_credentials",
                "client_id": settings.db_client_id,
                "client_credential": settings.db_client_secret,
                "authority": settings.oci_domain_url.rstrip("/") + "/oauth2/v1/token",
                "scopes": settings.db_scope,
            }},
        )

    @contextmanager
    def connection(self, end_user_token: str) -> Iterator[Any]:
        deepsec_provider.set_end_user_identity(end_user_token)
        with self._pool.acquire() as connection:
            yield connection

    def close(self) -> None:
        self._pool.close()

    @property
    def default_schema(self) -> str:
        return self._default_schema


def json_value(value: Any) -> Any:
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return str(value)
    if isinstance(value, bytes):
        return value.hex()
    return value


def rows_as_dicts(cursor: Any, rows: list[tuple[Any, ...]]) -> list[dict[str, Any]]:
    columns = [column[0] for column in cursor.description]
    return [dict(zip(columns, (json_value(value) for value in row), strict=True)) for row in rows]
