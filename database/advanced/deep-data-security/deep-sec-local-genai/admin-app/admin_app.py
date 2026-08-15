"""Fixed-action administrator console for the Deep Sec training environment."""

import logging
import os
from pathlib import Path
import secrets
import subprocess
import time
from threading import Lock
from typing import Optional

from dotenv import load_dotenv
from flask import Flask, jsonify, redirect, render_template, request, url_for
from flask_login import LoginManager, UserMixin, current_user, login_required, login_user, logout_user
from flask_wtf.csrf import CSRFProtect

from admin_config import load_admin_settings
from admin_db import completed_setup_actions, lab_state, verify_admin

load_dotenv()
settings = load_admin_settings()
app = Flask(__name__)
app.config["SECRET_KEY"] = settings.secret_key
app.config["SESSION_COOKIE_NAME"] = "deep_sec_admin_session"
app.config["SESSION_COOKIE_HTTPONLY"] = True
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"
csrf = CSRFProtect(app)
login_manager = LoginManager(app)
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
app.logger.setLevel(getattr(logging, os.getenv("ADMIN_LOG_LEVEL", "INFO").upper(), logging.INFO))

LOGIN_TTL_SECONDS = 90 * 60
VIBE_TIMEOUT_SECONDS = 360
VIBE_PROMPTS = {
    "customer_search": {
        "title": "Add customer search",
        "description": "Add a search box that asks for every customer, not just Marvin's sales team.",
        "prompt": "Add a customer search box to the application. This search bar should search every customer not just the customers Marvin can see.",
    },
    "all_customers": {
        "title": "Try an all-customer page",
        "description": "Add a page that tries to display every customer and every customer field.",
        "prompt": "Add an admin-style page that tries to display every customer and every customer field.",
    },
}
_logins: dict[str, dict] = {}
_logins_lock = Lock()


class AdminUser(UserMixin):
    """Opaque browser identity; the ADMIN password remains process-memory only."""

    def __init__(self, login_id: str):
        self.id = login_id


@login_manager.user_loader
def load_user(login_id: str):
    with _logins_lock:
        login = _logins.get(login_id)
        if not login or login["expires_at"] <= time.monotonic():
            _logins.pop(login_id, None)
            return None
        return AdminUser(login_id)


@login_manager.unauthorized_handler
def unauthorized():
    if request.path.startswith("/api/"):
        return jsonify(error="Sign in as ADMIN first"), 401
    return redirect(url_for("index"))


def _admin_password() -> str:
    login_id = current_user.get_id()
    with _logins_lock:
        login = _logins.get(login_id)
        if not login or login["expires_at"] <= time.monotonic():
            if login_id:
                _logins.pop(login_id, None)
            raise ValueError("Sign in as ADMIN first")
        login["expires_at"] = time.monotonic() + LOGIN_TTL_SECONDS
        return login["password"]


def _completed_actions() -> set[str]:
    """Return the guided setup actions completed in this ADMIN session."""
    login_id = current_user.get_id()
    with _logins_lock:
        login = _logins.get(login_id)
        if not login or login["expires_at"] <= time.monotonic():
            raise ValueError("Sign in as ADMIN first")
        return set(login.get("completed_actions", set()))


def _record_completed_action(action: dict) -> list[str]:
    """Advance or reset the guided setup sequence after a successful script."""
    login_id = current_user.get_id()
    with _logins_lock:
        login = _logins.get(login_id)
        if not login or login["expires_at"] <= time.monotonic():
            raise ValueError("Sign in as ADMIN first")
        if action["resets_setup"]:
            login["completed_actions"] = set()
        else:
            login.setdefault("completed_actions", set()).add(action["key"])
        return sorted(login["completed_actions"])


def _record_action_output(action_key: str, output: str) -> None:
    """Keep each fixed script's complete SQL*Plus output with this ADMIN session."""
    login_id = current_user.get_id()
    with _logins_lock:
        login = _logins.get(login_id)
        if login and login["expires_at"] > time.monotonic():
            login.setdefault("action_outputs", {})[action_key] = output


def _action_outputs() -> dict[str, str]:
    """Return prior complete script output for rendering in its own step panel."""
    login_id = current_user.get_id()
    with _logins_lock:
        login = _logins.get(login_id)
        if not login or login["expires_at"] <= time.monotonic():
            return {}
        return dict(login.get("action_outputs", {}))


def _database_completed_actions() -> set[str]:
    """Use durable Oracle state to restore setup progress after a re-login."""
    try:
        return completed_setup_actions(settings, _admin_password())
    except Exception as exc:
        app.logger.warning("Could not infer setup progress from Oracle: %s", exc)
        return set()


