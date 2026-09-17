# Copyright (c) 2026, Oracle and/or its affiliates.
# High-level configuration for the LangChain Agent sample application.
# Reads OCI Generative AI, Oracle Database, and Entra ID settings from
# environment variables and exposes them through a frozen dataclass.
#
# Dependencies:
# - python-dotenv for loading environment variables from .env file
# - OCI Generative AI Service configuration and model OCIDs
# - Oracle Database connection settings
# - Microsoft Entra ID / MSAL-related application settings

from dataclasses import dataclass
import os

from dotenv import load_dotenv

load_dotenv()

# Optional legacy model-name mapping. New deployments should set MODEL_ID in
# the ignored .env file instead of editing this module.

MODEL_IDS = {
    # Keep this mapping available for existing deployments that select a
    # friendly model name in source. New deployments should set MODEL_ID in
    # the ignored .env file instead of editing this module.
}

@dataclass(frozen=True)
class AppConfig:
    # OCI Generative AI configuration.
    oci_config_file: str = os.getenv("OCI_CONFIG_FILE", "~/.oci/config")
    oci_profile: str = os.getenv("OCI_PROFILE", "DEFAULT")
    oci_auth_type: str = os.getenv("OCI_AUTH_TYPE", "API_KEY").upper()
    oci_genai_service_endpoint: str = os.getenv(
        "OCI_GENAI_SERVICE_ENDPOINT",
        "https://inference.generativeai.us-ashburn-1.oci.oraclecloud.com",
    )
    COMPARTMENT_ID: str = os.getenv(
        "COMPARTMENT_ID",
        "",
    )
    model_choice: str = os.getenv("MODEL_CHOICE", "")
    model_id: str = os.getenv("MODEL_ID", "")
    max_tokens: int = int(os.getenv("MAX_TOKENS", "4096"))

    # Oracle Database connection settings.
    DB_USER: str = os.getenv("DB_USER", "")
    DB_PASSWORD: str = os.getenv("DB_PASSWORD", "")
    DB_DSN: str = os.getenv("DB_DSN", "")
    SSL_CONFIG_DIR: str = os.getenv("SSL_CONFIG_DIR", "")

    # HR Entra application settings.
    DB_CLIENT_ID: str = os.getenv("DB_CLIENT_ID", "")
    DB_CLIENT_CREDENTIAL: str = os.getenv("DB_CLIENT_CREDENTIAL", "")
    DB_AUTHORITY: str = os.getenv("DB_AUTHORITY", "")
    DB_SCOPES: str = os.getenv("DB_SCOPES", "")

    # Salary-agent Entra application settings.
    COMP_DB_CLIENT_ID: str = os.getenv("COMP_DB_CLIENT_ID", "")
    COMP_DB_CLIENT_CREDENTIAL: str = os.getenv("COMP_DB_CLIENT_CREDENTIAL", "")
    COMP_DB_AUTHORITY: str = os.getenv("COMP_DB_AUTHORITY", "")
    COMP_DB_SCOPES: str = os.getenv("COMP_DB_SCOPES", "")

    # End-user interactive login settings for the shared MSAL client app.
    AZURE_CLIENT_ID: str = os.getenv("AZURE_CLIENT_ID", "")
    AZURE_TENANT_ID: str = os.getenv("AZURE_TENANT_ID", "")

    # End-user scopes for each agent mode.
    AZURE_SCOPES: str = os.getenv("AZURE_SCOPES", "")
    COMP_AZURE_SCOPES: str = os.getenv("COMP_AZURE_SCOPES", "")
