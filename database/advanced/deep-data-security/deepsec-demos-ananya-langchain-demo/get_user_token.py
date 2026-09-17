# Copyright (c) 2026, Oracle and/or its affiliates.
# Authenticates an end user with Microsoft Entra ID and returns an
# access token for the requested scope. Used to obtain tokens for
# Oracle Deep Data Security end-user identity propagation.
#
# Dependencies:
# - MSAL (Microsoft Authentication Library)
# - python-dotenv
# - AZURE_CLIENT_ID and AZURE_TENANT_ID environment variables

from __future__ import annotations

import os

import msal
from dotenv import load_dotenv

load_dotenv()


def get_access_token(scope: str) -> str:
    """
    Authenticate the current user and return an access token for the
    requested scope.
    """
    client_id = os.getenv("AZURE_CLIENT_ID")
    tenant_id = os.getenv("AZURE_TENANT_ID")

    # Validate the required authentication configuration.
    if not client_id or not tenant_id or not scope:
        raise RuntimeError(
            f"Missing MSAL config: client_id={client_id!r}, "
            f"tenant_id={tenant_id!r}, scope={scope!r}"
        )

    # Create a public client application for interactive authentication.
    app = msal.PublicClientApplication(
        client_id=client_id,
        authority=f"https://login.microsoftonline.com/{tenant_id}",
    )

    # Prompt the user to authenticate and acquire an access token.
    result = app.acquire_token_interactive(
        scopes=[scope],
    )

    # Surface any authentication errors with the details returned by MSAL.
    if "access_token" not in result:
        raise RuntimeError(
            f"{result.get('error')}: {result.get('error_description')}"
        )

    return result["access_token"]