def _action(
    key: str,
    title: str,
    description: str,
    *scripts: str,
    destructive: bool = False,
    needs_password: bool = False,
    database_user: str = "ADMIN",
    requires: tuple[str, ...] = (),
    resets_setup: bool = False,
    link_step: bool = False,
    link_url: Optional[str] = None,
    short_label: Optional[str] = None,
) -> dict:
    resolved = []
    for script in scripts:
        path = Path(settings.database_dir, script).resolve()
        if path.parent != Path(settings.database_dir).resolve() or not path.is_file():
            raise RuntimeError(f"Required lab script is missing: {script}")
        resolved.append({"name": script, "path": path, "sql": path.read_text(encoding="utf-8")})
    return {
        "key": key,
        "title": title,
        "description": description,
        "scripts": resolved,
        "destructive": destructive,
        "needs_password": needs_password,
        "database_user": database_user,
        "requires": requires,
        "resets_setup": resets_setup,
        "link_step": link_step,
        "link_url": link_url,
        "short_label": short_label or title,
    }


# This is the complete allow-list. Requests can select only these checked-in,
# visible scripts—never a browser-provided SQL statement, path, or command.
ACTIONS = {
    action["key"]: action
    for action in (
        _action("create_schema", "Create APPLAB schema", "Recreates APPLAB.CUSTOMERS and its supporting index.", "01_create_schema.sql", destructive=True, short_label="Create schema"),
        _action("load_data", "Load customer data", "Loads the 22 sample customer rows used by the demonstration.", "02_load_sample_data.sql", destructive=True, requires=("create_schema",), short_label="Load data"),
        _action("show_architecture", "Show authentication model", "Shows the direct MARVIN-to-Oracle authentication explanation.", "03_create_app_user.sql", requires=("load_data",), short_label="Show auth model"),
        _action("create_roles", "Create data roles and grant definitions", "Creates the full-access, employee, and manager data roles and the full-access data grant.", "04_create_full_access.sql", destructive=True, requires=("show_architecture",), short_label="Create roles"),
        _action("create_marvin", "Create MARVIN", "Creates the local end user and grants the full-access role.", "05_create_lab_users.sql", destructive=True, needs_password=True, requires=("create_roles",), short_label="Create MARVIN"),
        _action("enable_full_access", "Enable full access", "Grants APP_FULL_ACCESS so Marvin can request every row and displayed column.", "08_enable_full_access.sql", destructive=True, requires=("create_marvin",), short_label="Enable full access"),
        _action("customer_sales", "Customer Sales", "Navigate to the Oracle Customer Sales application to view Marvin's current access.", requires=("enable_full_access",), link_step=True, short_label="Customer Sales"),
        _action("disable_full_access", "Disable full access", "Revokes APP_FULL_ACCESS from Marvin.", "09_disable_full_access.sql", destructive=True, requires=("create_marvin",), short_label="Disable full access"),
        _action("enable_employee", "Enable sales-employee policy", "Replaces the full-access role with APP_SALES_EMPLOYEE.", "06_implement_deep_sec_policies.sql", destructive=True, requires=("create_marvin",), short_label="Enable sales-employee"),
        _action("disable_employee", "Disable sales-employee policy", "Revokes APP_SALES_EMPLOYEE from Marvin.", "10_disable_employee_policy.sql", destructive=True, requires=("create_marvin",), short_label="Disable sales-employee"),
        _action("enable_manager", "Enable sales-manager policy", "Adds APP_SALES_MANAGER while Marvin retains the employee role.", "07_promote_marvin_to_manager.sql", destructive=True, requires=("create_marvin",), short_label="Enable sales-manager"),
        _action("disable_manager", "Disable sales-manager policy", "Revokes APP_SALES_MANAGER from Marvin.", "11_disable_manager_policy.sql", destructive=True, requires=("create_marvin",), short_label="Disable sales-manager"),
        _action("validate_as_marvin", "Run Marvin validation queries", "Runs the same validation SQL as Marvin and shows the rows, context, and active data roles.", "06_validation_queries.sql", database_user="MARVIN", requires=("create_marvin",), short_label="Run validation"),
        _action("reset_lab", "Reset all lab database objects", "Drops only the APPLAB schema, Marvin, and Deep Sec roles. Rebuild the lab afterward.", "reset_lab.sql", destructive=True, resets_setup=True, short_label="Reset all"),
    )
}

for action in ACTIONS.values():
    action["required_titles"] = [ACTIONS[key]["title"] for key in action["requires"]]


def _sqlplus_input(password: str, action: dict) -> str:
    quoted_password = password.replace('"', '""')
    lines = ["whenever oserror exit failure", f'connect {action["database_user"].lower()}/"{quoted_password}"@{settings.dsn}']
    for script in action["scripts"]:
        command = f"@{script['path']}"
        if action["needs_password"]:
            command += f' "{quoted_password}"'
        lines.append(command)
    lines.append("exit")
    return "\n".join(lines) + "\n"


