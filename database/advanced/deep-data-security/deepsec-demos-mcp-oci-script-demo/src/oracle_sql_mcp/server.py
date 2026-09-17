# Copyright (c) 2026, Oracle and/or its affiliates.
# Defines and runs the Oracle SQL MCP server and its read-only schema/query tools.
# Depends on FastMCP HTTP authorization, python-oracledb database access, and SQL guards.

"""MCP tools for OCI IAM-authenticated Oracle SQL inspection and queries."""

from __future__ import annotations

import argparse
import sys
from typing import Any

from mcp.server.auth.middleware.auth_context import get_access_token
from mcp.server.auth.settings import AuthSettings
from mcp.server.fastmcp import FastMCP

from .config import Settings
from .database import Database, rows_as_dicts
from .sql import bounded_limit, clean_read_only_sql
from .token_verifier import OciIamTokenVerifier

_settings = Settings()


def _create_mcp() -> FastMCP:
    """Create the required bearer-token-protected Streamable HTTP server."""
    _settings.require_http_auth()
    return FastMCP(
        "Oracle SQL",
        instructions=(
            "Use describe_table before ad-hoc queries when column names are uncertain. "
            "execute_sql is intentionally read-only; Oracle Deep Data Security remains the "
            "authoritative row and column access control layer."
        ),
        json_response=True,
        token_verifier=OciIamTokenVerifier(_settings),
        auth=AuthSettings(
            issuer_url=_settings.mcp_authorization_server_url,
            resource_server_url=_settings.mcp_resource_server_url,
            required_scopes=list(_settings.mcp_required_scopes),
        ),
    )


mcp = _create_mcp()
_database: Database | None = None


def _db() -> Database:
    if _database is None:
        raise RuntimeError("Server database pool has not started.")
    return _database


def _end_user_token() -> str:
    """Return the bearer token validated for the current HTTP request."""
    access_token = get_access_token()
    if access_token is not None:
        return access_token.token
    raise RuntimeError("No validated bearer token is available for this HTTP request.")


def _schema_owner(owner: str | None) -> str:
    selected = (owner or _db().default_schema).strip()
    if not selected:
        raise ValueError("owner is required when DEFAULT_SCHEMA is not configured.")
    return selected


@mcp.tool()
def get_current_user() -> dict[str, str]:
    """Return the OCI IAM end-user identity visible to the Oracle database session."""
    with _db().connection(_end_user_token()) as connection, connection.cursor() as cursor:
        cursor.execute("SELECT ORA_END_USER_CONTEXT.username AS username FROM sys.dual")
        row = cursor.fetchone()
    return {"username": str(row[0]) if row and row[0] else "unknown"}


@mcp.tool()
def list_tables(owner: str | None = None, limit: int = 200) -> list[dict[str, str]]:
    """List visible tables for an Oracle schema owner, or use configured DEFAULT_SCHEMA."""
    owner = _schema_owner(owner)
    with _db().connection(_end_user_token()) as connection, connection.cursor() as cursor:
        cursor.execute(
            """SELECT owner, table_name FROM all_tables WHERE owner = UPPER(:owner)
               ORDER BY table_name FETCH FIRST :limit ROWS ONLY""",
            owner=owner.strip(), limit=bounded_limit(limit),
        )
        return rows_as_dicts(cursor, cursor.fetchall())


@mcp.tool()
def describe_table(table_name: str, owner: str | None = None) -> list[dict[str, Any]]:
    """Describe visible table columns for an owner, or use configured DEFAULT_SCHEMA."""
    if not table_name.strip():
        raise ValueError("table_name is required.")
    owner = _schema_owner(owner)
    with _db().connection(_end_user_token()) as connection, connection.cursor() as cursor:
        cursor.execute(
            """SELECT column_name, data_type, data_length, data_precision, data_scale, nullable
               FROM all_tab_columns WHERE owner = UPPER(:owner) AND table_name = UPPER(:table_name)
               ORDER BY column_id""",
            owner=owner.strip(), table_name=table_name.strip(),
        )
        return rows_as_dicts(cursor, cursor.fetchall())


@mcp.tool()
def execute_sql(sql: str, max_rows: int = 100) -> dict[str, Any]:
    """Run one read-only Oracle SQL statement; results are capped at max_rows (up to 500)."""
    statement = clean_read_only_sql(sql)
    max_rows = bounded_limit(max_rows)
    with _db().connection(_end_user_token()) as connection, connection.cursor() as cursor:
        cursor.execute(statement)
        if not cursor.description:
            return {"columns": [], "rows": [], "row_count": 0, "truncated": False}
        rows = cursor.fetchmany(max_rows + 1)
        truncated = len(rows) > max_rows
        rows = rows[:max_rows]
        return {
            "columns": [column[0] for column in cursor.description],
            "rows": rows_as_dicts(cursor, rows),
            "row_count": len(rows),
            "truncated": truncated,
        }


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="OCI IAM Oracle SQL Streamable HTTP MCP server")
    parser.add_argument("--host", default="127.0.0.1", help="HTTP bind host (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=8000, help="HTTP bind port (default: 8000)")
    parser.add_argument(
        "--allow-remote-http",
        action="store_true",
        help="Acknowledge responsibility for TLS, network controls, and public MCP resource-server URLs.",
    )
    return parser.parse_args()


def _is_loopback_host(host: str) -> bool:
    return host.strip().lower() in {"localhost", "127.0.0.1", "::1"}


def main() -> None:
    global _database
    args = _parse_args()
    if not _is_loopback_host(args.host):
        if not args.allow_remote_http:
            raise RuntimeError(
                "Refusing non-loopback HTTP binding without --allow-remote-http. "
                "Configure HTTPS and a public MCP_RESOURCE_SERVER_URL before remote use."
            )
        print(
            "WARNING: remote HTTP requires TLS, trusted network controls, and a public "
            "MCP_RESOURCE_SERVER_URL that matches the client-facing endpoint.",
            file=sys.stderr,
        )
    _database = Database(_settings)
    try:
        mcp.settings.host = args.host
        mcp.settings.port = args.port
        print(
            f"Oracle SQL MCP listening at http://{args.host}:{args.port}/mcp "
            "(bearer token required for every HTTP request).",
            file=sys.stderr,
        )
        mcp.run(transport="streamable-http")
    finally:
        _database.close()


if __name__ == "__main__":
    main()
