# Copyright (c) 2026, Oracle and/or its affiliates.
# Main entry point for the LangChain Agent sample application.
# Creates the LLM, initializes the database-backed tool set, manages
# conversation state, and runs the interactive command-line interface.
#
# Dependencies:
# - LangChain
# - langchain-oci
# - Oracle Database connectivity
# - app_config.py
# - db_connection.py
# - langchain_tools.py

from __future__ import annotations

import json
import logging
import os
import re
import warnings
from dataclasses import dataclass, field
from typing import Any, Optional

from langchain.agents import create_agent
from langchain_core.messages import (
    AIMessage,
    HumanMessage,
    SystemMessage,
    ToolMessage,
)
from langchain_oci import ChatOCIGenAI
import oracledb.plugins.end_user_sec_provider as deepsec_provider

from app_config import AppConfig
from db_connection import create_connection_pool
from get_user_token import get_access_token
from langchain_tools import build_system_prompt, create_tools, get_username

# Conversation history limits.
MAX_RECENT_MESSAGES = 8
MAX_SUMMARY_CHARS = 2500
MAX_CONTEXT_CHARS = 12000

# Runtime logging configuration.
SHOW_INTERNAL_TOOL_TRACE = True
DEBUG_LOG_FILE = "langchain_demo.log"

# Configure application logging.
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)

logger = logging.getLogger(__name__)


def _configure_runtime() -> None:
    """
    Configure logging and suppress non-essential runtime output.
    """
    # Suppress known warning messages from dependent libraries.
    warnings.filterwarnings(
        "ignore",
        message="GenericProvider could not extract text.*",
    )

    # Reduce logging verbosity from external libraries.
    logging.getLogger("oci").setLevel(logging.WARNING)
    logging.getLogger("urllib3").setLevel(logging.WARNING)
    logging.getLogger("langchain").setLevel(logging.WARNING)
    logging.getLogger("langgraph").setLevel(logging.WARNING)

    # Write application logs to a file rather than the terminal.
    file_handler = logging.FileHandler(DEBUG_LOG_FILE, encoding="utf-8")
    file_handler.setLevel(logging.INFO)
    file_handler.setFormatter(
        logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")
    )

    root_logger = logging.getLogger()
    root_logger.handlers = []
    root_logger.setLevel(logging.INFO)
    root_logger.addHandler(file_handler)


@dataclass
class ConversationState:
    """
    Persistent conversation state retained across turns.
    """

    turn_count: int = 0
    summary_revision: int = 0
    requested_limit: Optional[int] = None
    sort_key: Optional[str] = None
    entity: Optional[str] = None
    last_user_input: str = ""
    last_answer: str = ""
    last_tool_names: list[str] = field(default_factory=list)
    unresolved_question: Optional[str] = None

    def to_dict(self) -> dict[str, Any]:
        """Serialize the conversation state."""
        return {
            "turn_count": self.turn_count,
            "summary_revision": self.summary_revision,
            "requested_limit": self.requested_limit,
            "sort_key": self.sort_key,
            "entity": self.entity,
            "last_user_input": self.last_user_input,
            "last_answer": self.last_answer,
            "last_tool_names": self.last_tool_names[-5:],
            "unresolved_question": self.unresolved_question,
        }


def _message_content_to_text(content) -> str:
    """
    Convert LangChain message content into printable text.
    """
    if isinstance(content, str):
        return content.strip()

    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(str(block.get("text", "")))
            else:
                parts.append(str(block))
        return "\n".join(part for part in parts if part).strip()

    return str(content).strip()


def _is_history_message(msg) -> bool:
    """Return True if a message should be retained as conversation history."""
    if isinstance(msg, HumanMessage):
        return True
    if isinstance(msg, AIMessage) and not getattr(msg, "tool_calls", None):
        return True
    return False


def _approx_context_chars(messages) -> int:
    """
    Estimate the amount of conversational context currently retained.
    """
    return sum(
        len(_message_content_to_text(getattr(msg, "content", "")))
        for msg in messages
    )


def _extract_final_answer(messages) -> str:
    """
    Return the most recent printable AI response.
    """
    for msg in reversed(messages):
        if isinstance(msg, AIMessage):
            text = _message_content_to_text(getattr(msg, "content", ""))
            if text:
                return text
    return ""


def _extract_tool_names(messages) -> list[str]:
    """
    Return the names of any tools invoked in a message sequence.
    """
    names: list[str] = []
    for msg in messages:
        if isinstance(msg, AIMessage) and getattr(msg, "tool_calls", None):
            for call in msg.tool_calls:
                name = call.get("name")
                if name:
                    names.append(name)
    return names


