import os
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

    def _employees_mock(self, user):
        username = user["username"].lower()
        is_manager = "MANAGERS" in user.get("roles", [])
        rows = [
            {"employee_id": 101, "first_name": "Marvin", "last_name": "Manager", "salary": "REDACTED", "manager_id": None},
            {"employee_id": 102, "first_name": "Emma", "last_name": "Employee", "salary": "REDACTED", "manager_id": 101},
            {"employee_id": 103, "first_name": "Avery", "last_name": "Analyst", "salary": "REDACTED", "manager_id": 101},
            {"employee_id": 104, "first_name": "Sofia", "last_name": "Engineer", "salary": "REDACTED", "manager_id": 101},
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
            "note": "Normal request. No application elevation role was requested.",
        }

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
            SELECT employee_id, first_name, last_name, ssn, salary, department_id, manager_id
              FROM hr.employees
             ORDER BY employee_id
        """
        rows = self._run_with_context(user, None, sql, fetch="rows")
        return {
            "mode": "oracledb",
            "user": user["username"],
            "elevated": False,
            "rows": rows,
            "note": "Oracle enforced visible rows and columns using the end user security context.",
        }

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
            "note": "Oracle allowed this only because the data role is granted to the application identity.",
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

    def _run_with_context(self, user, data_roles, sql, fetch):
        import oracledb

        pool = self._pool_oracle()
        connection = pool.acquire()
        try:
            db_token = self._database_access_token_for_user(user["access_token"])
            effective_data_roles = self._mapped_data_roles_from_database_token(db_token)
            if data_roles:
                effective_data_roles.extend(data_roles)
            effective_data_roles = sorted(set(effective_data_roles))

            context_kwargs = {
                "end_user_identity": user["access_token"],
                "database_access_token": db_token,
            }
            if effective_data_roles:
                context_kwargs["data_roles"] = effective_data_roles
                print("Requesting data roles: {0}".format(", ".join(effective_data_roles)))
            context = oracledb.create_end_user_security_context(**context_kwargs)
            connection.set_end_user_security_context(context)
            cursor = connection.cursor()
            try:
                cursor.execute(sql)
                columns = [d[0] for d in cursor.description]
                if fetch == "one":
                    row = cursor.fetchone()
                    return _row_to_dict(columns, row) if row else None
                return [_row_to_dict(columns, row) for row in cursor.fetchall()]
            finally:
                cursor.close()
                connection.clear_end_user_security_context()
        finally:
            pool.release(connection)

    def _mapped_data_roles_from_database_token(self, db_token):
        claims = decode_jwt_without_validation(db_token)
        roles = claims.get("roles") or []
        if isinstance(roles, str):
            roles = roles.split()

        mapped_roles = []
        for role in roles:
            role_name = str(role).upper()
            if role_name in ("EMPLOYEES", "MANAGERS"):
                mapped_roles.append("HRAPP_{0}".format(role_name))
        return mapped_roles


def _row_to_dict(columns, row):
    result = {}
    for index, column in enumerate(columns):
        value = row[index]
        if hasattr(value, "read"):
            value = value.read()
        result[column] = value
    return result
