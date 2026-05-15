from __future__ import annotations

import json
import os
import shutil
import subprocess
from typing import Any

from app.identity import UserIdentity


SQLPLUS_JSON_BEGIN = "__MCP_GRANT_VIEW_JSON_BEGIN__"
SQLPLUS_JSON_END = "__MCP_GRANT_VIEW_JSON_END__"


class GrantViewDatabase:
    def __init__(self) -> None:
        self.mode = os.getenv("GRANT_VIEW_DB_MODE", "mock").lower()
        self.tns_alias = os.getenv("GRANT_VIEW_TNS_ALIAS", "hrdb")
        self.sqlplus_bin = os.getenv("SQLPLUS_BIN", "sqlplus")
        self.sqlplus_timeout = int(os.getenv("SQLPLUS_TIMEOUT_SECONDS", "180"))

    def search_employees(self, identity: UserIdentity, query: str = "") -> dict[str, Any]:
        if self.mode in {"python", "oracledb"}:
            return self._search_employees_python(identity, query)
        if self.mode in {"sqlplus", "oracle"}:
            return self._search_employees_oracle(identity, query)
        return self._search_employees_mock(identity, query)

    def summarize_access(self, identity: UserIdentity) -> dict[str, Any]:
        if self.mode in {"python", "oracledb"}:
            return self._summarize_access_python(identity)
        if self.mode in {"sqlplus", "oracle"}:
            return self._summarize_access_oracle(identity)
        return {
            "user": identity.subject,
            "roles": list(identity.roles),
            "model": "mock data grants",
            "visible_regions": self._visible_regions(identity),
            "visible_departments": self._visible_departments(identity),
            "salary_visible": self._can_view_salary(identity),
        }

    def _search_employees_mock(self, identity: UserIdentity, query: str) -> dict[str, Any]:
        rows = [
            {
                "employee_id": 101,
                "first_name": "Avery",
                "last_name": "Chen",
                "name": "Avery Chen",
                "ssn": None,
                "salary": "REDACTED",
                "department_id": 80,
                "manager_id": None,
            },
            {
                "employee_id": 102,
                "first_name": "Mina",
                "last_name": "Patel",
                "name": "Mina Patel",
                "ssn": "123-45-6789",
                "salary": 152000,
                "department_id": 100,
                "manager_id": 101,
            },
            {
                "employee_id": 103,
                "first_name": "Jon",
                "last_name": "Bell",
                "name": "Jon Bell",
                "ssn": None,
                "salary": "REDACTED",
                "department_id": 60,
                "manager_id": 101,
            },
            {
                "employee_id": 104,
                "first_name": "Sofia",
                "last_name": "Reyes",
                "name": "Sofia Reyes",
                "ssn": None,
                "salary": "REDACTED",
                "department_id": 80,
                "manager_id": 101,
            },
        ]

        needle = query.strip().lower()
        visible_rows = []

        for row in rows:
            if needle and needle not in " ".join(str(value).lower() for value in row.values()):
                continue
            visible_rows.append(dict(row))

        return {
            "user": identity.subject,
            "roles": list(identity.roles),
            "query": query,
            "rows": visible_rows,
            "row_count": len(visible_rows),
            "enforced_by": "mock adapter standing in for Oracle data grants",
        }

    def _search_employees_oracle(self, identity: UserIdentity, query: str) -> dict[str, Any]:
        result = self._run_sqlplus_json(_emit_json_sql(_employees_select_sql(query)))
        result["query"] = query
        result["row_count"] = len(result.get("rows", []))
        result["enforced_by"] = (
            f"Oracle Database through sqlplus /@{self.tns_alias}; "
            "Entra ID token auth and data grants are enforced by the database"
        )
        return result

    def _summarize_access_oracle(self, identity: UserIdentity) -> dict[str, Any]:
        result = self._run_sqlplus_json(_emit_json_sql(_access_select_sql()))
        result["model"] = (
            f"Oracle Database through sqlplus /@{self.tns_alias}; "
            "identity comes from the Entra ID token accepted by Oracle"
        )
        result["salary_visible"] = any(
            role.upper() in {"HRAPP_EMPLOYEES", "HRAPP_MANAGERS"}
            for role in result.get("roles", [])
        )
        return result

    def _search_employees_python(self, identity: UserIdentity, query: str) -> dict[str, Any]:
        result = self._run_python_json(identity, _employees_select_sql(query))
        result["query"] = query
        result["row_count"] = len(result.get("rows", []))
        result["enforced_by"] = (
            f"Oracle Database through python-oracledb /@{self.tns_alias}; "
            "Entra ID token auth and data grants are enforced by the database"
        )
        return result

    def _summarize_access_python(self, identity: UserIdentity) -> dict[str, Any]:
        result = self._run_python_json(identity, _access_select_sql())
        result["model"] = (
            f"Oracle Database through python-oracledb /@{self.tns_alias}; "
            "identity comes from the Entra ID token accepted by Oracle"
        )
        result["salary_visible"] = any(
            role.upper() in {"HRAPP_EMPLOYEES", "HRAPP_MANAGERS"}
            for role in result.get("roles", [])
        )
        return result

    def _run_python_json(self, identity: UserIdentity, sql: str) -> dict[str, Any]:
        try:
            import oracledb
        except ImportError as exc:
            raise RuntimeError(
                "GRANT_VIEW_DB_MODE=python requires python-oracledb. Install it with "
                "python3 -m pip install python-oracledb."
            ) from exc

        lib_dir = os.getenv("ORACLE_CLIENT_LIB_DIR")
        if lib_dir:
            try:
                oracledb.init_oracle_client(lib_dir=lib_dir)
            except Exception:
                pass

        connect_kwargs: dict[str, Any] = {"dsn": self.tns_alias}
        if identity.access_token:
            connect_kwargs["access_token"] = lambda: identity.access_token
            if os.getenv("ORACLEDB_EXTERNAL_AUTH", "true").lower() == "true":
                connect_kwargs["externalauth"] = True
        else:
            connect_kwargs["externalauth"] = True

        try:
            with oracledb.connect(**connect_kwargs) as connection:
                with connection.cursor() as cursor:
                    cursor.execute(sql)
                    row = cursor.fetchone()
        except Exception as exc:
            raise RuntimeError(f"python-oracledb could not query Oracle: {exc}") from exc

        if not row:
            raise RuntimeError("Oracle returned no JSON payload.")

        value = row[0]
        if hasattr(value, "read"):
            value = value.read()
        try:
            parsed = json.loads(str(value))
        except json.JSONDecodeError as exc:
            raise RuntimeError("Oracle returned data, but it was not valid JSON.") from exc
        if not isinstance(parsed, dict):
            raise RuntimeError("Oracle JSON payload was not an object.")
        return parsed

    def _run_sqlplus_json(self, sql: str) -> dict[str, Any]:
        if not shutil.which(self.sqlplus_bin):
            raise RuntimeError(
                f"Cannot find {self.sqlplus_bin}. Install Oracle Client or set SQLPLUS_BIN."
            )

        script = _sqlplus_script(sql)
        try:
            completed = subprocess.run(
                [self.sqlplus_bin, "-s", f"/@{self.tns_alias}"],
                input=script,
                text=True,
                capture_output=True,
                timeout=self.sqlplus_timeout,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError(
                "Timed out waiting for sqlplus. If Entra ID opened a browser, finish "
                "the sign-in and try again, or increase SQLPLUS_TIMEOUT_SECONDS."
            ) from exc

        output = f"{completed.stdout}\n{completed.stderr}"
        if completed.returncode != 0:
            raise RuntimeError(_short_sqlplus_error(output))

        json_text = _extract_between_markers(output)
        try:
            parsed = json.loads(json_text)
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                "SQLPlus returned data, but the app could not parse the JSON payload."
            ) from exc

        if not isinstance(parsed, dict):
            raise RuntimeError("SQLPlus JSON payload was not an object.")
        return parsed

    def _visible_regions(self, identity: UserIdentity) -> list[str]:
        roles = set(identity.roles)
        if "HR_ADMIN" in roles:
            return []
        if "SALES_REGION_US" in roles:
            return ["US"]
        return ["US"]

    def _visible_departments(self, identity: UserIdentity) -> list[str]:
        roles = set(identity.roles)
        if "HR_ADMIN" in roles:
            return []
        if "FINANCE_ANALYST" in roles:
            return ["Finance"]
        if "SALES_REGION_US" in roles:
            return ["Sales"]
        return []

    def _can_view_salary(self, identity: UserIdentity) -> bool:
        return bool({"FINANCE_ANALYST", "HR_ADMIN"} & set(identity.roles))


