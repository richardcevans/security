# Copyright (c) 2026, Oracle and/or its affiliates.
# Connects the companion client to the OAuth-protected Oracle SQL MCP HTTP endpoint.
# Depends on the MCP Python SDK, httpx, and the client-owned OCI IAM login flow.

"""MCP client that authenticates before connecting over Streamable HTTP."""

from __future__ import annotations

import os
from contextlib import AsyncExitStack
from typing import Any

import httpx
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client

from .auth import login
from .config import Settings


class OracleSqlMcpClient:
    """Authenticate the caller and connect to an Oracle SQL MCP server."""

    def __init__(self, *, login: bool = True, server_url: str) -> None:
        self._login = login
        self._server_url = server_url
        self._stack = AsyncExitStack()
        self._session: ClientSession | None = None

    async def __aenter__(self) -> "OracleSqlMcpClient":
        token = self._client_token()
        http_client = await self._stack.enter_async_context(
            httpx.AsyncClient(
                headers={"Authorization": f"Bearer {token}"},
                follow_redirects=True,
                # Database acquisition and OCI IAM introspection can exceed httpx's
                # five-second default, especially on an initial request.
                timeout=httpx.Timeout(60.0),
            )
        )
        read_stream, write_stream, _ = await self._stack.enter_async_context(
            streamable_http_client(self._server_url, http_client=http_client)
        )
        self._session = await self._stack.enter_async_context(ClientSession(read_stream, write_stream))
        await self._session.initialize()
        return self

    async def __aexit__(self, *exc_info: object) -> None:
        await self._stack.aclose()

    async def list_tools(self) -> list[Any]:
        return list((await self._require_session().list_tools()).tools)

    async def call_tool(self, name: str, arguments: dict[str, Any]) -> str:
        result = await self._require_session().call_tool(name, arguments)
        text = "\n".join(
            getattr(item, "text", str(item)) for item in result.content
        )
        return f"TOOL_ERROR: {text}" if result.isError else text

    def _require_session(self) -> ClientSession:
        if self._session is None:
            raise RuntimeError("MCP client has not connected yet.")
        return self._session

    def _client_token(self) -> str:
        """Authenticate at the client boundary, never in the MCP server process."""
        if self._login:
            return login(Settings())
        token = os.getenv("END_USER_ACCESS_TOKEN", "").strip()
        if not token:
            raise RuntimeError("Set END_USER_ACCESS_TOKEN or omit --no-login.")
        return token