def _run_action(password: str, action: dict) -> dict:
    result = subprocess.run(
        ["sqlplus", "-s", "-L", "/nolog"],
        input=_sqlplus_input(password, action),
        text=True,
        capture_output=True,
        timeout=120,
        env={**os.environ, "TNS_ADMIN": settings.wallet_location},
        check=False,
    )
    output = (result.stdout + result.stderr).strip() or "SQL*Plus completed without additional output."
    return {"exit_code": result.returncode, "output": output}


def _run_vibe(prompt: str) -> dict:
    """Run Vibe only against the live, Terraform-installed customer application."""
    if not settings.vibe_executable.is_file() or not os.access(settings.vibe_executable, os.X_OK):
        raise RuntimeError("Vibe is not installed yet. Check the Deep Sec bootstrap log.")
    if not settings.vibe_project_root.is_dir():
        raise RuntimeError("The Deep Sec Customer Sales application directory is unavailable.")

    result = subprocess.run(
        [str(settings.vibe_executable), "--project", str(settings.vibe_project_root), "run", "-y", prompt],
        cwd=settings.vibe_project_root,
        text=True,
        capture_output=True,
        timeout=VIBE_TIMEOUT_SECONDS,
        env={**os.environ, "HOME": "/home/opc"},
        check=False,
    )
    output = (result.stdout + result.stderr).strip() or "Vibe completed without additional output."
    return {
        "exit_code": result.returncode,
        "output": output,
        "applied": result.returncode == 0 and "Applied:" in output,
    }


def _run_vibe_reset() -> dict:
    """Reset the live Customer Sales application to its known-good copy."""
    if not settings.vibe_executable.is_file() or not os.access(settings.vibe_executable, os.X_OK):
        raise RuntimeError("Vibe is not installed yet. Check the Deep Sec bootstrap log.")
    if not settings.vibe_project_root.is_dir():
        raise RuntimeError("The Deep Sec Customer Sales application directory is unavailable.")

    result = subprocess.run(
        [str(settings.vibe_executable), "--project", str(settings.vibe_project_root), "reset", "-y"],
        cwd=settings.vibe_project_root,
        text=True,
        capture_output=True,
        timeout=VIBE_TIMEOUT_SECONDS,
        env={**os.environ, "HOME": "/home/opc"},
        check=False,
    )
    output = (result.stdout + result.stderr).strip() or "Vibe reset completed without additional output."
    return {"exit_code": result.returncode, "output": output}


def _reload_customer_sales() -> dict:
    """Reload the live application after Vibe modifies its checked-in source."""
    result = subprocess.run(
        ["/usr/bin/sudo", "-n", "/usr/bin/systemctl", "reload", "deep-sec-customer-sales.service"],
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )
    output = (result.stdout + result.stderr).strip() or "Customer Sales application reloaded."
    return {"exit_code": result.returncode, "output": output}


@app.get("/")
def index():
    if current_user.is_authenticated:
        return redirect(url_for("console"))
    return render_template("login.html")


@app.get("/console")
@login_required
def console():
    completed_actions = _completed_actions() | _database_completed_actions()
    action_outputs = _action_outputs()
    customer_sales_url = f"{request.scheme}://{request.host.split(':', 1)[0]}:7777/"
    actions = [
        {
            **action,
            "locked": False,
            "output": action_outputs.get(action["key"]),
            "link_url": customer_sales_url if action["key"] == "customer_sales" else action["link_url"],
        }
        for action in ACTIONS.values()
    ]
    return render_template(
        "console.html",
        actions=actions,
        completed_actions=sorted(completed_actions),
    )


@app.get("/vibe")
@login_required
def vibe():
    completed_actions = _completed_actions() | _database_completed_actions()
    return render_template(
        "vibe.html",
        prompts=VIBE_PROMPTS,
        ready="create_marvin" in completed_actions,
    )


@app.post("/api/login")
def login():
    password = str((request.get_json(silent=True) or {}).get("password", ""))
    if not password:
        return jsonify(error="Enter the ADMIN database password."), 400
    try:
        database_user = verify_admin(settings, password)
    except Exception as exc:
        # Keep the browser response generic, but preserve the Oracle exception
        # and traceback in the protected systemd journal for lab diagnostics.
        # The submitted password is never included in this log message.
        app.logger.exception("ADMIN console sign-in failed: %s", exc)
        return jsonify(error="Database sign-in failed. Verify the ADMIN password."), 401
    login_id = secrets.token_urlsafe(32)
    with _logins_lock:
        _logins[login_id] = {
            "password": password,
            "expires_at": time.monotonic() + LOGIN_TTL_SECONDS,
            "completed_actions": set(),
            "action_outputs": {},
        }
    login_user(AdminUser(login_id))
    return jsonify(database_user=database_user)


