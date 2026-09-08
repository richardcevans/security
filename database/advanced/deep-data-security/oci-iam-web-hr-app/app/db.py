"""Direct ADB access using the signed-in OCI IAM OAuth token.

Each request opens a short-lived connection with the browser user's token.
Oracle Database therefore evaluates its OCI IAM data roles and data grants for
that user; this app never uses an ADMIN password or a shared database account.
"""

import os
from decimal import Decimal

import oracledb

from app.identity import decode_jwt_without_validation, public_claims


class WebHrDatabase:
    def __init__(self):
        self.dsn = os.getenv("WEB_HR_TNS_ALIAS") or os.getenv("ADB_SERVICE", "")
        self.config_dir = os.getenv("TNS_ADMIN") or os.getenv("WALLET_DIR", "")
        self.wallet_password = os.getenv("WALLET_PWD", "")

    def employees_for_user(self, user):
        return {"mode": "oci_iam_oauth", "rows": self._query(user, """
            SELECT employee_id, first_name, last_name, user_name, department_id,
                   manager_id, phone_number, salary
              FROM hr.employees
             ORDER BY employee_id
        """)}

    def salary_summary(self, user):
        rows = self._query(user, """
            SELECT COUNT(*) AS visible_rows, SUM(salary) AS total_salary,
                   AVG(salary) AS average_salary
              FROM hr.employees
        """)
        summary = rows[0] if rows else {}
        return {"mode": "oci_iam_oauth", "elevated": False,
                "employee_count": summary.get("visible_rows", 0),
                "total_salary": summary.get("total_salary"),
                "average_salary": summary.get("average_salary")}

    def update_employee_field(self, user, employee_id, field_name, value):
        allowed = {"phone_number", "first_name", "salary", "department_id"}
        if field_name not in allowed:
            raise ValueError("Field is not an allowed application update.")
        with self._connection(user) as connection:
            with connection.cursor() as cursor:
                cursor.execute("UPDATE hr.employees SET {0} = :value WHERE employee_id = :employee_id".format(field_name), {"value": value, "employee_id": employee_id})
                affected = cursor.rowcount
            connection.commit()
        return {"mode": "oci_iam_oauth", "updated_rows": affected, "employee_id": employee_id, "field": field_name}

    def audit_events(self, user):
        return {"mode": "oci_iam_oauth", "events": [], "note": "Audit access is intentionally not granted to the end-user application."}

    def disable_salary_updates(self, user):
        return {"mode": "oci_iam_oauth", "note": "Policy changes are DBA operations and are not exposed to this end-user app."}

    enable_salary_updates = disable_salary_updates

    def debug_tokens_for_user(self, user):
        return {"mode": "oci_iam_oauth", "database_access_token": public_claims(decode_jwt_without_validation(user["access_token"]))}

    def debug_context_for_user(self, user):
        return {"mode": "oci_iam_oauth", "identity": self._query(user, """
            SELECT SYS_CONTEXT('USERENV','AUTHENTICATED_IDENTITY') AS authenticated_identity,
                   SYS_CONTEXT('USERENV','AUTHENTICATION_METHOD') AS auth_method,
                   SYS_CONTEXT('USERENV','CURRENT_USER') AS current_user
              FROM dual
        """)}

    def preflight(self, user):
        try:
            identity = self.debug_context_for_user(user)["identity"]
            visible = self._query(user, "SELECT COUNT(*) AS visible_rows FROM hr.employees")
            return {"mode": "oci_iam_oauth", "summary": "pass", "checks": [
                {"name": "OCI IAM token connection", "status": "pass", "detail": "Connected to ADB with the signed-in user's OAuth token."},
                {"name": "Database identity", "status": "pass", "detail": "Database authenticated the OCI IAM user.", "evidence": identity},
                {"name": "Data grants", "status": "pass", "detail": "HR query completed under database-enforced data grants.", "evidence": visible},
            ]}
        except Exception as exc:
            return {"mode": "oci_iam_oauth", "summary": "fail", "checks": [{"name": "OCI IAM database connection", "status": "fail", "detail": str(exc)}]}

    def _connection(self, user):
        if not self.dsn or not self.config_dir or not self.wallet_password:
            raise RuntimeError("ADB_SERVICE, TNS_ADMIN/WALLET_DIR, and WALLET_PWD must be present in .deep-sec-mcp.env.")
        return oracledb.connect(
            access_token=user["access_token"],
            dsn=self.dsn,
            config_dir=self.config_dir,
            wallet_location=self.config_dir,
            wallet_password=self.wallet_password,
        )

    def _query(self, user, statement):
        with self._connection(user) as connection:
            with connection.cursor() as cursor:
                cursor.execute(statement)
                columns = [item[0].lower() for item in cursor.description]
                return [_json_row(dict(zip(columns, row))) for row in cursor]


def _json_row(row):
    return {key: float(value) if isinstance(value, Decimal) else value for key, value in row.items()}
