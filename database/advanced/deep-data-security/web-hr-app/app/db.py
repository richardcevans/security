import json
import os
from decimal import Decimal, InvalidOperation
from pathlib import Path
from app.identity import decode_jwt_without_validation, public_claims
from urllib.parse import urlencode
from urllib.error import HTTPError
from urllib.request import Request, urlopen


class WebHrDatabase(object):
    def __init__(self):
        self.mode = os.getenv("WEB_HR_DB_MODE", "mock").lower()
        self.tns_alias = os.getenv("WEB_HR_TNS_ALIAS", "hrdb")
        self._pool = None

    def employees_for_user(self, user):
        if self.mode == "oracledb":
            return self._employees_oracle(user)
        return self._employees_mock(user)

    def salary_summary(self, user):
        if self.mode == "oracledb":
            return self._salary_summary_oracle(user)
        return self._salary_summary_mock(user)

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

    def disable_salary_updates(self, user):
        if self.mode == "oracledb":
            return self._set_salary_update_policy_oracle(user, enabled=False)
        payload = self._employees_mock(user)
        payload["policy_change"] = "Mock mode: salary updates disabled."
        payload["policy_demo"] = _policy_toggle_demo(False)
        return payload

    def enable_salary_updates(self, user):
        if self.mode == "oracledb":
            return self._set_salary_update_policy_oracle(user, enabled=True)
        payload = self._employees_mock(user)
        payload["policy_change"] = "Mock mode: salary updates enabled."
        payload["policy_demo"] = _policy_toggle_demo(True)
        return payload

    def debug_tokens_for_user(self, user):
        if self.mode != "oracledb":
            return {
                "mode": self.mode,
                "message": "Database token diagnostics are available in oracledb mode.",
            }

        app_token = self._application_access_token()
        db_token = self._database_access_token_for_user(user["access_token"])
        return {
            "mode": "oracledb",
            "application_database_token": public_claims(decode_jwt_without_validation(app_token)),
            "database_access_token": public_claims(decode_jwt_without_validation(db_token)),
        }

    def debug_context_for_user(self, user):
        if self.mode != "oracledb":
            return {
                "mode": self.mode,
                "message": "Database context diagnostics are available in oracledb mode.",
                "connection_model": self._connection_model(user, None),
            }

        pooled_identity = self._pooled_connection_identity()
        end_user_context = self._run_with_context(
            user,
            None,
            "SELECT 1 AS context_probe FROM dual",
            fetch="one",
            include_context=True,
        )["request_context"]
        roles = end_user_context.get("active_data_roles", [])
        payload = {
            "mode": "oracledb",
            "application_identity": self._application_identity_summary(),
            "pooled_connection_identity": pooled_identity,
            "end_user_context": end_user_context,
            "connection_model": self._connection_model(user, end_user_context),
            "identity": end_user_context.get("identity"),
            "active_data_roles": roles,
        }
        print("")
        print("========================================================================")
        print("Database context diagnostics")
        print("========================================================================")
        print(json.dumps(payload, indent=2, sort_keys=True, default=str))
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
            "WEB_HR_TOKEN_URI",
            "WEB_HR_APP_CLIENT_ID",
            "WEB_HR_APP_CLIENT_SECRET",
            "WEB_HR_DB_SCOPE",
        ]
        missing_env = [name for name in required_env if not os.getenv(name)]
        if missing_env:
            add("Required environment", "fail", "Missing {0}.".format(", ".join(missing_env)))
        else:
            add(
                "Required environment",
                "pass",
                "Required Entra and database token settings are present.",
                {
                    "tns_alias": self.tns_alias,
                    "db_scope": os.getenv("WEB_HR_DB_SCOPE"),
                    "app_db_scope": os.getenv("WEB_HR_APP_DB_SCOPE", os.getenv("WEB_HR_DB_SCOPE")),
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
            wallet_pem = os.path.join(wallet_location, "ewallet.pem")
            status = "pass" if os.path.isfile(wallet_pem) else "fail"
            add("Client wallet", status, "Wallet PEM: {0}".format(wallet_pem))
        else:
            default_wallet_pem = Path(__file__).resolve().parent.parent / "python-wallet" / "ewallet.pem"
            if default_wallet_pem.is_file():
                add("Client wallet", "pass", "Default wallet PEM: {0}".format(default_wallet_pem))
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
            import oracledb.plugins.end_user_sec_provider  # noqa: F401

            if not hasattr(oracledb, "create_end_user_security_context"):
                raise RuntimeError("python-oracledb does not expose create_end_user_security_context.")
            return (
                "python-oracledb exposes Deep Data Security APIs.",
                {"oracledb_version": getattr(oracledb, "__version__", "unknown")},
            )

        run("Python driver", driver_check)

        def app_token_check():
            token = self._application_access_token()
            claims = public_claims(decode_jwt_without_validation(token))
            return "Application database token acquired.", {
                "aud": claims.get("aud"),
                "appid": claims.get("appid"),
                "roles": claims.get("roles", []),
                "scp": claims.get("scp"),
            }

        run("Application token", app_token_check)

        def user_token_check():
            token = self._database_access_token_for_user(user["access_token"])
            claims = public_claims(decode_jwt_without_validation(token))
            return "On-behalf-of database token acquired for {0}.".format(user["username"]), {
                "aud": claims.get("aud"),
                "upn": claims.get("upn"),
                "roles": claims.get("roles", []),
                "scp": claims.get("scp"),
            }

        run("End-user database token", user_token_check)

        def app_connection_check():
            row = self._run_app_query(
                """
                SELECT SYS_CONTEXT('USERENV','SESSIONID') AS session_id,
                       SYS_CONTEXT('USERENV','SERVICE_NAME') AS service_name,
                       SYS_CONTEXT('USERENV','AUTHENTICATED_IDENTITY') AS authenticated_identity,
                       SYS_CONTEXT('USERENV','ENTERPRISE_IDENTITY') AS enterprise_identity,
                       SYS_CONTEXT('USERENV','AUTHENTICATION_METHOD') AS auth_method,
                       SYS_CONTEXT('USERENV','CURRENT_USER') AS current_user,
                       SYS_CONTEXT('USERENV','SESSION_USER') AS session_user,
                       SYS_CONTEXT('USERENV','CURRENT_SCHEMA') AS current_schema
                  FROM dual
                """,
                fetch="one",
            )
            row["EXPECTED_POOL_USER"] = "WEB_HR_APP_USER"
            row["ORACLE_APPLICATION_IDENTITY"] = "WEB_HR_APP"
            return "Application token can acquire a pooled database connection as WEB_HR_APP_USER.", row

        run("Pooled app connection", app_connection_check)

        def app_hr_privilege_check():
            rows = self._run_app_query(
                """
                SELECT privilege, column_name
                  FROM all_col_privs
                 WHERE table_schema = 'HR'
                   AND table_name = 'EMPLOYEES'
                   AND grantee = SYS_CONTEXT('USERENV','CURRENT_USER')
                   AND privilege = 'UPDATE'
                   AND column_name IN ('EMPLOYEE_ID', 'PHONE_NUMBER', 'SALARY', 'DEPARTMENT_ID')
                 ORDER BY column_name
                """,
                fetch="rows",
            )
            granted_columns = sorted(row.get("COLUMN_NAME") for row in rows)
            required_columns = ["DEPARTMENT_ID", "EMPLOYEE_ID", "PHONE_NUMBER", "SALARY"]
            missing_columns = [column for column in required_columns if column not in granted_columns]
            if missing_columns:
                raise RuntimeError(
                    "WEB_HR_APP_USER is missing UPDATE on HR.EMPLOYEES columns: {0}. "
                    "Run ./01_configure_database_app_identity.sh again.".format(", ".join(missing_columns))
                )
            return "Application identity has required HR.EMPLOYEES update columns.", {
                "update_columns": granted_columns,
            }

        run("Application HR update grants", app_hr_privilege_check)

        def context_check():
            result = self._run_with_context(
                user,
                None,
                """
                SELECT ORA_END_USER_CONTEXT.username AS username,
                       ORA_END_USER_CONTEXT.HR.EMP_CTX.ID AS employee_context_id,
                       SYS_CONTEXT('USERENV','AUTHENTICATION_METHOD') AS auth_method
                  FROM dual
                """,
                fetch="one",
            )
            return "Application can create and attach an end-user security context.", result

        run("End-user security context", context_check)

        def role_check():
            roles = self._run_with_context(
                user,
                None,
                "SELECT role_name FROM v$end_user_data_role ORDER BY role_name",
                fetch="rows",
            )
            return "Database mapped token roles to active Deep Data Security data roles.", {
                "active_data_roles": [row.get("ROLE_NAME") for row in roles],
            }

        run("Token role mapping", role_check)

        def elevation_check():
            result = self._run_with_context(
                user,
                ["HRAPP_COMPENSATION_ANALYST"],
                "SELECT COUNT(*) AS visible_rows FROM hr.employees",
                fetch="one",
            )
            return "Application can request HRAPP_COMPENSATION_ANALYST for one elevated action.", result

        run("Application elevation role", elevation_check)

        def audit_check():
            result = self._run_app_query(
                "SELECT COUNT(*) AS sample_rows FROM unified_audit_trail WHERE ROWNUM <= 1",
                fetch="one",
            )
            return "Application can read Unified Audit Trail through AUDIT_VIEWER.", result

        run("Audit visibility", audit_check)

        return {
            "mode": "oracledb",
            "checks": checks,
            "summary": _preflight_summary(checks),
        }

    def _employees_mock(self, user):
        username = user["username"].lower()
        is_manager = "MANAGERS" in user.get("roles", [])
        rows = [
            {"employee_id": 101, "first_name": "Marvin", "last_name": "Manager", "phone_number": "555-0101", "salary": "REDACTED", "ssn": "REDACTED", "department_id": 10, "manager_id": None},
            {"employee_id": 102, "first_name": "Emma", "last_name": "Employee", "phone_number": "555-0102", "salary": "REDACTED", "ssn": "REDACTED", "department_id": 10, "manager_id": 101},
            {"employee_id": 103, "first_name": "Avery", "last_name": "Analyst", "phone_number": "555-0103", "salary": "REDACTED", "ssn": "REDACTED", "department_id": 20, "manager_id": 101},
            {"employee_id": 104, "first_name": "Sofia", "last_name": "Engineer", "phone_number": "555-0104", "salary": "REDACTED", "ssn": "REDACTED", "department_id": 20, "manager_id": 101},
        ]
        if "emma" in username:
            rows = [rows[1]]
        elif not is_manager:
            rows = rows[:1]
        return {
            "mode": "mock",
            "user": user["username"],
            "elevated": False,
            "rows": rows,
            "request_context": {
                "pooled_connection": "mock",
                "end_user": user["username"],
                "active_data_roles": user.get("roles", []),
            },
            "note": "Normal request. No application elevation role was requested.",
        }

    def _update_employee_field_mock(self, user, employee_id, field_name, value):
        payload = self._employees_mock(user)
        payload["updated"] = {
            "employee_id": employee_id,
            "field": field_name,
            "where_clause": "employee_id = :employee_id",
            "requested_value": value,
            "database_value": value,
            "row_count": 1,
            "saved": True,
            "request_context": payload.get("request_context"),
        }
        payload["note"] = "Mock mode accepted the edit. Oracle mode enforces it with Deep Data Security."
        self._log_employee_update(user, payload)
        return payload

    def _salary_summary_mock(self, user):
        return {
            "mode": "mock",
            "user": user["username"],
            "elevated": True,
            "data_roles": ["HRAPP_COMPENSATION_ANALYST"],
            "average_salary": 9826.00,
            "employee_count": 5,
            "note": "Elevated request. In real mode the app asks Oracle for HRAPP_COMPENSATION_ANALYST.",
        }

    def _employees_oracle(self, user):
        sql = """
            SELECT emp.employee_id,
                   emp.first_name,
                   emp.last_name,
                   emp.phone_number,
                   emp.salary,
                   DECODE(ORA_IS_COLUMN_AUTHORIZED(ssn), false, '000-00-0000', true, ssn) AS ssn,
                   emp.department_id,
                   emp.manager_id,
                   ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', phone_number) AS can_update_phone_number,
                   ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', salary) AS can_update_salary,
                   ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', department_id) AS can_update_department_id
              FROM hr.employees emp
             ORDER BY employee_id
        """
        result = self._run_with_context(user, None, sql, fetch="rows", include_context=True)
        return {
            "mode": "oracledb",
            "user": user["username"],
            "elevated": False,
            "rows": result["data"],
            "request_context": result["request_context"],
            "note": "Oracle enforced visible rows and columns using the end user security context.",
        }

    def _update_employee_field_oracle(self, user, employee_id, field_name, value):
        columns = {
            "phone_number": "phone_number",
            "salary": "salary",
            "department_id": "department_id",
        }
        column = columns.get(field_name)
        if not column:
            raise ValueError("Field {0} is not editable.".format(field_name))

        value = self._normalize_employee_update_value(column, value)

        where_clause = "employee_id = :employee_id"
        sql = "UPDATE hr.employees SET {0} = :value WHERE {1}".format(column, where_clause)
        update_result = self._run_employee_update_with_context(
            user,
            sql,
            employee_id,
            field_name,
            column,
            value,
        )
        row_count = update_result["row_count"]
        payload = self._employees_oracle(user)
        database_value = update_result.get("database_value")
        saved = row_count == 1 and self._values_match(column, value, database_value)
        payload["updated"] = {
            "employee_id": employee_id,
            "field": field_name,
            "where_clause": where_clause,
            "requested_value": value,
            "database_value": database_value,
            "row_count": row_count,
            "saved": saved,
            "authorization_before_update": update_result.get("authorization_before_update"),
            "visible_row_before_update": update_result.get("visible_row_before_update"),
            "request_context": update_result.get("request_context"),
        }
        if row_count == 0:
            if payload["updated"]["authorization_before_update"].get("can_update") is True:
                payload["note"] = (
                    "Oracle reported this visible row and field as editable, but the employee_id-keyed UPDATE "
                    "affected zero rows. The database is likely still using stale HRAPP_EMPLOYEES_ACCESS or "
                    "HRAPP_MANAGER_ACCESS data grants that do not authorize employee_id-keyed update predicates. "
                    "Run ./01_configure_database_app_identity.sh and ./04_configure_policy_toggle_demo.sh again."
                )
            else:
                payload["note"] = "No rows were updated. Deep Data Security did not authorize that edit for the current end user."
        elif not saved:
            payload["note"] = (
                "The UPDATE reported success, but the refreshed row does not contain the requested value. "
                "Check triggers, column normalization, and Deep Data Security policy state."
            )
        self._log_employee_update(user, payload)
        return payload

    def _log_employee_update(self, user, payload):
        updated = payload.get("updated") or {}
        entry = {
            "event": "employee_update",
            "mode": self.mode,
            "user": user.get("username"),
            "employee_id": updated.get("employee_id"),
            "field": updated.get("field"),
            "where_clause": updated.get("where_clause"),
            "row_count": updated.get("row_count"),
            "saved": updated.get("saved"),
            "note": payload.get("note"),
            "authorization_before_update": updated.get("authorization_before_update"),
            "visible_row_before_update": updated.get("visible_row_before_update"),
            "request_context": updated.get("request_context"),
        }
        if os.getenv("WEB_HR_VERBOSE") == "1":
            entry["requested_value"] = updated.get("requested_value")
            entry["database_value"] = updated.get("database_value")

        print("")
        print("========================================================================")
        print("Employee update result")
        print("========================================================================")
        print(json.dumps(entry, indent=2, sort_keys=True, default=str))
        print("========================================================================")
        print("")

    def _normalize_employee_update_value(self, column, value):
        if value is None:
            return None
        if column == "phone_number":
            return str(value).strip()

        text = str(value).strip().replace(",", "")
        if column == "salary":
            text = text.replace("$", "")
        if text == "":
            return None

        if column == "salary":
            try:
                return Decimal(text)
            except InvalidOperation:
                raise ValueError("salary must be numeric.")
        if column == "department_id":
            try:
                return int(text)
            except ValueError:
                raise ValueError("department_id must be numeric.")
        return value

    def _run_employee_update_with_context(self, user, sql, employee_id, field_name, column, value):
        def operation(connection, cursor):
            before_row = self._employee_row_for_update(cursor, employee_id)
            if not before_row:
                raise ValueError("Employee {0} is not visible to {1}.".format(employee_id, user["username"]))

            authorization_before_update = self._update_authorization_for_row(before_row, field_name)
            context_before_update = self._current_request_context(cursor)
            cursor.execute(sql, {"value": value, "employee_id": employee_id})
            row_count = cursor.rowcount
            after_row = self._employee_row_for_update(cursor, employee_id)
            database_value = after_row.get(column.upper()) if after_row else None
            connection.commit()
            return {
                "row_count": row_count,
                "database_value": database_value,
                "authorization_before_update": authorization_before_update,
                "visible_row_before_update": _employee_update_log_row(before_row),
                "request_context": context_before_update,
            }

        return self._with_context(user, None, operation)

    def _employee_row_for_update(self, cursor, employee_id):
        cursor.execute(
            """
            SELECT emp.employee_id,
                   emp.first_name,
                   emp.last_name,
                   emp.phone_number,
                   emp.salary,
                   emp.department_id,
                   emp.manager_id,
                   ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', phone_number) AS can_update_phone_number,
                   ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', salary) AS can_update_salary,
                   ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', department_id) AS can_update_department_id
              FROM hr.employees emp
             WHERE emp.employee_id = :employee_id
            """,
            {"employee_id": employee_id},
        )
        columns = [d[0] for d in cursor.description]
        row = cursor.fetchone()
        return _row_to_dict(columns, row) if row else None

    def _visible_row_for_employee(self, user, employee_id):
        payload = self._employees_oracle(user)
        row = self._row_by_employee_id(payload.get("rows", []), employee_id)
        if row:
            return row
        raise ValueError("Employee {0} is not visible to {1}.".format(employee_id, user["username"]))

    def _update_authorization_for_row(self, row, field_name):
        permission_fields = {
            "phone_number": "CAN_UPDATE_PHONE_NUMBER",
            "salary": "CAN_UPDATE_SALARY",
            "department_id": "CAN_UPDATE_DEPARTMENT_ID",
        }
        permission_field = permission_fields.get(field_name)
        raw_value = row.get(permission_field) if permission_field else None
        return {
            "permission_field": permission_field,
            "raw_value": raw_value,
            "can_update": _is_oracle_true(raw_value),
        }

    def _row_by_employee_id(self, rows, employee_id):
        for row in rows:
            if row.get("EMPLOYEE_ID") == employee_id:
                return row
        return None

    def _values_match(self, column, requested, actual):
        if requested is None:
            return actual is None
        if actual is None:
            return False
        if column == "phone_number":
            return str(requested).strip() == str(actual).strip()
        if column == "salary":
            try:
                return Decimal(str(requested)) == Decimal(str(actual))
            except InvalidOperation:
                return str(requested) == str(actual)
        if column == "department_id":
            try:
                return int(requested) == int(actual)
            except (TypeError, ValueError):
                return str(requested) == str(actual)
        return requested == actual

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
        rows = self._run_app_query(sql, fetch="rows")
        return {
            "mode": "oracledb",
            "window": "last 3 minutes",
            "events": rows,
            "note": "END_USER_NAME identifies the Deep Data Security end user. DBUSERNAME identifies the pooled application database account.",
        }

    def _set_salary_update_policy_oracle(self, user, enabled):
        proc = "sys.web_hr_enable_salary_updates" if enabled else "sys.web_hr_disable_salary_updates"
        self._run_app_query("BEGIN {0}; END;".format(proc), fetch="rowcount")
        payload = self._employees_oracle(user)
        payload["policy_change"] = (
            "Manager salary updates enabled by recreating HR.HRAPP_MANAGER_ACCESS."
            if enabled
            else "Manager salary updates disabled by recreating HR.HRAPP_MANAGER_ACCESS without UPDATE(salary)."
        )
        payload["dba_demo_procedure"] = proc
        payload["policy_demo"] = _policy_toggle_demo(enabled)
        return payload

    def _salary_summary_oracle(self, user):
        sql = """
            SELECT ROUND(AVG(salary), 2) AS average_salary, COUNT(*) AS employee_count
              FROM hr.employees
        """
        rows = self._run_with_context(
            user,
            ["HRAPP_COMPENSATION_ANALYST"],
            sql,
            fetch="one",
        )
        row = rows or {}
        return {
            "mode": "oracledb",
            "user": user["username"],
            "elevated": True,
            "data_roles": ["HRAPP_COMPENSATION_ANALYST"],
            "average_salary": row.get("AVERAGE_SALARY"),
            "employee_count": row.get("EMPLOYEE_COUNT"),
            "note": "Oracle allowed this only because the local data role is granted to the application identity.",
        }

    def _application_identity_summary(self):
        client_id = os.getenv("WEB_HR_APP_CLIENT_ID", "")
        return {
            "oracle_application_identity": "WEB_HR_APP",
            "pooled_database_user": "WEB_HR_APP_USER",
            "mapped_to": "AZURE_CLIENT_ID={0}".format(client_id) if client_id else "AZURE_CLIENT_ID=<not set>",
            "client_id": client_id,
            "database_scope": os.getenv("WEB_HR_DB_SCOPE"),
            "application_database_scope": os.getenv("WEB_HR_APP_DB_SCOPE", os.getenv("WEB_HR_DB_SCOPE")),
            "tns_alias": self.tns_alias,
        }

    def _connection_model(self, user, request_context):
        active_roles = []
        if request_context:
            active_roles = [
                row.get("ROLE_NAME")
                for row in request_context.get("active_data_roles", [])
                if row.get("ROLE_NAME")
            ]
        return {
            "browser_signed_in_user": user.get("username"),
            "pooled_connection_database_user": "WEB_HR_APP_USER",
            "oracle_application_identity": "WEB_HR_APP",
            "end_user_security_context": user.get("username"),
            "employee_context_id": (
                (request_context or {}).get("identity") or {}
            ).get("EMPLOYEE_CONTEXT_ID"),
            "active_data_roles": active_roles,
            "how_requests_run": (
                "The Python app borrows a pooled WEB_HR_APP_USER connection, creates an end-user "
                "security context from the signed-in user's database token and the application "
                "database token, attaches that context for the request, then clears it before "
                "returning the connection to the pool."
            ),
        }

    def _pooled_connection_identity(self):
        row = self._run_app_query(
            """
            SELECT SYS_CONTEXT('USERENV','SESSIONID') AS session_id,
                   SYS_CONTEXT('USERENV','SERVICE_NAME') AS service_name,
                   SYS_CONTEXT('USERENV','AUTHENTICATED_IDENTITY') AS authenticated_identity,
                   SYS_CONTEXT('USERENV','ENTERPRISE_IDENTITY') AS enterprise_identity,
                   SYS_CONTEXT('USERENV','AUTHENTICATION_METHOD') AS auth_method,
                   SYS_CONTEXT('USERENV','CURRENT_USER') AS current_user,
                   SYS_CONTEXT('USERENV','SESSION_USER') AS session_user,
                   SYS_CONTEXT('USERENV','CURRENT_SCHEMA') AS current_schema,
                   SYS_CONTEXT('USERENV','CLIENT_IDENTIFIER') AS client_identifier
              FROM dual
            """,
            fetch="one",
        )
        row["EXPECTED_POOL_USER"] = "WEB_HR_APP_USER"
        row["ORACLE_APPLICATION_IDENTITY"] = "WEB_HR_APP"
        return row

    def _pool_oracle(self):
        if self._pool is not None:
            return self._pool

        try:
            import oracledb
            import oracledb.plugins.end_user_sec_provider  # noqa: F401
        except ImportError as exc:
            raise RuntimeError(
                "WEB_HR_DB_MODE=oracledb requires python-oracledb with Deep Data Security support. "
                "The current Python environment cannot import oracledb.plugins.end_user_sec_provider. "
                "Run ./setup_python_oracledb.sh, then restart with ./start.sh --verbose so run.sh uses "
                "~/web-hr-app-venv/bin/python."
            ) from exc

        version = getattr(oracledb, "__version__", "unknown")
        missing = []
        if not hasattr(oracledb, "create_end_user_security_context"):
            missing.append("oracledb.create_end_user_security_context")
        if missing:
            raise RuntimeError(
                "python-oracledb {0} does not expose the required Deep Data Security API: {1}. "
                "Install python-oracledb 4.0 or later in a supported Python environment.".format(
                    version,
                    ", ".join(missing),
                )
            )

        if not all(
            [
                os.getenv("WEB_HR_DB_SCOPE"),
                os.getenv("WEB_HR_APP_DB_SCOPE", os.getenv("WEB_HR_DB_SCOPE")),
                os.getenv("WEB_HR_TOKEN_URI"),
                os.getenv("WEB_HR_APP_CLIENT_ID"),
                os.getenv("WEB_HR_APP_CLIENT_SECRET"),
            ]
        ):
            raise RuntimeError("Missing Web HR App database token settings. Run 00_setup_entra_web_app.sh.")

        pool_kwargs = {
            "dsn": self.tns_alias,
            "min": 1,
            "max": 4,
            "increment": 1,
            "access_token": self._application_access_token,
        }

        config_dir = os.getenv("WEB_HR_CONFIG_DIR") or os.getenv("TNS_ADMIN")
        wallet_location = os.getenv("WEB_HR_WALLET_LOCATION")
        if not wallet_location:
            default_wallet = Path(__file__).resolve().parent.parent / "python-wallet"
            if (default_wallet / "ewallet.pem").is_file():
                wallet_location = str(default_wallet)
        wallet_password = os.getenv("WEB_HR_WALLET_PASSWORD")
        if config_dir:
            pool_kwargs["config_dir"] = config_dir
        if wallet_location:
            wallet_pem = Path(wallet_location) / "ewallet.pem"
            if not wallet_pem.is_file():
                raise RuntimeError(
                    "WEB_HR_WALLET_LOCATION is set to {0}, but {1} does not exist. "
                    "Run ./setup_python_oracledb.sh to export the database server certificate "
                    "into the python-oracledb trust wallet.".format(wallet_location, wallet_pem)
                )
            pool_kwargs["wallet_location"] = wallet_location
        if wallet_password:
            pool_kwargs["wallet_password"] = wallet_password

        try:
            self._pool = oracledb.create_pool(**pool_kwargs)
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
        return self._pool

    def _application_access_token(self, *args):
        body = urlencode(
            {
                "grant_type": "client_credentials",
                "client_id": os.getenv("WEB_HR_APP_CLIENT_ID"),
                "client_secret": os.getenv("WEB_HR_APP_CLIENT_SECRET"),
                "scope": os.getenv("WEB_HR_APP_DB_SCOPE", os.getenv("WEB_HR_DB_SCOPE")),
            }
        ).encode("utf-8")
        return self._request_access_token(body, "application database access token")

    def _database_access_token_for_user(self, end_user_token):
        body = urlencode(
            {
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "client_id": os.getenv("WEB_HR_APP_CLIENT_ID"),
                "client_secret": os.getenv("WEB_HR_APP_CLIENT_SECRET"),
                "scope": os.getenv("WEB_HR_DB_SCOPE"),
                "assertion": end_user_token,
                "requested_token_use": "on_behalf_of",
            }
        ).encode("utf-8")
        return self._request_access_token(body, "on-behalf-of database access token")

    def _request_access_token(self, body, token_name):
        request = Request(
            os.getenv("WEB_HR_TOKEN_URI"),
            data=body,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        try:
            with urlopen(request, timeout=30) as response:
                payload = __import__("json").loads(response.read().decode("utf-8"))
        except HTTPError as exc:
            message = exc.read().decode("utf-8", "replace")
            raise RuntimeError(
                "Could not get {0}: HTTP {1} {2}".format(token_name, exc.code, message)
            )
        token = payload.get("access_token")
        if not token:
            raise RuntimeError("Entra ID did not return an {0}.".format(token_name))
        return token

    def _with_context(self, user, data_roles, operation):
        import oracledb

        pool = self._pool_oracle()
        connection = pool.acquire()
        try:
            end_user_database_token = self._database_access_token_for_user(user["access_token"])
            context_kwargs = {
                "end_user_identity": end_user_database_token,
                "database_access_token": self._application_access_token(),
            }
            if data_roles:
                context_kwargs["data_roles"] = data_roles
                print("Requesting data roles: {0}".format(", ".join(data_roles)))
            context = oracledb.create_end_user_security_context(**context_kwargs)
            connection.set_end_user_security_context(context)
            cursor = connection.cursor()
            try:
                return operation(connection, cursor)
            except Exception:
                connection.rollback()
                raise
            finally:
                cursor.close()
                connection.clear_end_user_security_context()
        finally:
            pool.release(connection)

    def _run_with_context(self, user, data_roles, sql, fetch, params=None, include_context=False):
        def operation(connection, cursor):
            cursor.execute(sql, params or {})
            if fetch == "rowcount":
                row_count = cursor.rowcount
                request_context = self._current_request_context(cursor) if include_context else None
                connection.commit()
                if include_context:
                    return {
                        "row_count": row_count,
                        "request_context": request_context,
                    }
                return row_count
            columns = [d[0] for d in cursor.description]
            if fetch == "one":
                row = cursor.fetchone()
                data = _row_to_dict(columns, row) if row else None
                return {"data": data, "request_context": self._current_request_context(cursor)} if include_context else data
            data = [_row_to_dict(columns, row) for row in cursor.fetchall()]
            return {"data": data, "request_context": self._current_request_context(cursor)} if include_context else data

        return self._with_context(user, data_roles, operation)

    def _run_app_query(self, sql, fetch, params=None):
        pool = self._pool_oracle()
        connection = pool.acquire()
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
            pool.release(connection)

    def _current_request_context(self, cursor):
        identity_sql = """
            SELECT SYS_CONTEXT('USERENV','SESSIONID') AS session_id,
                   SYS_CONTEXT('USERENV','SERVICE_NAME') AS service_name,
                   ORA_END_USER_CONTEXT.username AS end_user_name,
                   ORA_END_USER_CONTEXT.HR.EMP_CTX.ID AS employee_context_id,
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
            "pooled_connection": {
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


def _is_oracle_true(value):
    if value is True:
        return True
    if value in (1, "1"):
        return True
    return str(value).upper() == "TRUE"


def _employee_update_log_row(row):
    return {
        "employee_id": row.get("EMPLOYEE_ID"),
        "manager_id": row.get("MANAGER_ID"),
        "can_update_phone_number": _is_oracle_true(row.get("CAN_UPDATE_PHONE_NUMBER")),
        "can_update_salary": _is_oracle_true(row.get("CAN_UPDATE_SALARY")),
        "can_update_department_id": _is_oracle_true(row.get("CAN_UPDATE_DEPARTMENT_ID")),
    }


def _preflight_summary(checks):
    counts = {"pass": 0, "warn": 0, "fail": 0}
    for check in checks:
        status = check.get("status")
        if status in counts:
            counts[status] += 1
    return counts


def _policy_toggle_demo(enabled):
    update_clause = (
        "UPDATE (employee_id, salary, department_id, first_name)"
        if enabled
        else "UPDATE (employee_id, department_id, first_name)"
    )
    return {
        "button_effect": "Restore Salary Edits" if enabled else "Disable Salary Edits",
        "what_changes": "The app calls a SYS definer-rights procedure installed by 04_configure_policy_toggle_demo.sh.",
        "procedure": (
            "SYS.WEB_HR_ENABLE_SALARY_UPDATES"
            if enabled
            else "SYS.WEB_HR_DISABLE_SALARY_UPDATES"
        ),
        "deepsec_change": (
            "Recreates HR.HRAPP_MANAGER_ACCESS with UPDATE(employee_id, salary), so manager salary cells become editable again."
            if enabled
            else "Recreates HR.HRAPP_MANAGER_ACCESS with UPDATE(employee_id) but without UPDATE(salary), so manager salary cells are no longer editable."
        ),
        "data_grant_core": (
            "CREATE OR REPLACE DATA GRANT hr.HRAPP_MANAGER_ACCESS "
            "AS SELECT (ALL COLUMNS EXCEPT ssn), {0} "
            "ON hr.employees "
            "WHERE manager_id = ORA_END_USER_CONTEXT.HR.EMP_CTX.ID "
            "TO HRAPP_MANAGERS"
        ).format(update_clause),
        "application_behavior": (
            "After the procedure runs, the app reloads employees and asks Oracle "
            "ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', salary) again. The UI follows "
            "Oracle's answer; the app does not hard-code the salary rule."
        ),
    }
