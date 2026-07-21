#!/usr/bin/env python3
"""Loopback API that proves an OCI IAM caller token reaches ADB unchanged.

The service accepts a bearer token, validates it with the Identity Domain JWKS,
and opens a short-lived ADB connection with that same token. It provides an
identity proof, reviewed query tools, and a bounded LLM tool loop. It never
accepts arbitrary SQL.
"""

import json
import os
import re
import subprocess
import sys
from decimal import Decimal
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import urlopen

import jwt
import oracledb
from jwt import PyJWKClient


MAX_BODY_BYTES = 4096
MAX_QUESTION_CHARS = 1000


def required_env(name):
    value = os.getenv(name, "")
    if not value:
        raise RuntimeError(f"{name} is required")
    return value


class ServiceSettings:
    def __init__(self):
        self.dsn = required_env("ADB_SERVICE")
        self.config_dir = required_env("TNS_ADMIN")
        self.wallet_password = required_env("WALLET_PWD")
        self.domain_url = required_env("OCI_DOMAIN_URL").rstrip("/")
        self.audience = required_env("OCI_AUDIENCE")
        self.genai_compartment_id = required_env("ROOT_COMP_ID")
        self.genai_region = os.getenv("GENAI_REGION", "us-chicago-1")
        self.genai_model_id = os.getenv("GENAI_MODEL_ID", "meta.llama-3.3-70b-instruct")
        self.oci_connection_timeout = int(os.getenv("OCI_CONNECTION_TIMEOUT", "10"))
        self.oci_read_timeout = int(os.getenv("OCI_READ_TIMEOUT", "60"))
        self.metadata = self._metadata()
        self.jwks = PyJWKClient(self.metadata["jwks_uri"])

    def _metadata(self):
        with urlopen(f"{self.domain_url}/.well-known/openid-configuration", timeout=15) as response:
            return json.loads(response.read().decode("utf-8"))

    def validate_bearer_token(self, token):
        key = self.jwks.get_signing_key_from_jwt(token).key
        return jwt.decode(
            token,
            key,
            algorithms=["RS256", "RS384", "RS512"],
            audience=self.audience,
            issuer=self.metadata["issuer"],
            options={"require": ["exp", "iss", "sub"]},
        )

    def database_proof(self, token):
        # The caller's bearer token is passed directly to ADB. No ADMIN account,
        # service account, shared schema account, or database password is used.
        with self._connection(token) as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT SYS_CONTEXT('USERENV', 'AUTHENTICATED_IDENTITY'),
                           SYS_CONTEXT('USERENV', 'CURRENT_USER'),
                           SYS_CONTEXT('USERENV', 'AUTHENTICATION_METHOD'),
                           SYS_CONTEXT('USERENV', 'CLIENT_PROGRAM_NAME')
                      FROM dual
                    """
                )
                authenticated_identity, current_user, authentication_method, client_program_name = cursor.fetchone()
                cursor.execute("SELECT COUNT(*) FROM hr.employees")
                (visible_employee_rows,) = cursor.fetchone()
        return {
            "authenticated_identity": authenticated_identity,
            "current_user": current_user,
            "authentication_method": authentication_method,
            "client_program_name": client_program_name,
            "visible_employee_rows": _json_value(visible_employee_rows),
        }

    def run_query_tool(self, token, tool, arguments):
        """Run one reviewed, parameterized query as the bearer-token user."""
        statement, binds = _query_tool_statement(tool, arguments)
        with self._connection(token) as connection:
            with connection.cursor() as cursor:
                cursor.execute(statement, binds)
                columns = [item[0].lower() for item in cursor.description]
                rows = [_json_row(dict(zip(columns, row))) for row in cursor]
        return {"tool": tool, "arguments": arguments, "rows": rows}

    def _connection(self, token):
        return oracledb.connect(
            access_token=token,
            dsn=self.dsn,
            config_dir=self.config_dir,
            wallet_location=self.config_dir,
            wallet_password=self.wallet_password,
        )

    def answer_question(self, token, question):
        """Run the bounded GenAI → reviewed-tool → GenAI loop for one caller."""
        selection_text = self._chat(_tool_selection_request(question), max_tokens=128)
        try:
            selection = json.loads(selection_text)
        except json.JSONDecodeError as exc:
            raise ValueError(f"LLM returned invalid tool-selection JSON: {exc}") from exc
        if not isinstance(selection, dict):
            raise ValueError("LLM tool selection must be a JSON object")
        tool = selection.get("tool")
        arguments = selection.get("arguments", {})
        if tool == "unsupported":
            return {
                "selected_tool": "unsupported",
                "tool_result": None,
                "answer": "That question is outside the service's reviewed HR query tools.",
            }
        if not isinstance(tool, str) or not isinstance(arguments, dict):
            raise ValueError("LLM tool selection must contain a string tool and an object arguments")
        tool_result = self.run_query_tool(token, tool, arguments)
        answer = self._chat(_answer_request(question, tool_result), max_tokens=512)
        return {"selected_tool": tool, "tool_result": tool_result, "answer": answer}

    def _chat(self, instruction, max_tokens):
        request = {
            "apiFormat": "GENERIC",
            "messages": [{"role": "USER", "content": [{"type": "TEXT", "text": instruction}]}],
            "maxTokens": max_tokens,
            "temperature": 0,
        }
        command = _oci_cli_command(
            "generative-ai-inference", "chat-result", "chat",
            "--region", self.genai_region,
            "--connection-timeout", str(self.oci_connection_timeout),
            "--read-timeout", str(self.oci_read_timeout),
            "--compartment-id", self.genai_compartment_id,
            "--serving-mode", json.dumps({"servingType": "ON_DEMAND", "modelId": self.genai_model_id}),
            "--chat-request", json.dumps(request),
            "--output", "json",
        )
        try:
            completed = subprocess.run(command, check=True, capture_output=True, text=True, timeout=self.oci_read_timeout + 15)
            response = json.loads(completed.stdout)
            return response["data"]["chat-response"]["choices"][0]["message"]["content"][0]["text"].strip()
        except FileNotFoundError as exc:
            raise RuntimeError("OCI CLI is required for this local GenAI service") from exc
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError("OCI Generative AI request timed out") from exc
        except subprocess.CalledProcessError as exc:
            detail = (exc.stderr or exc.stdout or "OCI CLI failed").strip()
            raise RuntimeError(f"OCI Generative AI request failed: {detail}") from exc
        except (KeyError, IndexError, TypeError, json.JSONDecodeError) as exc:
            raise RuntimeError(f"OCI Generative AI returned an unexpected response: {exc}") from exc


class IdentityProofHandler(BaseHTTPRequestHandler):
    server_version = "DeepSecGenAIIdentityProof/0.1"

    def do_GET(self):
        if self.path == "/healthz":
            self._send_json({"status": "ok", "service": "identity-proof"})
            return
        self._send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)

    def do_POST(self):
        if self.path not in {"/v1/identity/proof", "/v1/query", "/v1/ask"}:
            self._send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)
            return

        payload = self._read_small_json_body()
        if payload is None:
            return
        token = self._bearer_token()
        if not token:
            self._send_json({"error": "Authorization: Bearer <OCI IAM database access token> is required"}, HTTPStatus.UNAUTHORIZED)
            return

        try:
            claims = SETTINGS.validate_bearer_token(token)
        except Exception as exc:  # Do not reveal the token or a trace.
            self._send_json({"error": "bearer token validation failed", "detail": str(exc)}, HTTPStatus.UNAUTHORIZED)
            return

        if self.path == "/v1/query":
            self._run_query(token, payload)
            return

        if self.path == "/v1/ask":
            self._ask_llm(token, payload)
            return

        try:
            database = SETTINGS.database_proof(token)
        except Exception as exc:  # Database error is useful to the local caller, but no traceback is returned.
            print(f"ADB identity proof failed: {type(exc).__name__}: {exc}", file=sys.stderr)
            self._send_json({"error": "ADB identity proof failed", "detail": str(exc)}, HTTPStatus.BAD_GATEWAY)
            return

        self._send_json(
            {
                "proof": "pass",
                "token_subject": claims.get("user_name") or claims.get("preferred_username") or claims.get("sub"),
                "token_audience": claims.get("aud"),
                "database": database,
            }
        )

    def _run_query(self, token, payload):
        if not isinstance(payload, dict):
            self._send_json({"error": "request body must be a JSON object"}, HTTPStatus.BAD_REQUEST)
            return
        tool = payload.get("tool")
        arguments = payload.get("arguments", {})
        if not isinstance(tool, str) or not isinstance(arguments, dict):
            self._send_json({"error": "tool must be a string and arguments must be an object"}, HTTPStatus.BAD_REQUEST)
            return
        try:
            result = SETTINGS.run_query_tool(token, tool, arguments)
        except ValueError as exc:
            self._send_json({"error": str(exc)}, HTTPStatus.BAD_REQUEST)
        except Exception as exc:
            print(f"ADB query tool failed: {type(exc).__name__}: {exc}", file=sys.stderr)
            self._send_json({"error": "ADB query tool failed", "detail": str(exc)}, HTTPStatus.BAD_GATEWAY)
        else:
            self._send_json(result)

    def _ask_llm(self, token, payload):
        if not isinstance(payload, dict) or set(payload) != {"question"}:
            self._send_json({"error": "request body must contain exactly one field: question"}, HTTPStatus.BAD_REQUEST)
            return
        question = payload["question"]
        if not isinstance(question, str) or not question.strip() or len(question) > MAX_QUESTION_CHARS:
            self._send_json({"error": f"question must be non-empty text up to {MAX_QUESTION_CHARS} characters"}, HTTPStatus.BAD_REQUEST)
            return
        try:
            result = SETTINGS.answer_question(token, question.strip())
        except ValueError as exc:
            self._send_json({"error": str(exc)}, HTTPStatus.BAD_REQUEST)
        except Exception as exc:
            print(f"LLM query loop failed: {type(exc).__name__}: {exc}", file=sys.stderr)
            self._send_json({"error": "LLM query loop failed", "detail": str(exc)}, HTTPStatus.BAD_GATEWAY)
        else:
            self._send_json({"question": question.strip(), **result})

    def _read_small_json_body(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._send_json({"error": "invalid Content-Length"}, HTTPStatus.BAD_REQUEST)
            return None
        if length > MAX_BODY_BYTES:
            self._send_json({"error": "request body is too large"}, HTTPStatus.REQUEST_ENTITY_TOO_LARGE)
            return None
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._send_json({"error": "request body must be JSON"}, HTTPStatus.BAD_REQUEST)
            return None
        return payload

    def _bearer_token(self):
        value = self.headers.get("Authorization", "")
        scheme, _, token = value.partition(" ")
        return token.strip() if scheme.lower() == "bearer" and token.strip() else ""

    def _send_json(self, payload, status=HTTPStatus.OK):
        body = json.dumps(payload, default=_json_value, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format_string, *args):
        # Never log request headers, which could contain a bearer token.
        print(f"{self.address_string()} - {format_string % args}", file=sys.stderr)


def _json_value(value):
    return float(value) if isinstance(value, Decimal) else value


def _json_row(row):
    return {key: _json_value(value) for key, value in row.items()}


def _query_tool_statement(tool, arguments):
    """Return only reviewed SQL and bind values; no request text becomes SQL."""
    if tool == "employee_count":
        _require_no_unknown_arguments(arguments, set())
        return "SELECT COUNT(*) AS visible_employee_rows FROM hr.employees", {}

    if tool == "employees_by_department":
        _require_no_unknown_arguments(arguments, set())
        return """
            SELECT department_id, COUNT(*) AS employee_count
              FROM hr.employees
             GROUP BY department_id
             ORDER BY department_id
        """, {}

    if tool == "employees_by_job_code":
        _require_no_unknown_arguments(arguments, set())
        return """
            SELECT job_code, COUNT(*) AS employee_count
              FROM hr.employees
             GROUP BY job_code
             ORDER BY job_code
        """, {}

    if tool == "list_employees":
        _require_no_unknown_arguments(arguments, {"department_id", "job_code", "limit"})
        conditions = []
        binds = {}
        if "department_id" in arguments:
            department_id = arguments["department_id"]
            if isinstance(department_id, bool) or not isinstance(department_id, int) or department_id < 1:
                raise ValueError("department_id must be a positive integer")
            conditions.append("department_id = :department_id")
            binds["department_id"] = department_id
        if "job_code" in arguments:
            job_code = arguments["job_code"]
            if not isinstance(job_code, str) or not re.fullmatch(r"[A-Za-z0-9_]{1,10}", job_code):
                raise ValueError("job_code must contain only letters, numbers, or underscores and be at most 10 characters")
            conditions.append("job_code = :job_code")
            binds["job_code"] = job_code.upper()
        limit = arguments.get("limit", 25)
        if isinstance(limit, bool) or not isinstance(limit, int) or not 1 <= limit <= 100:
            raise ValueError("limit must be an integer from 1 through 100")
        binds["limit"] = limit
        where_clause = " WHERE " + " AND ".join(conditions) if conditions else ""
        return f"""
            SELECT employee_id, first_name, last_name, job_code,
                   department_id, manager_id, user_name
              FROM hr.employees
              {where_clause}
             ORDER BY employee_id
             FETCH FIRST :limit ROWS ONLY
        """, binds

    raise ValueError(
        "unknown tool. Allowed tools: employee_count, employees_by_department, "
        "employees_by_job_code, list_employees"
    )


def _require_no_unknown_arguments(arguments, allowed):
    unexpected = sorted(set(arguments) - allowed)
    if unexpected:
        raise ValueError("unsupported argument(s): " + ", ".join(unexpected))


def _tool_selection_request(question):
    return """You are a query-tool router for a protected HR service. Return exactly one JSON object and no markdown.

