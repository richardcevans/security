"""Fixed-action administrator console for the Deep Sec training environment."""

import logging
import os
from pathlib import Path
import re
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
from admin_db import completed_setup_actions, lab_state, validation_comparison, verify_admin

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
_vibe_lock = Lock()


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
    custom_grant_step: bool = False,
    internal_secret_script: Optional[str] = None,
    link_url: Optional[str] = None,
    short_label: Optional[str] = None,
    expect: Optional[str] = None,
) -> dict:
    resolved = []
    for script in scripts:
        path = Path(settings.database_dir, script).resolve()
        if path.parent != Path(settings.database_dir).resolve() or not path.is_file():
            raise RuntimeError(f"Required lab script is missing: {script}")
        display_path = path.with_suffix(".display.sql")
        if display_path.is_file() and display_path.parent == Path(settings.database_dir).resolve():
            display_sql = display_path.read_text(encoding="utf-8")
        else:
            display_sql = path.read_text(encoding="utf-8")
        resolved.append({"name": script, "path": path, "sql": display_sql})
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
        "custom_grant_step": custom_grant_step,
        "internal_secret_script": internal_secret_script,
        "link_url": link_url,
        "short_label": short_label or title,
        "expect": expect,
    }


# This is the complete allow-list. Requests can select only these checked-in,
# visible scripts—never a browser-provided SQL statement, path, or command.
ACTIONS = {
    action["key"]: action
    for action in (
        _action("setup_database", "Set up database", "Creates the APPLAB schema and loads the 22 sample customer rows used throughout the lab.", "create_schema.sql", "load_sample_data.sql", destructive=True, internal_secret_script="create_schema.sql", short_label="Set up database", expect="The APPLAB schema is created and 22 customer rows are loaded. Marvin doesn't exist yet, so his Oracle result above stays empty until Create MARVIN runs."),
        _action("create_roles", "Create data roles and grant definitions", "Creates the full-access, employee, and manager data roles and the full-access data grant.", "create_data_roles.sql", destructive=True, requires=("setup_database",), short_label="Create roles", expect="Three data roles are created: APP_FULL_ACCESS, APP_SALES_EMPLOYEE, and APP_SALES_MANAGER. No visible change yet; Marvin still doesn't exist."),
        _action("create_marvin", "Create MARVIN", "Creates the local end user and grants the full-access role.", "create_lab_users.sql", destructive=True, needs_password=True, requires=("create_roles",), short_label="Create MARVIN", expect="Marvin is created and immediately granted APP_FULL_ACCESS. Marvin's Oracle result above should now show APP_FULL_ACCESS, 22 rows, and both sensitive columns."),
        _action("create_emma", "Create EMMA", "Creates Emma as a fixed comparison user, always APP_SALES_EMPLOYEE, so students can see a stable employee-level view alongside Marvin's changing access.", "create_emma_user.sql", destructive=True, needs_password=True, requires=("create_roles",), short_label="Create EMMA", expect="Emma is created and granted APP_SALES_EMPLOYEE, fixed for the rest of the lab. Sign in as Emma in Customer Sales at any point to see her own 6 WEST rows, with Credit Limit and Sensitive Identifier both Not authorized."),
        _action("enable_full_access", "Enable full access", "Grants APP_FULL_ACCESS so Marvin can request every row and displayed column.", "enable_full_access.sql", destructive=True, requires=("create_marvin",), short_label="Enable full access", expect="Marvin's Oracle result shows APP_FULL_ACCESS, 22 rows, and both sensitive columns. This is his starting state, so nothing changes if you run this again."),
        _action("customer_sales", "Customer Sales", "Navigate to the Oracle Customer Sales application to view Marvin's current access.", requires=("enable_full_access",), link_step=True, short_label="Customer Sales", expect="Sign in as Marvin and select Customer Report. You should see 22 rows, including Apex Treasury, with Credit Limit and Sensitive Identifier both visible."),
        _action("disable_full_access", "Disable full access", "Revokes APP_FULL_ACCESS from Marvin.", "disable_full_access.sql", destructive=True, requires=("create_marvin",), short_label="Disable full access", expect="APP_FULL_ACCESS is revoked. Marvin's Oracle result shows no active data roles until you enable a policy below."),
        _action("enable_employee", "Enable sales-employee policy", "Replaces the full-access role with APP_SALES_EMPLOYEE.", "implement_deep_sec_policies.sql", destructive=True, requires=("create_marvin",), short_label="Enable sales-employee", expect="Marvin's Oracle result changes to APP_SALES_EMPLOYEE. In Customer Sales, Customer Report should now show 3 rows, with Credit Limit and Sensitive Identifier both reading Not authorized."),
        _action("disable_employee", "Disable sales-employee policy", "Revokes APP_SALES_EMPLOYEE from Marvin.", "disable_employee_policy.sql", destructive=True, requires=("create_marvin",), short_label="Disable sales-employee", expect="APP_SALES_EMPLOYEE is revoked. Run Enable sales-employee policy again, or continue to the manager steps below, to give Marvin a role again."),
        _action("create_manager_context", "Create manager hierarchy", "Creates the sales-rep hierarchy and synchronizes each customer's manager attribute for Oracle's manager data grant.", "create_sales_reps.sql", "create_manager_context.sql", destructive=True, requires=("create_marvin",), short_label="Manager hierarchy", expect="The SALES_REPS hierarchy is created and EMMA's six WEST customer rows are assigned to MARVIN. This prepares the manager policy; Marvin's access does not change yet."),
        _action("enable_manager", "Enable sales-manager policy", "Adds APP_SALES_MANAGER while Marvin retains the employee role.", "promote_marvin_to_manager.sql", destructive=True, requires=("create_marvin",), short_label="Enable sales-manager", expect="Marvin's Oracle result adds APP_SALES_MANAGER alongside APP_SALES_EMPLOYEE. In Customer Sales, sign out and back in, then Customer Report should show 9 rows with Credit Limit visible and Sensitive Identifier still Not authorized."),
        _action("disable_manager", "Disable sales-manager policy", "Revokes APP_SALES_MANAGER from Marvin.", "disable_manager_policy.sql", destructive=True, requires=("create_marvin",), short_label="Disable sales-manager", expect="APP_SALES_MANAGER is revoked. Marvin drops back to APP_SALES_EMPLOYEE if that role is still active."),
        _action("customize_manager_grant", "Customize the manager grant", "Choose exactly which columns Marvin's manager role can see, then apply the change directly to Oracle. sensitive_identifier is never offered, so it remains off-limits.", requires=("create_manager_context", "enable_manager"), custom_grant_step=True, short_label="Customize grant", expect="The grant updates immediately. Reload Customer Report in Customer Sales as Marvin, manager, to see the columns you kept or removed."),
        _action("validate_as_marvin", "Run Marvin validation queries", "Runs the same validation SQL as Marvin and shows the rows, context, and active data roles.", "validation_queries.sql", database_user="MARVIN", requires=("create_marvin",), short_label="Run validation", expect="The output shows exactly what Marvin's own session sees right now: his rows, end-user context, and active data roles."),
        _action("reset_lab", "Reset all lab database objects", "Drops only the APPLAB schema, Marvin, and Deep Sec roles. Rebuild the lab afterward.", "reset_lab.sql", destructive=True, resets_setup=True, short_label="Reset all", expect="The APPLAB schema, Marvin, and all Deep Sec roles are dropped. Run Set up database to start over from the beginning."),
    )
}

