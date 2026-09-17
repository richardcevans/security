# Copyright (c) 2026, Oracle and/or its affiliates.
# Provides the interactive command-line chat client and its MCP tool-execution loop.
# Depends on asyncio plus this package's OCI Generative AI and MCP client adapters.

"""Interactive CLI that uses OCI Generative AI to call the Oracle SQL MCP server."""

from __future__ import annotations

import argparse
import asyncio

from .config import GenAISettings
from .genai_chat import OCIChat, RequestedToolCall
from .mcp_client import OracleSqlMcpClient

SYSTEM_PROMPT = """
You are an Oracle HR assistant. Use the available MCP tools to answer questions.
The database enforces row and column visibility, so only rely on returned data.
Use describe_table before writing SQL when you are unsure of the schema. Treat
NULL protected fields as not visible. execute_sql accepts read-only SQL only.
Answer in concise, plain English unless the user requests SQL.
""".strip()


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="OCI Generative AI chat client for Oracle SQL MCP")
    parser.add_argument("--no-login", action="store_true", help="Use END_USER_ACCESS_TOKEN instead of client browser login")
    parser.add_argument(
        "--server-url",
        required=True,
        help="URL of the OAuth-protected Streamable HTTP MCP endpoint.",
    )
    return parser.parse_args()


async def run_chat(*, login: bool, server_url: str) -> None:
    settings = GenAISettings()
    async with OracleSqlMcpClient(login=login, server_url=server_url) as mcp_client:
        tools = await mcp_client.list_tools()
        chat = OCIChat(settings, SYSTEM_PROMPT, tools)
        identity = await mcp_client.call_tool("get_current_user", {})
        print(f"Connected to Oracle SQL MCP as: {identity}")
        print("Type 'exit' or 'quit' to end the session.")

        while True:
            try:
                user_text = input("\n> Q: ").strip()
            except EOFError:
                break
            if user_text.lower() in {"exit", "quit"}:
                break
            if not user_text:
                continue
            try:
                turn = await chat.ask(user_text)
                tool_calls = 0
                while turn.tool_calls:
                    tool_calls += len(turn.tool_calls)
                    if tool_calls > settings.max_tool_calls_per_turn:
                        raise RuntimeError("Model exceeded MAX_TOOL_CALLS_PER_TURN.")
                    results: list[tuple[RequestedToolCall, str]] = []
                    for tool_call in turn.tool_calls:
                        print(f"  Using {tool_call.name}…")
                        result = await mcp_client.call_tool(tool_call.name, tool_call.arguments)
                        results.append((tool_call, result))
                    turn = await chat.continue_after_tools(results)
                print(f"A: {turn.text or 'No response returned.'}")
            except Exception as exc:
                print(f"Error: {exc}")


def main() -> None:
    args = _parse_args()
    asyncio.run(run_chat(login=not args.no_login, server_url=args.server_url))


if __name__ == "__main__":
    main()