def _sqlplus_script(sql: str) -> str:
    return f"""
set echo off
set feedback off
set heading off
set pagesize 0
set linesize 32767
set long 1000000
set longchunksize 32767
set serveroutput on size unlimited
set termout on
set trimspool on
set verify off
whenever sqlerror exit sql.sqlcode

{sql}

exit
"""


def _access_select_sql() -> str:
    return """
        SELECT JSON_OBJECT(
          'user' VALUE SYS_CONTEXT('USERENV','AUTHENTICATED_IDENTITY'),
          'current_user' VALUE SYS_CONTEXT('USERENV','CURRENT_USER'),
          'authentication_method' VALUE SYS_CONTEXT('USERENV','AUTHENTICATION_METHOD'),
          'roles' VALUE COALESCE(
            (SELECT JSON_ARRAYAGG(role_name ORDER BY role_name RETURNING CLOB)
               FROM v$end_user_data_role),
            TO_CLOB('[]')
          ) FORMAT JSON
          RETURNING CLOB
        )
        FROM dual
        """


def _employees_select_sql(query: str) -> str:
    query_literal = _sql_literal(query.strip().lower())
    return f"""
        WITH filter_value AS (
          SELECT {query_literal} AS q FROM dual
        ),
        visible_employees AS (
          SELECT
            employee_id,
            first_name,
            last_name,
            ssn,
            salary,
            department_id,
            manager_id
          FROM hr.employees, filter_value
          WHERE q IS NULL
             OR q = ''
             OR LOWER(
                  first_name || ' ' || last_name || ' ' ||
                  employee_id || ' ' || department_id || ' ' ||
                  NVL(manager_id, -1)
                ) LIKE '%' || q || '%'
          ORDER BY employee_id
        )
        SELECT JSON_OBJECT(
          'user' VALUE SYS_CONTEXT('USERENV','AUTHENTICATED_IDENTITY'),
          'current_user' VALUE SYS_CONTEXT('USERENV','CURRENT_USER'),
          'authentication_method' VALUE SYS_CONTEXT('USERENV','AUTHENTICATION_METHOD'),
          'roles' VALUE COALESCE(
            (SELECT JSON_ARRAYAGG(role_name ORDER BY role_name RETURNING CLOB)
               FROM v$end_user_data_role),
            TO_CLOB('[]')
          ) FORMAT JSON,
          'rows' VALUE COALESCE(
            (SELECT JSON_ARRAYAGG(
              JSON_OBJECT(
                'employee_id' VALUE employee_id,
                'first_name' VALUE first_name,
                'last_name' VALUE last_name,
                'name' VALUE first_name || ' ' || last_name,
                'ssn' VALUE ssn,
                'salary' VALUE salary,
                'department_id' VALUE department_id,
                'manager_id' VALUE manager_id
                RETURNING CLOB
              )
              ORDER BY employee_id
              RETURNING CLOB
            )
            FROM visible_employees),
            TO_CLOB('[]')
          ) FORMAT JSON
          RETURNING CLOB
        )
        FROM dual
        """