MANAGER_GRANT_REQUIRED_COLUMNS = ("customer_id",)
MANAGER_GRANT_OPTIONAL_COLUMNS = ("customer_name", "region", "sales_rep", "revenue", "credit_limit")
MANAGER_GRANT_ALL_COLUMNS = MANAGER_GRANT_REQUIRED_COLUMNS + MANAGER_GRANT_OPTIONAL_COLUMNS


def _build_manager_grant_sql(selected_optional: list) -> str:
    """Build the manager data grant from a whitelisted column selection only."""
    invalid = set(selected_optional) - set(MANAGER_GRANT_OPTIONAL_COLUMNS)
    if invalid:
        raise ValueError(f"Unknown column(s): {', '.join(sorted(invalid))}")
    ordered = [
        column
        for column in MANAGER_GRANT_ALL_COLUMNS
        if column in MANAGER_GRANT_REQUIRED_COLUMNS or column in selected_optional
    ]
    return (
        "create or replace data grant APPLAB.marvin_manager_customer_access\n"
        f"  as select ({', '.join(ordered)})\n"
        "  on APPLAB.customers\n"
        "  where upper(sales_rep) = upper(ora_end_user_context.username)\n"
        "     or instr(','||ora_end_user_context.APPLAB.MGR_CTX.reports||',', ','||upper(sales_rep)||',') > 0\n"
        "  to app_sales_manager;"
    )


