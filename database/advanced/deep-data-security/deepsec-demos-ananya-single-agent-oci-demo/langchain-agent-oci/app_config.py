# Copyright (c) 2026, Oracle and/or its affiliates.
# High-level configuration for the LangChain Agent sample application.
# Reads OCI Generative AI and Oracle Database settings from environment
# variables and exposes them through a frozen dataclass.

from dataclasses import dataclass
import os

from dotenv import load_dotenv

load_dotenv()


@dataclass(frozen=True)
class AppConfig:
    # OCI Generative AI configuration.
    oci_config_file: str = os.getenv("OCI_CONFIG_FILE", "~/.oci/config")
    oci_profile: str = os.getenv("OCI_PROFILE", "DEFAULT")
    oci_auth_type: str = os.getenv("OCI_AUTH_TYPE", os.getenv("OCI_CLI_AUTH", "API_KEY")).upper()
    oci_genai_service_endpoint: str = os.getenv("OCI_GENAI_SERVICE_ENDPOINT", "")
    COMPARTMENT_ID: str = os.getenv("COMPARTMENT_ID", "")
    model_id: str = os.getenv("MODEL_ID", "")
    model_provider: str = os.getenv("MODEL_PROVIDER", "")
    max_tokens: int = int(os.getenv("MAX_TOKENS", "4096"))

    # Oracle Database connection settings.
    DB_USER: str = os.getenv("DB_USER", "")
    DB_PASSWORD: str = os.getenv("DB_PASSWORD", "")
    DB_DSN: str = os.getenv("DB_DSN", "")
    SSL_CONFIG_DIR: str = os.getenv("SSL_CONFIG_DIR", "")

    # HR OCI IAM application settings.
    HR_OCI_DOMAIN_URL: str = os.getenv("HR_OCI_DOMAIN_URL", "")
    HR_DB_APP_ID: str = os.getenv("HR_DB_APP_ID", "")
    HR_DB_CLIENT_ID: str = os.getenv("HR_DB_CLIENT_ID", "")
    HR_DB_CLIENT_SECRET: str = os.getenv("HR_DB_CLIENT_SECRET", "")
    HR_DB_SCOPE: str = os.getenv("HR_DB_SCOPE", "")
    HR_MIDTIER_APP_ID: str = os.getenv("HR_MIDTIER_APP_ID", "")
    HR_MIDTIER_CLIENT_ID: str = os.getenv("HR_MIDTIER_CLIENT_ID", "")
    HR_MIDTIER_CLIENT_SECRET: str = os.getenv("HR_MIDTIER_CLIENT_SECRET", "")
    HR_MIDTIER_SCOPE: str = os.getenv("HR_MIDTIER_SCOPE", "")
    HR_LOGIN_APP_ID: str = os.getenv("HR_LOGIN_APP_ID", "")
    HR_LOGIN_CLIENT_ID: str = os.getenv("HR_LOGIN_CLIENT_ID", "")
    HR_LOGIN_CLIENT_SECRET: str = os.getenv("HR_LOGIN_CLIENT_SECRET", "")
    HR_APP_CLIENT_ID: str = os.getenv("HR_APP_CLIENT_ID", "")
    HR_APP_CLIENT_SECRET: str = os.getenv("HR_APP_CLIENT_SECRET", "")
    HR_APP_SCOPE: str = os.getenv("HR_APP_SCOPE", "")
    HR_REDIRECT_URI: str = os.getenv("HR_REDIRECT_URI", "http://localhost:8888/callback")
