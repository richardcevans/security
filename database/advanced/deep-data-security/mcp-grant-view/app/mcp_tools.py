from __future__ import annotations

from typing import Any

from app.identity import UserIdentity
from app.oracle_adapter import GrantViewDatabase


def list_tools() -> list[dict[str, Any]]:
    return [
        {
            "name": "search_employees",
            "description": "Search employee records visible to the current user.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Optional name, department, or region filter.",
                    }
                },
            },
        },
        {
            "name": "summarize_my_access",
            "description": "Show the current user's roles and effective demo data access.",
            "input_schema": {"type": "object", "properties": {}},
        },
    ]


def call_tool(
    database: GrantViewDatabase,
    identity: UserIdentity,
    tool_name: str,
    arguments: dict[str, Any] | None = None,
) -> dict[str, Any]:
    args = arguments or {}

    if tool_name == "search_employees":
        return database.search_employees(identity, query=str(args.get("query", "")))

    if tool_name == "summarize_my_access":
        return database.summarize_access(identity)

    raise ValueError(f"Unknown tool: {tool_name}")


def choose_tool_for_question(question: str) -> tuple[str, dict[str, Any]]:
    lowered = question.lower()
    if "access" in lowered or "role" in lowered or "grant" in lowered:
        return "summarize_my_access", {}

    query = question.lower()
    for prefix in ("show me", "find", "search", "list", "who can i see"):
        query = query.replace(prefix, "").strip()
    for filler in ("employees", "employee", "records", "rows", "data"):
        query = query.replace(filler, "").strip()
    return "search_employees", {"query": query}
