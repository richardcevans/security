# Copyright (c) 2026, Oracle and/or its affiliates.
# Defines immutable environment-backed settings for database, OCI IAM, and GenAI use.
# Depends on dataclasses, os, and python-dotenv for loading `.env` configuration.

"""Environment-backed runtime settings."""

from __future__ import annotations

import os
from dataclasses import dataclass

from dotenv import load_dotenv

load_dotenv()


def _value(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


def _integer(name: str, default: int) -> int:
    raw = _value(name)
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError as exc:
        raise RuntimeError(f"{name} must be an integer.") from exc


@dataclass(frozen=True)
class Settings:
    db_user: str = _value("DB_USER")
    db_password: str = _value("DB_PASSWORD")
    db_dsn: str = _value("DB_DSN")
    default_schema: str = _value("DEFAULT_SCHEMA")
    ssl_config_dir: str = _value("SSL_CONFIG_DIR")
    wallet_password: str = _value("WALLET_PWD", _value("WALLET_PASSWORD"))
    oci_domain_url: str = _value("OCI_DOMAIN_URL")
    db_client_id: str = _value("DB_CLIENT_ID")
    db_client_secret: str = _value("DB_CLIENT_SECRET")
    db_scope: str = _value("DB_SCOPE")
    app_client_id: str = _value("APP_CLIENT_ID")
    app_client_secret: str = _value("APP_CLIENT_SECRET")
    app_scope: str = _value("APP_SCOPE")
    redirect_uri: str = _value("REDIRECT_URI", "http://localhost:8888/callback")
    mcp_resource_server_url: str = _value("MCP_RESOURCE_SERVER_URL")
    mcp_authorization_server_url: str = _value(
        "MCP_AUTHORIZATION_SERVER_URL", _value("OCI_DOMAIN_URL")
    )
    mcp_token_issuer: str = _value("MCP_TOKEN_ISSUER")
    mcp_auth_audience: str = _value("MCP_AUTH_AUDIENCE")
    mcp_introspection_url: str = _value(
        "MCP_INTROSPECTION_URL",
        _value("OCI_DOMAIN_URL").rstrip("/") + "/oauth2/v1/introspect"
        if _value("OCI_DOMAIN_URL")
        else "",
    )
    mcp_introspection_client_id: str = _value(
        "MCP_INTROSPECTION_CLIENT_ID", _value("DB_CLIENT_ID")
    )
    mcp_introspection_client_secret: str = _value(
        "MCP_INTROSPECTION_CLIENT_SECRET", _value("DB_CLIENT_SECRET")
    )
    mcp_required_scopes: tuple[str, ...] = tuple(_value("MCP_REQUIRED_SCOPES").split())
    pool_min: int = _integer("DB_POOL_MIN", 1)
    pool_max: int = _integer("DB_POOL_MAX", 4)
    pool_increment: int = _integer("DB_POOL_INCREMENT", 1)

    def require_database(self) -> None:
        required = {
            "DB_USER": self.db_user,
            "DB_PASSWORD": self.db_password,
            "DB_DSN": self.db_dsn,
            "SSL_CONFIG_DIR": self.ssl_config_dir,
            "WALLET_PWD": self.wallet_password,
            "OCI_DOMAIN_URL": self.oci_domain_url,
            "DB_CLIENT_ID": self.db_client_id,
            "DB_CLIENT_SECRET": self.db_client_secret,
            "DB_SCOPE": self.db_scope,
        }
        missing = [name for name, value in required.items() if not value]
        if missing:
            raise RuntimeError("Missing database configuration: " + ", ".join(missing))

    def require_login(self) -> None:
        required = {
            "OCI_DOMAIN_URL": self.oci_domain_url,
            "APP_CLIENT_ID": self.app_client_id,
            "APP_CLIENT_SECRET": self.app_client_secret,
            "APP_SCOPE": self.app_scope,
            "REDIRECT_URI": self.redirect_uri,
        }
        missing = [name for name, value in required.items() if not value]
        if missing:
            raise RuntimeError("Missing OCI IAM login configuration: " + ", ".join(missing))

    def require_http_auth(self) -> None:
        required = {
            "MCP_RESOURCE_SERVER_URL": self.mcp_resource_server_url,
            "MCP_AUTHORIZATION_SERVER_URL": self.mcp_authorization_server_url,
            "MCP_TOKEN_ISSUER": self.mcp_token_issuer,
            "MCP_AUTH_AUDIENCE": self.mcp_auth_audience,
            "MCP_INTROSPECTION_URL": self.mcp_introspection_url,
            "MCP_INTROSPECTION_CLIENT_ID": self.mcp_introspection_client_id,
            "MCP_INTROSPECTION_CLIENT_SECRET": self.mcp_introspection_client_secret,
            "MCP_REQUIRED_SCOPES": " ".join(self.mcp_required_scopes),
        }
        missing = [name for name, value in required.items() if not value]
        if missing:
            raise RuntimeError("Missing Streamable HTTP authorization configuration: " + ", ".join(missing))


@dataclass(frozen=True)
class GenAISettings:
    """OCI Generative AI settings for the MCP CLI client."""

    oci_config_file: str = _value("OCI_CONFIG_FILE")
    oci_profile: str = _value("OCI_PROFILE", "DEFAULT")
    compartment_id: str = _value("COMPARTMENT_ID")
    model_id: str = _value("MODEL_ID")
    endpoint: str = _value("OCI_GENAI_ENDPOINT")
    auth_type: str = _value("GENAI_AUTH_TYPE", "auto").lower()
    max_tokens: int = _integer("MAX_TOKENS", 4096)
    max_tool_calls_per_turn: int = _integer("MAX_TOOL_CALLS_PER_TURN", 8)

    def require(self) -> None:
        required = {
            "OCI_CONFIG_FILE": self.oci_config_file,
            "COMPARTMENT_ID": self.compartment_id,
            "MODEL_ID": self.model_id,
            "OCI_GENAI_ENDPOINT": self.endpoint,
        }
        missing = [name for name, value in required.items() if not value]
        if missing:
            raise RuntimeError("Missing OCI Generative AI configuration: " + ", ".join(missing))
        if self.auth_type not in {"auto", "api_key", "security_token"}:
            raise RuntimeError(
                "GENAI_AUTH_TYPE must be auto, api_key, or security_token."
            )
