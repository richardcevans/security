# Copyright (c) 2026, Oracle and/or its affiliates.
# Validates the SQL accepted by the generic read-only MCP query tool.
# Depends only on the Python standard library regular-expression module.

"""Conservative SQL validation used by the generic query tool."""

from __future__ import annotations

import re

_COMMENT = re.compile(r"--|/\*|\*/")
_READ_ONLY = re.compile(r"^(?:SELECT\b|WITH\b|EXPLAIN\s+PLAN\s+FOR\s+SELECT\b)", re.IGNORECASE)


def clean_read_only_sql(sql: str) -> str:
    cleaned = sql.strip()
    if cleaned.endswith(";"):
        cleaned = cleaned[:-1].rstrip()
    if not cleaned:
        raise ValueError("SQL is required.")
    if ";" in cleaned or _COMMENT.search(cleaned):
        raise ValueError("Only one SQL statement without comments is allowed.")
    if not _READ_ONLY.match(cleaned):
        raise ValueError("Only read-only SELECT, WITH, or EXPLAIN PLAN statements are allowed.")
    return cleaned


def bounded_limit(limit: int, maximum: int = 500) -> int:
    if limit < 1:
        return 1
    return min(limit, maximum)
