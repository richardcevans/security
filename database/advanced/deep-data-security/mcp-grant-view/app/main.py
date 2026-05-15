from __future__ import annotations

import json
import mimetypes
import os
import sys
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import unquote

from app.identity import identity_from_authorization_header
from app.mcp_tools import call_tool, choose_tool_for_question, list_tools
from app.oracle_adapter import GrantViewDatabase


APP_DIR = Path(__file__).resolve().parent
STATIC_DIR = APP_DIR / "static"
database = GrantViewDatabase()


class GrantViewHandler(BaseHTTPRequestHandler):
    server_version = "MCPGrantView/0.1"

    def do_GET(self) -> None:
        if self.path == "/":
            self._send_file(STATIC_DIR / "index.html")
            return

        if self.path == "/health":
            self._send_json({"status": "ok", "db_mode": database.mode})
            return

        if self.path == "/api/config":
            self._send_json(_client_config())
            return

        if self.path == "/mcp/tools":
            self._send_json({"tools": list_tools()})
            return

        if self.path.startswith("/static/"):
            relative = unquote(self.path.removeprefix("/static/"))
            self._send_static_file(relative)
            return

        self._send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:
        if self.path == "/api/ask":
            self._handle_ask()
            return

        if self.path == "/mcp/call":
            self._handle_mcp_call()
            return

        self._send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)

    def _handle_ask(self) -> None:
        body = self._read_json()
        question = str(body.get("question", "")).strip()
        if not question:
            self._send_json({"error": "question is required"}, HTTPStatus.BAD_REQUEST)
            return

        identity = identity_from_authorization_header(self.headers.get("Authorization"))
        tool_name, arguments = choose_tool_for_question(question)
        try:
            result = call_tool(database, identity, tool_name, arguments)
        except RuntimeError as exc:
            self._send_json({"error": str(exc)}, HTTPStatus.NOT_IMPLEMENTED)
            return

        self._send_json(
            {
                "question": question,
                "selected_tool": tool_name,
                "tool_arguments": arguments,
                "identity": _identity_response(identity),
                "answer": _format_answer(tool_name, result),
                "result": result,
            }
        )

    def _handle_mcp_call(self) -> None:
        body = self._read_json()
        tool_name = str(body.get("tool_name", "")).strip()
        arguments = body.get("arguments", {})
        if not tool_name:
            self._send_json({"error": "tool_name is required"}, HTTPStatus.BAD_REQUEST)
            return
        if not isinstance(arguments, dict):
            self._send_json({"error": "arguments must be an object"}, HTTPStatus.BAD_REQUEST)
            return

        identity = identity_from_authorization_header(self.headers.get("Authorization"))
        try:
            result = call_tool(database, identity, tool_name, arguments)
        except ValueError as exc:
            self._send_json({"error": str(exc)}, HTTPStatus.NOT_FOUND)
            return
        except RuntimeError as exc:
            self._send_json({"error": str(exc)}, HTTPStatus.NOT_IMPLEMENTED)
            return

        self._send_json(
            {
                "tool_name": tool_name,
                "identity": _identity_response(identity),
                "result": result,
            }
        )

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            return {}
        return body if isinstance(body, dict) else {}

    def _send_static_file(self, relative: str) -> None:
        target = (STATIC_DIR / relative).resolve()
        if not str(target).startswith(str(STATIC_DIR.resolve())):
            self._send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)
            return
        self._send_file(target)

    def _send_file(self, path: Path) -> None:
        if not path.exists() or not path.is_file():
            self._send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)
            return

        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        content = path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def _send_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        content = json.dumps(payload, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def log_message(self, format: str, *args: Any) -> None:
        print(f"{self.address_string()} - {format % args}")


def _identity_response(identity: Any) -> dict[str, Any]:
    return {
        "subject": identity.subject,
        "display_name": identity.display_name,
        "roles": list(identity.roles),
    }


def _client_config() -> dict[str, Any]:
    app_id_uri = os.getenv("APP_ID_URI") or os.getenv("AZURE_DB_APP_ID_URI") or ""
    default_scope = f"{app_id_uri}/session:scope:connect" if app_id_uri else ""
    return {
        "auth_mode": os.getenv("GRANT_VIEW_AUTH_MODE", "demo").lower(),
        "db_mode": database.mode,
        "tenant_id": os.getenv("TENANT_ID", ""),
        "client_id": os.getenv("CLIENT_ID", ""),
        "app_id_uri": app_id_uri,
        "scope": os.getenv("GRANT_VIEW_ENTRA_SCOPE", default_scope),
    }


def _format_answer(tool_name: str, result: dict[str, Any]) -> str:
    if tool_name == "summarize_my_access":
        roles = ", ".join(result.get("roles", []))
        salary = "can" if result.get("salary_visible") else "cannot"
        return f"You have roles {roles}. In this demo you {salary} view salary values."

    count = result.get("row_count", 0)
    return f"Found {count} visible employee row(s). The database layer decides what is visible."


def main() -> None:
    host = os.getenv("GRANT_VIEW_HOST", "127.0.0.1")
    port = int(os.getenv("GRANT_VIEW_PORT", "8008"))
    try:
        server = ThreadingHTTPServer((host, port), GrantViewHandler)
    except OSError as exc:
        if exc.errno == 98:
            print(
                f"Port {port} is already in use. Stop the existing server or run "
                f"with GRANT_VIEW_PORT=<other-port> ./run.sh",
                file=sys.stderr,
            )
            raise SystemExit(1) from exc
        raise
    print(f"MCP Grant View running at http://{host}:{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
