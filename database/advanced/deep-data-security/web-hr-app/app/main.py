import json
import mimetypes
import os
import sys
import traceback
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from socketserver import ThreadingMixIn
from urllib.parse import parse_qs, urlparse

from app.db import WebHrDatabase
from app.identity import (
    app_config,
    clear_session,
    demo_session,
    finish_login,
    new_login,
    session_from_cookie,
    token_debug_from_session,
    user_from_session,
)


APP_DIR = Path(__file__).resolve().parent
STATIC_DIR = APP_DIR / "static"
DATABASE = WebHrDatabase()


class WebHrServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True


class Handler(BaseHTTPRequestHandler):
    server_version = "WebHRApp/0.1"

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/":
            self._send_file(STATIC_DIR / "index.html")
            return

        if path == "/debug":
            self._send_file(STATIC_DIR / "debug.html")
            return

        if path == "/config":
            self._send_json(app_config())
            return

        if path == "/favicon.ico":
            self.send_response(HTTPStatus.NO_CONTENT)
            self.end_headers()
            return

        if path == "/login":
            try:
                params = parse_qs(parsed.query)
                prompt = params.get("prompt", ["select_account"])[0]
                self._redirect(new_login(prompt=prompt))
            except Exception as exc:
                self._send_text(str(exc), HTTPStatus.BAD_REQUEST)
            return

        if path == "/demo/marvin":
            self._set_session_and_redirect(demo_session("marvin"))
            return

        if path == "/demo/emma":
            self._set_session_and_redirect(demo_session("emma"))
            return

        if path == "/callback":
            params = parse_qs(parsed.query)
            try:
                session_id = finish_login(
                    params.get("state", [""])[0],
                    params.get("code", [""])[0],
                )
            except Exception as exc:
                self._send_text("Login failed: {0}".format(exc), HTTPStatus.BAD_REQUEST)
                return
            self._set_session_and_redirect(session_id)
            return

        if path == "/logout":
            clear_session(self.headers.get("Cookie", ""))
            self.send_response(HTTPStatus.FOUND)
            self.send_header("Set-Cookie", "web_hr_session=; Max-Age=0; Path=/; HttpOnly; SameSite=Lax")
            self.send_header("Location", "/")
            self.end_headers()
            return

        if path == "/api/me":
            self._send_json({"user": self._current_user()})
            return

        if path == "/api/debug/tokens":
            session = session_from_cookie(self.headers.get("Cookie", ""))
            if not session:
                self._send_json({"error": "not signed in"}, HTTPStatus.UNAUTHORIZED)
                return
            user = user_from_session(session)
            payload = token_debug_from_session(session) or {}
            self._call_database(lambda: self._merge_debug_payload(payload, user))
            return

        if path == "/api/debug/database-context":
            user = self._require_user()
            if not user:
                return
            self._call_database(lambda: DATABASE.debug_context_for_user(user))
            return

        if path == "/api/preflight":
            user = self._require_user()
            if not user:
                return
            self._call_database(lambda: DATABASE.preflight(user))
            return

        if path == "/api/employees":
            user = self._require_user()
            if not user:
                return
            self._call_database(lambda: DATABASE.employees_for_user(user))
            return

        if path == "/api/salary-summary":
            user = self._require_user()
            if not user:
                return
            self._call_database(lambda: DATABASE.salary_summary(user))
            return

        if path == "/api/audit/events":
            user = self._require_user()
            if not user:
                return
            self._call_database(lambda: DATABASE.audit_events(user))
            return

        if path.startswith("/static/"):
            relative = path[len("/static/") :]
            self._send_static(relative)
            return

        self._send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/api/employees/update":
            user = self._require_user()
            if not user:
                return
            try:
                payload = self._read_json_body()
                employee_id = int(payload.get("employee_id"))
                field_name = str(payload.get("field", ""))
                value = payload.get("value")
            except Exception as exc:
                self._send_json({"error": "invalid request", "detail": str(exc)}, HTTPStatus.BAD_REQUEST)
                return
            self._call_database(lambda: DATABASE.update_employee_field(user, employee_id, field_name, value))
            return

        if path == "/api/policy/disable-salary-updates":
            user = self._require_user()
            if not user:
                return
            self._call_database(lambda: DATABASE.disable_salary_updates(user))
            return

        if path == "/api/policy/enable-salary-updates":
            user = self._require_user()
            if not user:
                return
            self._call_database(lambda: DATABASE.enable_salary_updates(user))
            return

        self._send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)

    def _current_user(self):
        session = session_from_cookie(self.headers.get("Cookie", ""))
        if not session:
            return None
        user = user_from_session(session)
        user.pop("access_token", None)
        return user

    def _require_user(self):
        session = session_from_cookie(self.headers.get("Cookie", ""))
        if not session:
            self._send_json({"error": "not signed in"}, HTTPStatus.UNAUTHORIZED)
            return None
        return user_from_session(session)

    def _call_database(self, fn):
        try:
            self._send_json(fn())
        except Exception as exc:
            traceback.print_exc()
            self._send_json(
                {
                    "error": str(exc),
                    "detail": traceback.format_exc(),
                },
                HTTPStatus.INTERNAL_SERVER_ERROR,
            )

    def _merge_debug_payload(self, payload, user):
        payload["obo_database_token"] = DATABASE.debug_tokens_for_user(user)
        self._log_debug_payload("Token diagnostics", payload)
        return payload

    def _log_debug_payload(self, label, payload):
        print("")
        print("========================================================================")
        print(label)
        print("========================================================================")
        print(json.dumps(payload, indent=2, sort_keys=True))
        print("========================================================================")
        print("")

    def _set_session_and_redirect(self, session_id):
        self.send_response(HTTPStatus.FOUND)
        self.send_header(
            "Set-Cookie",
            "web_hr_session={0}; Path=/; HttpOnly; SameSite=Lax".format(session_id),
        )
        self.send_header("Location", "/")
        self.end_headers()

    def _send_static(self, relative):
        target = (STATIC_DIR / relative).resolve()
        if not str(target).startswith(str(STATIC_DIR.resolve())):
            self._send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)
            return
        self._send_file(target)

    def _read_json_body(self):
        length = int(self.headers.get("Content-Length", "0"))
        content = self.rfile.read(length).decode("utf-8")
        return json.loads(content or "{}")

    def _send_file(self, path):
        if not path.exists() or not path.is_file():
            self._send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)
            return
        content = path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", mimetypes.guess_type(path.name)[0] or "application/octet-stream")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def _send_json(self, payload, status=HTTPStatus.OK):
        content = json.dumps(payload, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def _send_text(self, text, status=HTTPStatus.OK):
        content = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def _redirect(self, location):
        self.send_response(HTTPStatus.FOUND)
        self.send_header("Location", location)
        self.end_headers()

    def log_message(self, fmt, *args):
        print("{0} - {1}".format(self.address_string(), fmt % args))


def main():
    host = os.getenv("WEB_HR_HOST", "127.0.0.1")
    port = int(os.getenv("WEB_HR_PORT", "8012"))
    try:
        server = WebHrServer((host, port), Handler)
    except OSError as exc:
        if exc.errno == 98:
            print(
                "Port {0} is already in use. Stop the existing server or run "
                "with WEB_HR_PORT=<other-port> ./run.sh".format(port),
                file=sys.stderr,
            )
            raise SystemExit(1)
        raise
    print("Web HR App running at http://{0}:{1}".format(host, port))
    print("Database mode: {0}".format(os.getenv("WEB_HR_DB_MODE", "mock")))
    server.serve_forever()


if __name__ == "__main__":
    main()