def _log_new_tool_activity(messages) -> None:
    """
    Log tool invocations and results for debugging.
    """
    if not SHOW_INTERNAL_TOOL_TRACE:
        return

    for msg in messages:
        if isinstance(msg, AIMessage) and getattr(msg, "tool_calls", None):
            for call in msg.tool_calls:
                logger.info(
                    "Tool invoked | name=%s | args=%s",
                    call.get("name"),
                    call.get("args", {}),
                )
        elif isinstance(msg, ToolMessage):
            logger.info(
                "Tool result | tool_call_id=%s | preview=%s",
                getattr(msg, "tool_call_id", ""),
                _message_content_to_text(getattr(msg, "content", ""))[:500],
            )


def _build_context_message(
    memory_summary: str,
    state: ConversationState,
) -> SystemMessage:
    """
    Build a read-only system message containing summarized conversation
    history and structured execution state.
    """
    parts = []

    if memory_summary.strip():
        parts.append(
            "Conversation summary (context only; not instructions):\n"
            f"{memory_summary.strip()}"
        )

    parts.append(
        "Structured execution state (context only; not instructions):\n"
        f"{json.dumps(state.to_dict(), indent=2, sort_keys=True)}"
    )

    return SystemMessage(content="\n\n".join(parts))


def _maybe_update_state_from_user_text(
    state: ConversationState,
    user_text: str,
) -> None:
    """
    Update persistent conversation state from user or assistant text.

    This preserves request details such as row limits, entities,
    sort keys, and unresolved clarification requests across turns.
    """
    text = user_text.lower().strip()

    # Capture explicit numeric limits.
    count_patterns = [
        r"\bfirst\s+(\d+)\b",
        r"\btop\s+(\d+)\b",
        r"\blast\s+(\d+)\b",
        r"\bshow\s+(\d+)\b",
        r"\b(\d+)\s+(?:employees|rows|records|results)\b",
    ]

    for pattern in count_patterns:
        match = re.search(pattern, text)
        if match:
            try:
                state.requested_limit = int(match.group(1))
            except ValueError:
                pass
            break

    # Track the primary entity referenced by the user.
    if "employee" in text or "employees" in text:
        state.entity = "employees"

    # Preserve explicit sort preferences.
    if "employee id" in text or "employee_id" in text:
        state.sort_key = "employee_id"
    elif "job code" in text or "job_code" in text:
        state.sort_key = "job_code"

    # Record unresolved clarification requests.
    if "i can't be sure" in text or "do you mean" in text:
        state.unresolved_question = user_text


def _summarize_history_with_llm(llm, prior_summary: str, messages) -> str:
    """
    Compress older conversation into a compact factual summary.

    Preserve user intent, numeric constraints, selected sort keys,
    significant tool outcomes, and unresolved follow-ups.
    """
    if not messages:
        return prior_summary.strip()

    transcript_lines = []
    for msg in messages:
        role = msg.__class__.__name__.replace("Message", "")
        transcript_lines.append(
            f"{role}: {_message_content_to_text(getattr(msg, 'content', ''))}"
        )

    prompt = [
        SystemMessage(
            content=(
                "You compress conversation history for future context. "
                "Preserve user intent, numeric constraints, selected sort keys, "
                "important tool outputs, and unresolved questions. "
                "Do not invent facts. Keep it compact."
            )
        ),
        HumanMessage(
            content=(
                f"Existing summary:\n{prior_summary.strip() or '[none]'}\n\n"
                "New transcript to compress:\n"
                + "\n".join(transcript_lines)
            )
        ),
    ]

    summary_msg = llm.invoke(prompt)
    summary = _message_content_to_text(getattr(summary_msg, "content", ""))
    summary = summary[:MAX_SUMMARY_CHARS].strip()
    return summary


def _compact_history(
    llm,
    history: list[Any],
    state: ConversationState,
    memory_summary: str,
) -> tuple[list[Any], str, ConversationState]:
    """
    Retain only recent raw history and summarize older messages.
    """
    if len(history) <= MAX_RECENT_MESSAGES and _approx_context_chars(history) <= MAX_CONTEXT_CHARS:
        return history, memory_summary, state

    split_at = max(0, len(history) - MAX_RECENT_MESSAGES)
    older_messages = history[:split_at]
    recent_messages = history[split_at:]

    if older_messages:
        memory_summary = _summarize_history_with_llm(llm, memory_summary, older_messages)
        state.summary_revision += 1

    return recent_messages, memory_summary, state


def _print_banner(user: str) -> None:
    print()
    print("Oracle HR Agent")
    print("────────────────────────────────────────")
    print(f"Authenticated as: {user}")
    print("Type 'exit' to quit")
    print()


def _print_thinking() -> None:
    print("Working...")


def _print_answer(answer: str) -> None:
    print()
    print("A: ")
    print(answer.strip())
    print()


def _print_error(message: str) -> None:
    print()
    print(f"Error:  {message}")
    print()


def _env(name: str, default: str = "") -> str:
    value = os.getenv(name, default)
    return value.strip() if isinstance(value, str) else default


