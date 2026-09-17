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
    oci_config_file: str = os.getenv("OCI_CONFIG_FILE", "")
    oci_profile: str = os.getenv("OCI_PROFILE", "DEFAULT")
    COMPARTMENT_ID: str = os.getenv("COMPARTMENT_ID", "")
    model_id: str = os.getenv("MODEL_ID", "")
    oci_genai_endpoint: str = os.getenv("OCI_GENAI_ENDPOINT", "")
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
    HR_APP_CLIENT_ID: str = os.getenv("HR_APP_CLIENT_ID", "")
    HR_APP_CLIENT_SECRET: str = os.getenv("HR_APP_CLIENT_SECRET", "")
    HR_APP_SCOPE: str = os.getenv("HR_APP_SCOPE", "")
    HR_REDIRECT_URI: str = os.getenv("HR_REDIRECT_URI", "http://localhost:8888/callback")

    # Salary / compensation OCI IAM application settings.
    COMP_OCI_DOMAIN_URL: str = os.getenv("COMP_OCI_DOMAIN_URL", "")
    COMP_DB_APP_ID: str = os.getenv("COMP_DB_APP_ID", "")
    COMP_DB_CLIENT_ID: str = os.getenv("COMP_DB_CLIENT_ID", "")
    COMP_DB_CLIENT_SECRET: str = os.getenv("COMP_DB_CLIENT_SECRET", "")
    COMP_DB_SCOPE: str = os.getenv("COMP_DB_SCOPE", "")
    COMP_APP_CLIENT_ID: str = os.getenv("COMP_APP_CLIENT_ID", "")
    COMP_APP_CLIENT_SECRET: str = os.getenv("COMP_APP_CLIENT_SECRET", "")
    COMP_APP_SCOPE: str = os.getenv("COMP_APP_SCOPE", "")
    COMP_REDIRECT_URI: str = os.getenv("COMP_REDIRECT_URI", "http://localhost:8889/callback")