def _emit_json_sql(select_sql: str) -> str:
    return f"""
DECLARE
  l_json CLOB;
  l_pos  PLS_INTEGER := 1;
BEGIN
  {select_sql}
  INTO l_json;

  DBMS_OUTPUT.PUT_LINE('{SQLPLUS_JSON_BEGIN}');
  WHILE l_pos <= DBMS_LOB.GETLENGTH(l_json) LOOP
    DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(l_json, 30000, l_pos));
    l_pos := l_pos + 30000;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('{SQLPLUS_JSON_END}');
END;
/
"""


def _sql_literal(value: str) -> str:
    if value == "":
        return "NULL"
    return "'" + value.replace("'", "''") + "'"


def _extract_between_markers(output: str) -> str:
    begin = output.find(SQLPLUS_JSON_BEGIN)
    end = output.find(SQLPLUS_JSON_END)
    if begin == -1 or end == -1 or end <= begin:
        raise RuntimeError(_short_sqlplus_error(output))
    return output[begin + len(SQLPLUS_JSON_BEGIN) : end].strip()


def _short_sqlplus_error(output: str) -> str:
    lines = [line.rstrip() for line in output.splitlines() if line.strip()]
    interesting = [
        line
        for line in lines
        if line.startswith(("ORA-", "SP2-", "TNS-", "DPI-")) or "ERROR" in line.upper()
    ]
    if not interesting:
        interesting = lines[-12:]
    details = "\n".join(interesting[-12:])
    return (
        "SQLPlus could not query Oracle through the Entra-enabled hrdb alias.\n"
        f"{details}"
    )
