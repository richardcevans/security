# Copyright (c) 2026, Oracle and/or its affiliates.
# Interactive CLI that attaches user identity and invokes the Select AI Team.

from __future__ import annotations

import json
import logging
import re

import oracledb
import oracledb.plugins.end_user_sec_provider as deepsec_provider

from app_config import AppConfig
from db_connection import create_connection_pool
from get_user_token import get_access_token

logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")
logger = logging.getLogger(__name__)

_IDENTIFIER_RE = re.compile(r"[A-Za-z][A-Za-z0-9_$#]{0,127}")


def _qualified_name(owner: str, name: str, setting: str) -> str:
    if not _IDENTIFIER_RE.fullmatch(owner) or not _IDENTIFIER_RE.fullmatch(name):
        raise RuntimeError(f"{setting} must contain valid unquoted Oracle identifiers.")
    return f"{owner.upper()}.{name.upper()}"


def _set_select_ai_context(conn, profile_name: str, team_name: str) -> None:
    """Set shared Select AI objects in the current token-attached session."""
    with conn.cursor() as cur:
        cur.callproc(
            "DBMS_CLOUD_AI.SET_PROFILE",
            keyword_parameters={"profile_name": profile_name},
        )
        cur.callproc(
            "DBMS_CLOUD_AI_AGENT.SET_TEAM",
            keyword_parameters={"team_name": team_name},
        )


def _create_conversation(conn) -> str:
    with conn.cursor() as cur:
        conversation_id = cur.callfunc(
            "DBMS_CLOUD_AI.CREATE_CONVERSATION",
            str,
        )
    if not conversation_id:
        raise RuntimeError("The database did not return a Select AI conversation ID.")
    return str(conversation_id)


def _run_team(
    conn,
    team_name: str,
    profile_name: str,
    prompt: str,
    conversation_id: str,
) -> str:
    """Run the team directly in the authenticated Deep Sec session."""
    with conn.cursor() as cur:
        result = cur.callfunc(
            "DBMS_CLOUD_AI_AGENT.RUN_TEAM",
            oracledb.DB_TYPE_CLOB,
            keyword_parameters={
                "team_name": team_name,
                "user_prompt": prompt,
                # The team and SQL tool use {llm_profile}; supply the fully
                # qualified profile name on every invocation.
                "params": json.dumps(
                    {
                        "attribute_variables": {"llm_profile": profile_name},
                        "conversation_id": conversation_id,
                    }
                ),
            },
        )
    if result is None:
        return "No response returned from the Select AI team."
    return result.read() if hasattr(result, "read") else str(result)


def _get_username(conn) -> str:
    with conn.cursor() as cur:
        cur.execute("SELECT ORA_END_USER_CONTEXT.username FROM sys.dual")
        row = cur.fetchone()
    return str(row[0]) if row and row[0] else "unknown"


def main() -> None:
    cfg = AppConfig()
    profile_name = _qualified_name(
        cfg.SELECT_AI_PROFILE_OWNER,
        cfg.SELECT_AI_PROFILE_NAME,
        "SELECT_AI_PROFILE_OWNER and SELECT_AI_PROFILE_NAME",
    )
    team_name = _qualified_name(
        cfg.SELECT_AI_TEAM_OWNER,
        cfg.SELECT_AI_TEAM_NAME,
        "SELECT_AI_TEAM_OWNER and SELECT_AI_TEAM_NAME",
    )
    end_user_identity = get_access_token(
        domain_url=cfg.OCI_DOMAIN_URL,
        client_id=cfg.APP_CLIENT_ID,
        client_secret=cfg.APP_CLIENT_SECRET,
        scope=cfg.APP_SCOPE,
        redirect_uri=cfg.REDIRECT_URI,
    )
    pool = create_connection_pool()

    def connection_factory():
        # The plug-in reads this identity while it acquires the pooled connection.
        deepsec_provider.set_end_user_identity(end_user_identity)
        return pool.acquire()

    try:
        with connection_factory() as conn:
            user = _get_username(conn)
            _set_select_ai_context(conn, profile_name, team_name)
            conversation_id = _create_conversation(conn)

        print("\nOracle Select AI HR Assistant")
        print("─────────────────────────")
        print(f"Authenticated as: {user}")
        print("Type 'exit' to quit\n")

        while True:
            prompt = input("> Q: ").strip()
            if prompt.lower() in {"exit", "quit"}:
                break
            if not prompt:
                continue

            print("Working...")
            try:
                with connection_factory() as conn:
                    _set_select_ai_context(conn, profile_name, team_name)
                    answer = _run_team(
                        conn,
                        team_name,
                        profile_name,
                        prompt,
                        conversation_id,
                    )
                print(f"\nA:\n{answer}\n")
            except Exception as exc:
                logger.exception("Select AI team call failed")
                print(f"\nError: {exc}\n")
    finally:
        pool.close(force=True)


if __name__ == "__main__":
    main()
