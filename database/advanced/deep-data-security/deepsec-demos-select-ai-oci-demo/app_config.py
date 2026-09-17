# Copyright (c) 2026, Oracle and/or its affiliates.
# Loads and validates environment-backed configuration for the CLI.

from __future__ import annotations

from dataclasses import dataclass
import os

from dotenv import load_dotenv

load_dotenv()


@dataclass(frozen=True)
class AppConfig:
    """Environment-backed settings for the Select AI HR assistant."""

    # Oracle Database connectivity.
    DB_USER: str = os.getenv("DB_USER", "")
    DB_PASSWORD: str = os.getenv("DB_PASSWORD", "")
    DB_DSN: str = os.getenv("DB_DSN", "")
    SSL_CONFIG_DIR: str = os.getenv("SSL_CONFIG_DIR", "")
    WALLET_PASSWORD: str = os.getenv("WALLET_PWD", os.getenv("WALLET_PASSWORD", ""))

    # OCI IAM browser-login application. The obtained user token is propagated
    # to Deep Data Security for every database session.
    OCI_DOMAIN_URL: str = os.getenv("OCI_DOMAIN_URL", "")
    APP_CLIENT_ID: str = os.getenv("APP_CLIENT_ID", "")
    APP_CLIENT_SECRET: str = os.getenv("APP_CLIENT_SECRET", "")
    APP_SCOPE: str = os.getenv("APP_SCOPE", "")
    REDIRECT_URI: str = os.getenv("REDIRECT_URI", "http://localhost:8888/callback")

    # OCI IAM database-access client. It obtains the database token used with
    # the authenticated end-user token.
    DB_CLIENT_ID: str = os.getenv("DB_CLIENT_ID", "")
    DB_CLIENT_SECRET: str = os.getenv("DB_CLIENT_SECRET", "")
    DB_SCOPE: str = os.getenv("DB_SCOPE", "")

    # Optional pool sizing.
    DB_POOL_MIN: int = int(os.getenv("DB_POOL_MIN", "1"))
    DB_POOL_MAX: int = int(os.getenv("DB_POOL_MAX", "4"))
    DB_POOL_INCREMENT: int = int(os.getenv("DB_POOL_INCREMENT", "1"))

    # Select AI profile and team shared with Deep Sec data roles.
    SELECT_AI_PROFILE_OWNER: str = os.getenv("SELECT_AI_PROFILE_OWNER") or os.getenv("DB_USER", "")
    SELECT_AI_PROFILE_NAME: str = os.getenv("SELECT_AI_PROFILE_NAME", "HR_PROFILE")
    SELECT_AI_TEAM_OWNER: str = (
        os.getenv("SELECT_AI_TEAM_OWNER")
        or os.getenv("SELECT_AI_PROFILE_OWNER")
        or os.getenv("DB_USER", "")
    )
    SELECT_AI_TEAM_NAME: str = os.getenv("SELECT_AI_TEAM_NAME", "HR_TEAM")