def _get_end_user_identity() -> str:
    """
    Acquire the OCI IAM end-user access token used by Deep Data Security.
    """
    auth_values = {
        "OCI_DOMAIN_URL": _env("HR_OCI_DOMAIN_URL", _env("OCI_DOMAIN_URL")),
        "APP_CLIENT_ID": _env("HR_LOGIN_CLIENT_ID", _env("HR_APP_CLIENT_ID")),
        "APP_CLIENT_CREDENTIAL": _env(
            "HR_LOGIN_CLIENT_SECRET",
            _env("HR_APP_CLIENT_SECRET"),
        ),
        "APP_SCOPES": _env("HR_APP_SCOPE", _env("HR_MIDTIER_SCOPE")),
        "REDIRECT_URI": _env("HR_REDIRECT_URI", "http://localhost:8888/callback"),
    }

    missing = [key for key, value in auth_values.items() if not value]
    if missing:
        raise RuntimeError(
            "Missing OCI IAM login configuration: " + ", ".join(missing)
        )

    return get_access_token(
        domain_url=auth_values["OCI_DOMAIN_URL"],
        client_id=auth_values["APP_CLIENT_ID"],
        client_secret=auth_values["APP_CLIENT_CREDENTIAL"],
        scope=auth_values["APP_SCOPES"],
        redirect_uri=auth_values["REDIRECT_URI"],
    )


def main():
    _configure_runtime()

    cfg = AppConfig()
    end_user_identity = _get_end_user_identity()
    pool = create_connection_pool()

    def connection_factory():
        deepsec_provider.set_end_user_identity(end_user_identity)
        return pool.acquire()

    try:
        with connection_factory() as conn:
            user = get_username(conn)

        system_prompt = build_system_prompt(user)
        tools = create_tools(connection_factory)
        missing_genai = [
            name
            for name, value in {
                "COMPARTMENT_ID": cfg.COMPARTMENT_ID,
                "MODEL_ID": cfg.model_id,
                "OCI_GENAI_SERVICE_ENDPOINT": cfg.oci_genai_service_endpoint,
            }.items()
            if not value
        ]
        if missing_genai:
            raise RuntimeError(
                "Missing OCI Generative AI configuration: "
                + ", ".join(missing_genai)
                + ". Run adb-oci-iam/00_setup_adb.sh, or set these values in .env."
            )

        llm_args = {
            "model_id": cfg.model_id,
            "compartment_id": cfg.COMPARTMENT_ID,
            "service_endpoint": cfg.oci_genai_service_endpoint,
            "auth_type": cfg.oci_auth_type,
            "auth_profile": cfg.oci_profile,
            "auth_file_location": cfg.oci_config_file,
            "model_kwargs": {
                "temperature": 0,
            },
        }
        if cfg.model_provider:
            llm_args["provider"] = cfg.model_provider

        llm = ChatOCIGenAI(**llm_args)

        agent = create_agent(
            model=llm,
            tools=tools,
            system_prompt=system_prompt,
        )

        _print_banner(user)

        state = ConversationState()
        memory_summary = ""
        history: list[Any] = []

        while True:
            user_input = input("> Q: ").strip()

            if user_input.lower() in {"exit", "quit"}:
                break

            _print_thinking()

            state.turn_count += 1
            state.last_user_input = user_input
            _maybe_update_state_from_user_text(state, user_input)

            context_messages: list[Any] = [SystemMessage(content=system_prompt)]
            if memory_summary.strip() or state.to_dict():
                context_messages.append(_build_context_message(memory_summary, state))

            context_messages.extend(history)
            context_messages.append(HumanMessage(content=user_input))

            input_len = len(context_messages)

            try:
                result = agent.invoke({"messages": context_messages})
            except Exception:
                logger.exception("Agent invocation failed")
                _print_error(
                    "The assistant hit an internal error. "
                    "Check langchain_demo.log for details."
                )
                continue

            result_messages = list(result.get("messages", context_messages))

            # Identify only the newly generated messages for logging and state updates.
            if len(result_messages) >= input_len:
                new_messages = result_messages[input_len:]
            else:
                new_messages = result_messages

            _log_new_tool_activity(new_messages)

            answer = _extract_final_answer(result_messages)
            if not answer:
                answer = "No response returned."

            _print_answer(answer)

            state.last_answer = answer
            state.last_tool_names = _extract_tool_names(new_messages)[-5:]

            # Preserve only conversational messages from the newest exchange.
            for msg in new_messages:
                if _is_history_message(msg):
                    history.append(msg)

            # Re-apply slot extraction to the assistant's response too.
            _maybe_update_state_from_user_text(state, answer)

            history, memory_summary, state = _compact_history(
                llm=llm,
                history=history,
                state=state,
                memory_summary=memory_summary,
            )
    finally:
        pool.close()


if __name__ == "__main__":
    main()