Schema:
{"tool":"TOOL_NAME","arguments":{}}

Allowed tools:
- employee_count: count the caller's authorized HR.EMPLOYEES rows. arguments must be {}.
- employees_by_department: count authorized employees by department. arguments must be {}.
- employees_by_job_code: count authorized employees by job code. arguments must be {}.
- list_employees: list authorized non-sensitive employee fields. Optional arguments are department_id (positive integer), job_code (letters/numbers/underscore, max 10), and limit (integer 1 through 100).
- unsupported: use only when none of the tools can answer. arguments must be {}.

Never write SQL. Never invent a tool or argument. Do not request salary, SSN, phone number, photo, or any data not returned by these tools.

User question:
""" + question


def _answer_request(question, tool_result):
    return (
        "Answer the user using only the authorized database-tool result below. "
        "Do not claim to have executed SQL yourself. If the result does not fully answer the question, say what is unavailable.\n\n"
        f"USER_QUESTION:\n{question}\n\n"
        f"AUTHORIZED_TOOL_RESULT_JSON:\n{json.dumps(tool_result, separators=(',', ':'))}"
    )


def _oci_cli_command(*arguments):
    command = [os.getenv("OCI_CLI_BIN", "oci")]
    config_file = os.getenv("OCI_CONFIG_FILE") or os.getenv("OCI_CLI_CONFIG_FILE")
    if config_file:
        command.extend(["--config-file", config_file])
    profiles = [value for value in (os.getenv("OCI_PROFILE_NAME"), os.getenv("OCI_PROFILE"), os.getenv("OCI_CLI_PROFILE")) if value]
    if len(set(profiles)) > 1:
        raise RuntimeError("OCI_PROFILE_NAME, OCI_PROFILE, and OCI_CLI_PROFILE select different profiles")
    if profiles:
        command.extend(["--profile", profiles[0]])
    command.extend(arguments)
    return command


def main():
    host = os.getenv("IDENTITY_SERVICE_HOST", "127.0.0.1")
    port = int(os.getenv("IDENTITY_SERVICE_PORT", "8030"))
    if host not in {"127.0.0.1", "localhost", "::1"}:
        raise RuntimeError("This first identity-proof service is loopback-only. Keep IDENTITY_SERVICE_HOST on localhost.")
    global SETTINGS
    SETTINGS = ServiceSettings()
    server = ThreadingHTTPServer((host, port), IdentityProofHandler)
    print(f"Identity-proof API listening on http://{host}:{port}")
    print("Endpoints: GET /healthz, POST /v1/identity/proof, POST /v1/query, POST /v1/ask")
    server.serve_forever()


if __name__ == "__main__":
    main()