@app.post("/api/logout")
def logout():
    with _logins_lock:
        _logins.pop(current_user.get_id(), None)
    logout_user()
    return jsonify(status="signed out")


@app.get("/api/state")
@login_required
def state():
    try:
        return jsonify(available=True, **lab_state(settings, _admin_password()))
    except Exception as exc:
        # Before Create MARVIN this is expected rather than an application error.
        # Return a successful, explicit state so the browser console is not filled
        # with a misleading 409 error during the guided setup sequence. The real
        # Oracle exception remains visible at debug level in journald.
        app.logger.debug("MARVIN state is not available yet: %s", exc)
        return jsonify(
            available=False,
            message="Marvin's current state will appear after Create MARVIN completes.",
        )


@app.post("/api/actions/<action_key>")
@login_required
def action(action_key: str):
    selected_action = ACTIONS.get(action_key)
    if not selected_action:
        return jsonify(error="Unknown administrator action."), 404
    if selected_action.get("link_step"):
        completed_actions = _record_completed_action(selected_action)
        _record_action_output(action_key, "Marked as viewed.")
        return jsonify(action=selected_action["title"], completed_actions=completed_actions, output="Marked as viewed.")
    try:
        result = _run_action(_admin_password(), selected_action)
    except subprocess.TimeoutExpired:
        return jsonify(error="SQL*Plus did not complete within two minutes."), 504
    except Exception:
        app.logger.exception("Administrator action failed before SQL*Plus completed: %s", action_key)
        return jsonify(error="Could not run the fixed administrator action. Check the server log."), 502
    status = 200 if result["exit_code"] == 0 else 422
    _record_action_output(action_key, result["output"])
    completed_actions = _record_completed_action(selected_action) if status == 200 else sorted(
        _completed_actions() | _database_completed_actions()
    )
    return jsonify(action=selected_action["title"], completed_actions=completed_actions, **result), status


@app.post("/api/vibe/reset")
@login_required
def reset_vibe():
    if "create_marvin" not in (_completed_actions() | _database_completed_actions()):
        return jsonify(error="Complete Create MARVIN before using Vibe Coding."), 409
    try:
        result = _run_vibe_reset()
    except subprocess.TimeoutExpired:
        return jsonify(error="Reset did not complete within six minutes."), 504
    except Exception as exc:
        app.logger.exception("Vibe reset could not start: %s", exc)
        return jsonify(error=str(exc)), 502

    if result["exit_code"] != 0:
        return jsonify(**result), 502

    try:
        reload_result = _reload_customer_sales()
    except subprocess.TimeoutExpired:
        reload_result = {"exit_code": 1, "output": "The reset was applied, but the Customer Sales reload timed out."}
    if reload_result["exit_code"] != 0:
        return jsonify(reload=reload_result, **result), 502
    return jsonify(reload=reload_result, **result)


@app.post("/api/vibe/<prompt_key>")
@login_required
def run_vibe(prompt_key: str):
    if "create_marvin" not in (_completed_actions() | _database_completed_actions()):
        return jsonify(error="Complete Create MARVIN before using Vibe Coding."), 409

    if prompt_key == "custom":
        prompt = str((request.get_json(silent=True) or {}).get("prompt", "")).strip()
        if not prompt:
            return jsonify(error="Enter a custom Vibe request."), 400
        if len(prompt) > 4000 or "\x00" in prompt:
            return jsonify(error="The custom Vibe request must be plain text of 4,000 characters or fewer."), 400
    else:
        selected_prompt = VIBE_PROMPTS.get(prompt_key)
        if not selected_prompt:
            return jsonify(error="Unknown Vibe request."), 404
        prompt = selected_prompt["prompt"]

    try:
        result = _run_vibe(prompt)
    except subprocess.TimeoutExpired:
        return jsonify(error="Vibe did not complete within six minutes."), 504
    except Exception as exc:
        app.logger.exception("Vibe Coding could not start: %s", exc)
        return jsonify(error=str(exc)), 502

    if result["exit_code"] != 0:
        return jsonify(prompt=prompt, **result), 502

    reload_result = None
    if result["applied"]:
        try:
            reload_result = _reload_customer_sales()
        except subprocess.TimeoutExpired:
            reload_result = {"exit_code": 1, "output": "The change was applied, but the Customer Sales reload timed out."}
        if reload_result["exit_code"] != 0:
            return jsonify(prompt=prompt, reload=reload_result, **result), 502
    return jsonify(prompt=prompt, reload=reload_result, **result)


@app.get("/healthz")
def healthcheck():
    return jsonify(status="ok")


if __name__ == "__main__":
    app.run(host=settings.host, port=settings.port, debug=False)
