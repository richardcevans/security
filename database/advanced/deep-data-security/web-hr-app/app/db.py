import os
from decimal import Decimal
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
            "note": "Audit events are available in oracledb mode after running 04_configure_auditing.sh.",
        }

    def disable_salary_updates(self, user):
        if self.mode == "oracledb":
            return self._set_salary_update_policy_oracle(user, enabled=False)
        payload = self._employees_mock(user)
        payload["policy_change"] = "Mock mode: salary updates disabled."
        return payload

    def enable_salary_updates(self, user):
        if self.mode == "oracledb":
            return self._set_salary_update_policy_oracle(user, enabled=True)
        payload = self._employees_mock(user)
        payload["policy_change"] = "Mock mode: salary updates enabled."
        return payload

    def debug_tokens_for_user(self, user):
        if self.mode != "oracledb":
            return {
                "mode": self.mode,
                "message": "Database token diagnostics are available in oracledb mode.",
            }

        db_token = self._database_access_token_for_user(user["access_token"])
        return {
            "mode": "oracledb",
            "database_access_token": public_claims(decode_jwt_without_validation(db_token)),
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
        identity = self._run_with_context(user, None, identity_sql, fetch="one")
        roles = self._run_with_context(user, None, roles_sql, fetch="rows")
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
                SELECT SYS_CONTEXT('USERENV','AUTHENTICATED_IDENTITY') AS authenticated_identity,
                       SYS_CONTEXT('USERENV','AUTHENTICATION_METHOD') AS auth_method,
                       SYS_CONTEXT('USERENV','CURRENT_USER') AS current_user
                  FROM dual
                """,
                fetch="one",
            )
            return "Application token can acquire a pooled database connection.", row

        run("Pooled app connection", app_connection_check)

        def context_check():
            result = self._run_with_context(
                user,
                None,
                """
                SELECT ORA_END_USER_CONTEXT.username AS username,
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
            "value": value,
            "row_count": 1,
        }
        payload["note"] = "Mock mode accepted the edit. Oracle mode enforces it with Deep Data Security."
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

        if column in ("salary", "department_id") and value == "":
            value = None
        if column in ("salary", "department_id") and value is not None:
            try:
                value = float(value) if column == "salary" else int(value)
            except ValueError:
                raise ValueError("{0} must be numeric.".format(field_name))

        sql = "UPDATE hr.employees SET {0} = :value WHERE employee_id = :employee_id".format(column)
        row_count = self._run_with_context(
            user,
            None,
            sql,
            fetch="rowcount",
            params={"value": value, "employee_id": employee_id},
        )
        payload = self._employees_oracle(user)
        payload["updated"] = {
            "employee_id": employee_id,
            "field": field_name,
            "row_count": row_count,
        }
        if row_count == 0:
            payload["note"] = "No rows were updated. Deep Data Security did not authorize that edit for the current end user."
        return payload

    def _audit_events_oracle(self):
        sql = """
            SELECT event_timestamp,
                   dbusername,
                   end_user_name,
                   action_name,
                   object_schema,
                   object_name,
                   return_code
              FROM unified_audit_trail
             WHERE object_schema = 'HR'
               AND object_name = 'EMPLOYEES'
               AND action_name IN ('SELECT', 'UPDATE')
             ORDER BY event_timestamp DESC
             FETCH FIRST 20 ROWS ONLY
        """
        rows = self._run_app_query(sql, fetch="rows")
        return {
            "mode": "oracledb",
            "events": rows,
            "note": "END_USER_NAME identifies the Deep Data Security end user on pooled app connections.",
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

    def _pool_oracle(self):
        if self._pool is not None:
            return self._pool

        try:
            import oracledb
            import oracledb.plugins.end_user_sec_provider  # noqa: F401
        except ImportError as exc:
            raise RuntimeError(
                "WEB_HR_DB_MODE=oracledb requires python-oracledb with Deep Data Security support."
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
        wallet_password = os.getenv("WEB_HR_WALLET_PASSWORD")
        if config_dir:
            pool_kwargs["config_dir"] = config_dir
        if wallet_location:
            pool_kwargs["wallet_location"] = wallet_location
        if wallet_password:
            pool_kwargs["wallet_password"] = wallet_password

        self._pool = oracledb.create_pool(**pool_kwargs)
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

    def _run_with_context(self, user, data_roles, sql, fetch, params=None, include_context=False):
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
                connection.clear_end_user_security_context()
        finally:
            pool.release(connection)

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


def _preflight_summary(checks):
    counts = {"pass": 0, "warn": 0, "fail": 0}
    for check in checks:
        status = check.get("status")
        if status in counts:
            counts[status] += 1
    return counts
