import os
from decimal import Decimal
from pathlib import Path


class WebHrDatabase(object):
    def __init__(self):
        self.mode = os.getenv("WEB_HR_DB_MODE", "mock").lower()
        self.tns_alias = os.getenv("WEB_HR_TNS_ALIAS", "freepdb1")

    def employees_for_user(self, user):
        if self.mode == "oracledb":
            return self._employees_oracle(user)
        return self._employees_mock(user)

    def visible_summary(self, user):
        if self.mode == "oracledb":
            return self._visible_summary_oracle(user)
        return self._visible_summary_mock(user)

    def update_employee_field(self, user, employee_id, field_name, value):
        if self.mode == "oracledb":
            return self._update_employee_field_oracle(user, employee_id, field_name, value)
        return self._update_employee_field_mock(user, employee_id, field_name, value)

    def audit_events(self, user):
        if self.mode == "oracledb":
            return self._audit_events_oracle()
        return {
            "mode": "mock",
            "events": [],
            "note": "Audit events are available in oracledb mode after running 03_configure_auditing.sh.",
        }

    def debug_tokens_for_user(self, user):
        return {
            "mode": self.mode,
            "auth_mode": "local-end-user",
            "message": "This app does not use Entra ID, OAuth, application tokens, or OBO exchange.",
            "database_identity": user["username"],
        }

    def debug_context_for_user(self, user):
        if self.mode != "oracledb":
            return {
                "mode": self.mode,
                "message": "Database context diagnostics are available in oracledb mode.",
            }

        identity_sql = """
            SELECT ORA_END_USER_CONTEXT.username AS username,
                   SYS_CONTEXT('USERENV','AUTHENTICATED_IDENTITY') AS authenticated_identity,
                   SYS_CONTEXT('USERENV','ENTERPRISE_IDENTITY') AS enterprise_identity,
                   SYS_CONTEXT('USERENV','AUTHENTICATION_METHOD') AS auth_method,
                   SYS_CONTEXT('USERENV','CURRENT_USER') AS current_user
              FROM dual
        """
        roles_sql = """
            SELECT role_name
              FROM v$end_user_data_role
             ORDER BY role_name
        """
        identity = self._run_as_end_user(user, identity_sql, fetch="one")
        roles = self._run_as_end_user(user, roles_sql, fetch="rows")
        payload = {
            "mode": "oracledb",
            "identity": identity,
            "active_data_roles": roles,
        }
        print("")
        print("========================================================================")
        print("Database context diagnostics")
        print("========================================================================")
        print(__import__("json").dumps(payload, indent=2, sort_keys=True))
        print("========================================================================")
        print("")
        return payload

    def preflight(self, user):
        checks = []

        def add(name, status, detail, evidence=None):
            check = {
                "name": name,
                "status": status,
                "detail": detail,
            }
            if evidence is not None:
                check["evidence"] = evidence
            checks.append(check)

        def run(name, fn):
            try:
                detail, evidence = fn()
                add(name, "pass", detail, evidence)
            except Exception as exc:
                add(name, "fail", str(exc))

        required_env = [
            "WEB_HR_TNS_ALIAS",
            user.get("password_env", ""),
        ]
        missing_env = [name for name in required_env if not os.getenv(name)]
        if missing_env:
            add("Required environment", "fail", "Missing {0}.".format(", ".join(missing_env)))
        else:
            add(
                "Required environment",
                "pass",
                "Required local end-user database settings are present.",
                {
                    "tns_alias": self.tns_alias,
                    "database_user": user["username"],
                    "password_env": user.get("password_env"),
                },
            )

        config_dir = os.getenv("WEB_HR_CONFIG_DIR") or os.getenv("TNS_ADMIN")
        wallet_location = os.getenv("WEB_HR_WALLET_LOCATION")
        if config_dir:
            status = "pass" if os.path.isdir(config_dir) else "fail"
            add("Oracle network config", status, "Config directory: {0}".format(config_dir))
        else:
            add("Oracle network config", "warn", "WEB_HR_CONFIG_DIR/TNS_ADMIN is not set; relying on default Oracle lookup.")
        if wallet_location:
            status = "pass" if os.path.isdir(wallet_location) else "fail"
            add("Client wallet", status, "Wallet directory: {0}".format(wallet_location))
        else:
            add("Client wallet", "warn", "WEB_HR_WALLET_LOCATION is not set; the TNS alias must resolve wallet settings.")

        if self.mode != "oracledb":
            add("Database mode", "warn", "WEB_HR_DB_MODE is {0}; database checks are skipped.".format(self.mode))
            return {
                "mode": self.mode,
                "checks": checks,
                "summary": _preflight_summary(checks),
            }

        def driver_check():
            import oracledb
            return (
                "python-oracledb is available for direct end-user authentication.",
                {"oracledb_version": getattr(oracledb, "__version__", "unknown")},
            )

        run("Python driver", driver_check)

        def connection_check():
            row = self._run_as_end_user(
                user,
                """
                SELECT SYS_CONTEXT('USERENV','AUTHENTICATED_IDENTITY') AS authenticated_identity,
                       SYS_CONTEXT('USERENV','AUTHENTICATION_METHOD') AS auth_method,
                       ORA_END_USER_CONTEXT.username AS end_user_name,
                       SYS_CONTEXT('USERENV','CURRENT_USER') AS current_user
                  FROM dual
                """,
                fetch="one",
            )
            return "Selected end user can connect directly to Oracle Database.", row

        run("End-user connection", connection_check)

        def role_check():
            roles = self._run_as_end_user(
                user,
                "SELECT role_name FROM v$end_user_data_role ORDER BY role_name",
                fetch="rows",
            )
            return "Database activated Deep Data Security data roles for the authenticated end user.", {
                "active_data_roles": [row.get("ROLE_NAME") for row in roles],
            }

        run("Data role activation", role_check)

        def audit_check():
            result = self._run_app_query(
                "SELECT COUNT(*) AS sample_rows FROM unified_audit_trail WHERE ROWNUM <= 1",
                fetch="one",
            )
            return "Configured admin user can read Unified Audit Trail.", result

        run("Audit visibility", audit_check)

        return {
            "mode": "oracledb",
            "checks": checks,
            "summary": _preflight_summary(checks),
        }

    def _employees_mock(self, user):
        username = user["username"].lower()
        is_manager = "HRAPP_MANAGERS" in user.get("roles", [])
        rows = [
            {"employee_id": 1, "first_name": "Grace", "last_name": "Young", "job_code": "CEO", "phone_number": "555-100-0001", "salary": 235000, "ssn": "111-11-1111", "department_id": None, "user_name": "grace", "manager_id": None},
            {"employee_id": 2, "first_name": "Marvin", "last_name": "Morgan", "job_code": "SWE_MGR", "phone_number": "555-100-0002", "salary": 175000, "ssn": "222-22-2222", "department_id": 1, "user_name": "marvin", "manager_id": 1},
            {"employee_id": 3, "first_name": "Emma", "last_name": "Baker", "job_code": "SWE2", "phone_number": "555-100-0003", "salary": 120000, "ssn": "333-33-3333", "department_id": 1, "user_name": "emma", "manager_id": 2},
            {"employee_id": 4, "first_name": "Charlie", "last_name": "Davis", "job_code": "SWE1", "phone_number": "555-100-0004", "salary": 95000, "ssn": "", "department_id": 1, "user_name": "charlie", "manager_id": 2},
            {"employee_id": 5, "first_name": "Dana", "last_name": "Lee", "job_code": "SWE3", "phone_number": "555-100-0005", "salary": 130000, "ssn": "", "department_id": 1, "user_name": "dana", "manager_id": 2},
        ]
        if "emma" in username:
            rows = [rows[2]]
        elif not is_manager:
            rows = rows[:1]
        else:
            rows = rows[1:]
        for row in rows:
            own_row = row["user_name"] == username
            if not own_row:
                row["ssn"] = ""
            row["can_update_first_name"] = own_row or (is_manager and row["user_name"] != "marvin")
            row["can_update_phone_number"] = own_row
            row["can_update_salary"] = is_manager and row["user_name"] != "marvin"
            row["can_update_department_id"] = is_manager and row["user_name"] != "marvin"
        return {
            "mode": "mock",
            "user": user["username"],
            "elevated": False,
            "rows": rows,
            "request_context": {
                "database_session": "mock",
                "end_user": user["username"],
                "active_data_roles": user.get("roles", []),
            },
            "note": "Normal request. Mock mode simulates the password-based end-user data grants from end-user-data-grants.md.",
        }

    def _update_employee_field_mock(self, user, employee_id, field_name, value):
        payload = self._employees_mock(user)
        payload["updated"] = {
            "employee_id": employee_id,
            "field": field_name,
            "value": value,
            "row_count": 1,
        }
        payload["note"] = "Mock mode accepted the edit. Oracle mode enforces it with Deep Data Security."
        return payload

    def _visible_summary_mock(self, user):
        payload = self._employees_mock(user)
        return {
            "mode": "mock",
            "user": user["username"],
            "elevated": False,
            "data_roles": user.get("roles", []),
            "visible_rows": len(payload["rows"]),
            "average_visible_salary": round(
                sum(float(row["salary"]) for row in payload["rows"]) / len(payload["rows"]),
                2,
            ) if payload["rows"] else None,
            "note": "Direct end-user request. No application elevation role is used.",
        }

    def _employees_oracle(self, user):
        sql = """
            SELECT emp.employee_id,
                   emp.first_name,
                   emp.last_name,
                   emp.job_code,
                   emp.phone_number,
                   emp.salary,
                   DECODE(ORA_IS_COLUMN_AUTHORIZED(ssn), false, '', true, ssn) AS ssn,
                   emp.department_id,
                   emp.user_name,
                   emp.manager_id,
                   ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', first_name) AS can_update_first_name,
                   ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', phone_number) AS can_update_phone_number,
                   ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', salary) AS can_update_salary,
                   ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', department_id) AS can_update_department_id
              FROM hr.employees emp
             ORDER BY employee_id
        """
        result = self._run_as_end_user(user, sql, fetch="rows", include_context=True)
        return {
            "mode": "oracledb",
            "user": user["username"],
            "elevated": False,
            "rows": result["data"],
            "request_context": result["request_context"],
            "note": "Oracle enforced visible rows and columns using the authenticated end user's active data roles.",
        }

    def _update_employee_field_oracle(self, user, employee_id, field_name, value):
        columns = {
            "first_name": "first_name",
            "phone_number": "phone_number",
            "salary": "salary",
            "department_id": "department_id",
        }
        column = columns.get(field_name)
        if not column:
            raise ValueError("Field {0} is not editable.".format(field_name))

        if column in ("salary", "department_id") and value == "":
            value = None
        if column in ("salary", "department_id") and value is not None:
            try:
                value = float(value) if column == "salary" else int(value)
            except ValueError:
                raise ValueError("{0} must be numeric.".format(field_name))

        current_row = self._visible_row_for_employee(user, employee_id)
        match_column, match_value = self._update_match_predicate(user, current_row, column)
        sql = "UPDATE hr.employees SET {0} = :value WHERE {1} = :match_value".format(column, match_column)
        row_count = self._run_as_end_user(
            user,
            sql,
            fetch="rowcount",
            params={"value": value, "match_value": match_value},
        )
        payload = self._employees_oracle(user)
        payload["updated"] = {
            "employee_id": employee_id,
            "field": field_name,
            "match_column": match_column,
            "row_count": row_count,
        }
        if row_count == 0:
            payload["note"] = "No rows were updated. Deep Data Security did not authorize that edit for the current end user."
        return payload

    def _visible_row_for_employee(self, user, employee_id):
        payload = self._employees_oracle(user)
        for row in payload.get("rows", []):
            if row.get("EMPLOYEE_ID") == employee_id:
                return row
        raise ValueError("Employee {0} is not visible to {1}.".format(employee_id, user["username"]))

    def _update_match_predicate(self, user, row, column):
        if column != "first_name":
            return "first_name", row.get("FIRST_NAME")

        own_row = str(row.get("USER_NAME", "")).lower() == user["username"].lower()
        if own_row:
            return "phone_number", row.get("PHONE_NUMBER")
        return "salary", row.get("SALARY")

    def _audit_events_oracle(self):
        sql = """
            SELECT event_timestamp,
                   dbusername,
                   end_user_name,
                   os_username,
                   userhost,
                   client_program_name,
                   authentication_type,
                   sessionid,
                   action_name,
                   object_schema,
                   object_name,
                   return_code,
                   DBMS_LOB.SUBSTR(sql_text, 100, 1) AS sql_text_preview
              FROM unified_audit_trail
             WHERE object_schema = 'HR'
               AND object_name = 'EMPLOYEES'
               AND action_name IN ('SELECT', 'UPDATE')
               AND event_timestamp >= SYSTIMESTAMP - INTERVAL '3' MINUTE
             ORDER BY event_timestamp DESC
             FETCH FIRST 20 ROWS ONLY
        """
        try:
            rows = self._run_app_query(sql, fetch="rows")
        except Exception as exc:
            message = str(exc)
            if "ORA-01017" in message:
                return {
                    "mode": "oracledb",
                    "events": [],
                    "note": (
                        "Audit diagnostics could not sign in as deepsec_admin/Oracle123. "
                        "Run ./setup_audit_diagnostics.sh --tns-alias {0}, then restart the app."
                    ).format(self.tns_alias),
                }
            raise
        return {
            "mode": "oracledb",
            "window": "last 3 minutes",
            "events": rows,
            "note": "END_USER_NAME identifies the Deep Data Security end user. DBUSERNAME identifies the authenticated database user.",
        }

    def _visible_summary_oracle(self, user):
        sql = """
            SELECT ROUND(AVG(salary), 2) AS average_visible_salary,
                   COUNT(*) AS visible_rows
              FROM hr.employees
        """
        row = self._run_as_end_user(
            user,
            sql,
            fetch="one",
        )
        row = row or {}
        return {
            "mode": "oracledb",
            "user": user["username"],
            "elevated": False,
            "data_roles": user.get("roles", []),
            "average_visible_salary": row.get("AVERAGE_VISIBLE_SALARY"),
            "visible_rows": row.get("VISIBLE_ROWS"),
            "note": "Oracle evaluated the aggregate over only the rows visible to the authenticated end user.",
        }

    def _connect_oracle(self, user=None, admin=False):
        try:
            import oracledb
        except ImportError as exc:
            raise RuntimeError(
                "WEB_HR_DB_MODE=oracledb requires python-oracledb. "
                "Run ./setup_python_oracledb.sh, then restart with ./start.sh --verbose."
            ) from exc
        connection_kwargs = {
            "dsn": self.tns_alias,
        }
        if admin:
            admin_user = os.getenv("WEB_HR_ADMIN_USER", "deepsec_admin")
            admin_password = os.getenv("WEB_HR_ADMIN_PASSWORD", "Oracle123")
            connection_kwargs["user"] = admin_user
            connection_kwargs["password"] = admin_password
        else:
            password_env = user.get("password_env")
            password = os.getenv(password_env, os.getenv("WEB_HR_END_USER_PASSWORD", "Oracle123"))
            connection_kwargs["user"] = user["username"]
            connection_kwargs["password"] = password

        config_dir = os.getenv("WEB_HR_CONFIG_DIR") or os.getenv("TNS_ADMIN")
        wallet_location = os.getenv("WEB_HR_WALLET_LOCATION")
        if not wallet_location:
            default_wallet = Path(__file__).resolve().parent.parent / "python-wallet"
            if (default_wallet / "ewallet.pem").is_file():
                wallet_location = str(default_wallet)
        wallet_password = os.getenv("WEB_HR_WALLET_PASSWORD")
        if config_dir:
            connection_kwargs["config_dir"] = config_dir
        if wallet_location:
            wallet_pem = Path(wallet_location) / "ewallet.pem"
            if not wallet_pem.is_file():
                raise RuntimeError(
                    "WEB_HR_WALLET_LOCATION is set to {0}, but {1} does not exist. "
                    "Run ./setup_python_oracledb.sh to export the database server certificate "
                    "into the python-oracledb trust wallet.".format(wallet_location, wallet_pem)
                )
            connection_kwargs["wallet_location"] = wallet_location
        if wallet_password:
            connection_kwargs["wallet_password"] = wallet_password

        try:
            return oracledb.connect(**connection_kwargs)
        except Exception as exc:
            message = str(exc)
            if "DPY-4000" in message and self.tns_alias in message:
                raise RuntimeError(
                    "python-oracledb could not resolve the {0} TNS alias. "
                    "Set WEB_HR_CONFIG_DIR to the directory whose tnsnames.ora contains {0}, "
                    "or rerun ./setup_python_oracledb.sh so it can find and save that directory. "
                    "Current WEB_HR_CONFIG_DIR={1}; TNS_ADMIN={2}.".format(
                        self.tns_alias,
                        os.getenv("WEB_HR_CONFIG_DIR", "(not set)"),
                        os.getenv("TNS_ADMIN", "(not set)"),
                    )
                ) from exc
            if "CERTIFICATE_VERIFY_FAILED" in message or "self signed certificate" in message:
                wallet_hint = wallet_location or "(not set)"
                raise RuntimeError(
                    "python-oracledb could not verify the database TLS certificate. "
                    "This is the database TCPS trust store, not the browser HTTPS certificate. "
                    "Run ./setup_python_oracledb.sh, then restart ./run.sh. "
                    "Current WEB_HR_WALLET_LOCATION={0}.".format(wallet_hint)
                ) from exc
            raise

    def _run_as_end_user(self, user, sql, fetch, params=None, include_context=False):
        connection = self._connect_oracle(user=user)
        try:
            cursor = connection.cursor()
            try:
                cursor.execute(sql, params or {})
                if fetch == "rowcount":
                    row_count = cursor.rowcount
                    connection.commit()
                    return row_count
                columns = [d[0] for d in cursor.description]
                if fetch == "one":
                    row = cursor.fetchone()
                    data = _row_to_dict(columns, row) if row else None
                    return {"data": data, "request_context": self._current_request_context(cursor)} if include_context else data
                data = [_row_to_dict(columns, row) for row in cursor.fetchall()]
                return {"data": data, "request_context": self._current_request_context(cursor)} if include_context else data
            finally:
                cursor.close()
        finally:
            connection.close()

    def _run_app_query(self, sql, fetch, params=None):
        connection = self._connect_oracle(admin=True)
        try:
            cursor = connection.cursor()
            try:
                cursor.execute(sql, params or {})
                if fetch == "rowcount":
                    row_count = cursor.rowcount
                    connection.commit()
                    return row_count
                columns = [d[0] for d in cursor.description]
                if fetch == "one":
                    row = cursor.fetchone()
                    return _row_to_dict(columns, row) if row else None
                return [_row_to_dict(columns, row) for row in cursor.fetchall()]
            finally:
                cursor.close()
        finally:
            connection.close()

    def _current_request_context(self, cursor):
        identity_sql = """
            SELECT SYS_CONTEXT('USERENV','SESSIONID') AS session_id,
                   SYS_CONTEXT('USERENV','SERVICE_NAME') AS service_name,
                   ORA_END_USER_CONTEXT.username AS end_user_name,
                   SYS_CONTEXT('USERENV','AUTHENTICATED_IDENTITY') AS authenticated_identity,
                   SYS_CONTEXT('USERENV','ENTERPRISE_IDENTITY') AS enterprise_identity,
                   SYS_CONTEXT('USERENV','AUTHENTICATION_METHOD') AS auth_method,
                   SYS_CONTEXT('USERENV','CURRENT_USER') AS current_user
              FROM dual
        """
        cursor.execute(identity_sql)
        columns = [d[0] for d in cursor.description]
        identity = _row_to_dict(columns, cursor.fetchone())
        cursor.execute("SELECT role_name FROM v$end_user_data_role ORDER BY role_name")
        columns = [d[0] for d in cursor.description]
        roles = [_row_to_dict(columns, row) for row in cursor.fetchall()]
        return {
            "database_session": {
                "session_id": identity.get("SESSION_ID"),
                "service_name": identity.get("SERVICE_NAME"),
            },
            "identity": identity,
            "active_data_roles": roles,
        }


def _row_to_dict(columns, row):
    result = {}
    for index, column in enumerate(columns):
        value = row[index]
        if hasattr(value, "read"):
            value = value.read()
        if isinstance(value, bytes):
            value = value.decode("utf-8", "replace")
        elif hasattr(value, "isoformat"):
            value = value.isoformat()
        elif isinstance(value, Decimal):
            value = int(value) if value == value.to_integral_value() else float(value)
        result[column] = value
    return result


def _preflight_summary(checks):
    counts = {"pass": 0, "warn": 0, "fail": 0}
    for check in checks:
        status = check.get("status")
        if status in counts:
            counts[status] += 1
    return counts