def _run_manager_grant_sql(password: str, sql_statement: str) -> dict:
    """Run the server-generated manager grant as ADMIN through SQL*Plus."""
    quoted_password = password.replace('"', '""')
    script = f'whenever oserror exit failure\nconnect admin/"{quoted_password}"@{settings.dsn}\n{sql_statement}\nexit\n'
    result = subprocess.run(
        ["sqlplus", "-s", "-L", "/nolog"],
        input=script,
        text=True,
        capture_output=True,
        timeout=120,
        env={**os.environ, "TNS_ADMIN": settings.wallet_location},
        check=False,
    )
    output = (result.stdout + result.stderr).strip() or "SQL*Plus completed without additional output."
    return {"exit_code": result.returncode, "output": output}

for action in ACTIONS.values():
    action["required_titles"] = [ACTIONS[key]["title"] for key in action["requires"]]

STEPS = (
    {"key": "setup_database", "title": "Set up database", "action_keys": ("setup_database",), "next_hint": "Run Create roles to build the data roles and grants Marvin will use throughout the lab."},
    {"key": "create_roles", "title": "Create roles", "action_keys": ("create_roles",), "next_hint": "Run Create MARVIN to create the end user and grant his starting role."},
    {"key": "create_users", "title": "Create users", "action_keys": ("create_marvin", "create_emma"), "next_hint": "Continue to Full access to confirm Marvin's starting state, or go straight to Customer Sales."},
    {"key": "full_access", "title": "Full access", "action_keys": ("enable_full_access", "disable_full_access"), "next_hint": "Open Customer Sales to see this access from Marvin's side."},
    {"key": "customer_sales", "title": "Customer Sales", "action_keys": ("customer_sales",), "next_hint": "Return here and run Employee policy to restrict Marvin's access."},
    {"key": "employee_policy", "title": "Employee policy", "action_keys": ("enable_employee", "disable_employee"), "next_hint": "Run Manager hierarchy to prepare the data Marvin's manager promotion depends on."},
    {"key": "create_manager_context", "title": "Manager hierarchy", "action_keys": ("create_manager_context",), "next_hint": "Run Manager policy to actually promote Marvin and see his access change."},
    {"key": "manager_policy", "title": "Manager policy", "action_keys": ("enable_manager", "disable_manager"), "next_hint": "Try Customize grant to change which columns Marvin's manager role can see, or open Vibe Coding from the header navigation to try expanding his access with AI-generated code."},
    {"key": "customize_manager_grant", "title": "Customize grant", "action_keys": ("customize_manager_grant",), "next_hint": "Rerun Manager policy at any point to restore the original six-column grant, then continue to Run validation."},
    {"key": "validate_as_marvin", "title": "Run validation", "action_keys": ("validate_as_marvin",), "next_hint": "Use Reset all if you want to start the whole lab over from scratch."},
    {"key": "reset_lab", "title": "Reset all", "action_keys": ("reset_lab",), "next_hint": "Run Set up database to begin again."},
)


def _sqlplus_input(password: str, action: dict) -> str:
    quoted_password = password.replace('"', '""')
    lines = ["whenever oserror exit failure", f'connect {action["database_user"].lower()}/"{quoted_password}"@{settings.dsn}']
    for script in action["scripts"]:
        command = f"@{script['path']}"
        if script["name"] == action.get("internal_secret_script"):
            internal_secret = secrets.token_urlsafe(24).replace('"', '')
            command += f' "{internal_secret}"'
        elif action["needs_password"]:
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


def _parse_vibe_output(output: str) -> dict:
    """Extract the stable, learner-facing fields emitted by the Vibe CLI."""
    def _match(label: str) -> str:
        match = re.search(rf"^{re.escape(label)}\s*:\s*(.+)$", output, re.MULTILINE)
        return match.group(1).strip() if match else ""

    summary_match = re.search(r"OCI GenAI summary:\s*\n\n(.*?)\n\nGenAI calls:", output, re.DOTALL)
    files_match = re.search(r"Applied:\s*\n(.*?)(?:\n\nUse 'vibe|\Z)", output, re.DOTALL)
    files = [line.strip() for line in files_match.group(1).splitlines() if line.strip()] if files_match else []
    return {
        "target_project": _match("Project"),
        "model": _match("Model"),
        "region": _match("Region"),
        "genai_summary": summary_match.group(1).strip() if summary_match else "",
        "files_changed": files,
    }


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
        **_parse_vibe_output(output),
    }


def _run_vibe_reset() -> dict:
    """Reset the live Customer Sales application to its original copy."""
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
    return {"exit_code": result.returncode, "output": output, **_parse_vibe_output(output)}


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
    actions = {
        key: {
            **action,
            "locked": False,
            "output": action_outputs.get(action["key"]),
            "link_url": customer_sales_url if action["key"] == "customer_sales" else action["link_url"],
        }
        for key, action in ACTIONS.items()
    }
    steps = [
        {
            **step,
            "actions": [actions[key] for key in step["action_keys"]],
            "next_step_key": STEPS[index + 1]["key"] if index + 1 < len(STEPS) else STEPS[0]["key"],
        }
        for index, step in enumerate(STEPS)
    ]
    return render_template(
        "console.html",
        actions=actions,
        steps=steps,
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


@app.get("/api/validation-comparison")
@login_required
def validation_comparison_state():
    try:
        return jsonify(available=True, **validation_comparison(settings, _admin_password()))
    except Exception as exc:
        app.logger.debug("Validation comparison is not available yet: %s", exc)
        return jsonify(available=False, message="Create the comparison users and data roles first."), 200


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
    if selected_action.get("custom_grant_step"):
        return jsonify(error="Use the column choices and Apply this grant button."), 400
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


@app.post("/api/manager-grant/preview")
@login_required
def preview_manager_grant():
    payload = request.get_json(silent=True) or {}
    selected = payload.get("columns", [])
    if not isinstance(selected, list) or not all(isinstance(column, str) for column in selected):
        return jsonify(error="Invalid column selection."), 400
    try:
        return jsonify(sql=_build_manager_grant_sql(selected))
    except ValueError as exc:
        return jsonify(error=str(exc)), 400


@app.post("/api/manager-grant/apply")
@login_required
def apply_manager_grant():
    payload = request.get_json(silent=True) or {}
    selected = payload.get("columns", [])
    if not isinstance(selected, list) or not all(isinstance(column, str) for column in selected):
        return jsonify(error="Invalid column selection."), 400
    try:
        sql = _build_manager_grant_sql(selected)
    except ValueError as exc:
        return jsonify(error=str(exc)), 400
    completed_actions = _completed_actions() | _database_completed_actions()
    if not {"create_manager_context", "enable_manager"}.issubset(completed_actions):
        return jsonify(error="Run Manager hierarchy and Manager policy before customizing this grant."), 409
    try:
        result = _run_manager_grant_sql(_admin_password(), sql)
    except subprocess.TimeoutExpired:
        return jsonify(error="The grant update did not complete within two minutes."), 504
    except Exception:
        app.logger.exception("Manager grant customization failed before SQL*Plus completed.")
        return jsonify(error="Could not apply the customized grant. Check the server log."), 502
    status = 200 if result["exit_code"] == 0 else 422
    return jsonify(sql=sql, **result), status


@app.post("/api/vibe/reset")
@login_required
def reset_vibe():
    if "create_marvin" not in (_completed_actions() | _database_completed_actions()):
        return jsonify(error="Complete Create MARVIN before using Vibe Coding."), 409
    if not _vibe_lock.acquire(blocking=False):
        return jsonify(error="Another Vibe request is already running. Wait for it to finish."), 409
    try:
        result = _run_vibe_reset()
        if result["exit_code"] != 0:
            return jsonify(**result), 502
        try:
            reload_result = _reload_customer_sales()
        except subprocess.TimeoutExpired:
            reload_result = {"exit_code": 1, "output": "The reset was applied, but the Customer Sales reload timed out."}
        if reload_result["exit_code"] != 0:
            return jsonify(reload=reload_result, **result), 502
        return jsonify(reload=reload_result, **result)
    except subprocess.TimeoutExpired:
        return jsonify(error="Reset did not complete within six minutes."), 504
    except Exception as exc:
        app.logger.exception("Vibe reset could not start: %s", exc)
        return jsonify(error=str(exc)), 502
    finally:
        _vibe_lock.release()


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

    if not _vibe_lock.acquire(blocking=False):
        return jsonify(error="Another Vibe request is already running. Wait for it to finish."), 409
    try:
        result = _run_vibe(prompt)
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
    except subprocess.TimeoutExpired:
        return jsonify(error="Vibe did not complete within six minutes."), 504
    except Exception as exc:
        app.logger.exception("Vibe Coding could not start: %s", exc)
        return jsonify(error=str(exc)), 502
    finally:
        _vibe_lock.release()


@app.get("/healthz")
def healthcheck():
    return jsonify(status="ok")


if __name__ == "__main__":
    app.run(host=settings.host, port=settings.port, debug=False)
