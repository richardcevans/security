# Copyright (c) 2026, Oracle and/or its affiliates.
# LangChain tools for the Oracle HR demo application.
# Provides HR-oriented helper tools and a generic SQL escape hatch for
# the authenticated database session.
#
# Dependencies:
# - langchain_core
# - python-oracledb
# - Oracle Deep Data Security end-user security provider
# - app_config.py

from __future__ import annotations

import re
import traceback
from typing import Optional

from langchain_core.tools import tool

# Demo schema focus.
HR_OWNER = "HR"
HR_EMPLOYEES_TABLE = "EMPLOYEES"
HR_DEMO_TABLES = {HR_EMPLOYEES_TABLE}
HR_DEMO_SCHEMAS = {
    HR_EMPLOYEES_TABLE: [
        ("EMPLOYEE_ID", "NUMBER", "N", 22),
        ("FIRST_NAME", "VARCHAR2", "Y", 50),
        ("LAST_NAME", "VARCHAR2", "Y", 50),
        ("JOB_CODE", "VARCHAR2", "Y", 10),
        ("DEPARTMENT_ID", "NUMBER", "Y", 22),
        ("SSN", "VARCHAR2", "Y", 20),
        ("PHOTO", "BLOB", "Y", 4000),
        ("PHONE_NUMBER", "VARCHAR2", "Y", 30),
        ("SALARY", "NUMBER", "Y", 22),
        ("USER_NAME", "VARCHAR2", "Y", 128),
        ("MANAGER_ID", "NUMBER", "Y", 22),
    ],
}

_TABLE_NAME_RE = re.compile(r"^[A-Z][A-Z0-9_$#]*$")

_SQL_TABLE_REF_RE = re.compile(
    r"(\b(?:FROM|JOIN|UPDATE|INTO|DELETE\s+FROM)\s+)"
    r"([A-Z][A-Z0-9_$#]*)(?!\s*\.)",
    re.IGNORECASE,
)


def _hr_table_names(conn) -> set[str]:
    """
    Return HR table names for the demo, supplemented by catalog visibility.
    """
    table_names = set(HR_DEMO_TABLES)
    try:
        with conn.cursor() as cursor:
            cursor.execute(
                """
                SELECT table_name
                FROM all_tables
                WHERE owner = :owner
                """,
                owner=HR_OWNER,
            )
            table_names.update(
                str(row[0]).upper()
                for row in cursor.fetchall()
                if row and row[0]
            )
    except Exception:
        pass
    return table_names


def _rewrite_unqualified_hr_tables(query: str, hr_tables: set[str]) -> str:
    """
    Qualify bare HR table references like:
      FROM employees   -> FROM HR.EMPLOYEES
    Only rewrites names that exist in the demo schema or HR catalog.
    """

    def _replace(match) -> str:
        prefix = match.group(1)
        table = match.group(2)
        if table.upper() in hr_tables:
            return f"{prefix}{HR_OWNER}.{table}"
        return match.group(0)

    return _SQL_TABLE_REF_RE.sub(_replace, query)


def _normalize_hr_table_name(table_name: str) -> tuple[str, str]:
    """
    Validate and normalize a table name to HR.<TABLE>.
    Accepts either EMPLOYEES or HR.EMPLOYEES.
    """
    raw = table_name.strip().upper()
    if "." in raw:
        owner, table = raw.split(".", 1)
    else:
        owner, table = HR_OWNER, raw

    if owner != HR_OWNER:
        raise ValueError("Only HR schema objects are supported by this demo.")
    if not _TABLE_NAME_RE.match(table):
        raise ValueError(f"Invalid table name: {table_name}")

    return owner, table


def _format_rows(cursor, rows) -> str:
    """
    Convert query rows to a compact readable table.
    """
    headers = [col[0] for col in cursor.description]
    lines = [" | ".join(headers)]
    for row in rows:
        lines.append(
            " | ".join("NULL" if value is None else str(value) for value in row)
        )
    return "\n".join(lines)


def _current_employee_id(conn) -> Optional[int]:
    """
    Resolve the authenticated end user's employee_id from HR.EMPLOYEES.
    Returns None if the current user is not mapped to a row.
    """
    with conn.cursor() as cursor:
        cursor.execute(
            """
            SELECT employee_id
            FROM hr.employees
            WHERE UPPER(user_name) = UPPER(ORA_END_USER_CONTEXT.username)
            """
        )
        row = cursor.fetchone()
        return int(row[0]) if row and row[0] is not None else None


def get_username(conn) -> str:
    """
    Return authenticated end-user identity from the database session.
    """
    with conn.cursor() as cursor:
        cursor.execute(
            "SELECT ORA_END_USER_CONTEXT.username FROM sys.dual"
        )
        row = cursor.fetchone()
        return row[0] if row and row[0] else "unknown"


def build_system_prompt(user: str) -> str:
    """
    Build system instructions for the HR agent.
    """
    return f"""
    You are an Oracle HR assistant for a CLI demo.

    Authenticated user: {user}

    Use the tools available to you as needed. The database enforces access
    control through Deep Data Security / XS security, so you should trust
    the session visibility returned by the database.

    Guidance:
    - Use HR schema objects by default.
    - This lab setup creates HR.EMPLOYEES as the demo table.
    - HR.EMPLOYEES columns are employee_id, first_name, last_name, job_code,
      department_id, ssn, photo, phone_number, salary, user_name, manager_id.
    - Prefer purpose-built HR tools for common requests:
    - get_current_user
    - get_employee
    - search_employees
    - get_my_direct_reports
    - get_salary_summary
    - Use describe_table when you need schema details.
    - Use execute_sql for ad hoc SQL, complex queries, or write operations that
      are allowed for the current database identity but always prompt the user
      for a confirmation message before making any changes or writes in the
      database - only proceed if the user responds in the affirmative.
    - If the user asks for "my", "me", or "I", interpret that relative to the
      authenticated database identity.
    - Salary or other protected fields may come back as NULL when not visible;
      treat NULL as "not visible" rather than as missing data.
    - Return responses in plain English unless the user explicitly asks for SQL.
    - Do not invent column names; use describe_table if unsure.
    """.strip()


def create_tools(connection_factory):
    """
    Create the LangChain tool set using a per-tool database connection.
    """

    @tool
    def get_current_user() -> str:
        """Return the authenticated end-user identity visible to the database session."""
        try:
            with connection_factory() as conn:
                return get_username(conn)
        except Exception as exc:
            return f"DATABASE_ERROR: {exc}"

    @tool
    def list_tables() -> str:
        """List tables available in the HR schema."""
        try:
            with connection_factory() as conn:
                tables = [
                    f"{HR_OWNER}.{table_name}"
                    for table_name in sorted(_hr_table_names(conn))
                ]

            if not tables:
                return "No HR tables found."
            return "Tables:\n" + "\n".join(tables)
        except Exception as exc:
            return f"DATABASE_ERROR: {exc}"

    @tool
    def describe_table(table_name: str) -> str:
        """Return schema details for an HR table."""
        try:
            owner, table = _normalize_hr_table_name(table_name)
        except Exception as exc:
            return f"ERROR: {exc}"

        try:
            with connection_factory() as conn:
                with conn.cursor() as cursor:
                    try:
                        cursor.execute(
                            """
                            SELECT column_name, data_type, nullable, data_length
                            FROM all_tab_columns
                            WHERE owner = :owner
                              AND table_name = :table_name
                            ORDER BY column_id
                            """,
                            owner=owner,
                            table_name=table,
                        )
                        rows = cursor.fetchall()
                    except Exception:
                        rows = []

            if not rows:
                rows = HR_DEMO_SCHEMAS.get(table, [])

            if not rows:
                return f"No schema found for {owner}.{table}."

            lines = [f"Schema for {owner}.{table}:"]
            for column_name, data_type, nullable, data_length in rows:
                lines.append(
                    f"- {column_name} | {data_type} | nullable={nullable} | length={data_length}"
                )
            return "\n".join(lines)
        except Exception as exc:
            return f"ERROR fetching schema: {exc}"

    @tool
    def get_employee(employee_identifier: str) -> str:
        """
        Return a single employee by employee ID or user name.

        The authenticated database session determines which rows and
        columns are visible.
        """
        ident = employee_identifier.strip()
        if not ident:
            return "ERROR: employee_identifier is required."

        try:
            with connection_factory() as conn:
                with conn.cursor() as cursor:
                    # Look up by employee ID when a numeric identifier is supplied.
                    if ident.isdigit():
                        cursor.execute(
                            """
                            SELECT employee_id,
                                   first_name,
                                   last_name,
                                   user_name,
                                   phone_number,
                                   job_code,
                                   manager_id,
                                   department_id,
                                   salary,
                                   ssn
                            FROM hr.employees
                            WHERE employee_id = :employee_id
                            """,
                            employee_id=int(ident),
                        )
                    # Otherwise treat the identifier as a user name.
                    else:
                        cursor.execute(
                            """
                            SELECT employee_id,
                                   first_name,
                                   last_name,
                                   user_name,
                                   phone_number,
                                   job_code,
                                   manager_id,
                                   department_id,
                                   salary,
                                   ssn
                            FROM hr.employees
                            WHERE UPPER(user_name) = UPPER(:user_name)
                            """,
                            user_name=ident,
                        )

                    rows = cursor.fetchall()
                    if not rows:
                        return f"NO_DATA_FOUND for {employee_identifier}"

                    return _format_rows(cursor, rows)

        except Exception as exc:
            return f"DATABASE_ERROR: {exc}"

    @tool
    def search_employees(query: str, limit: int = 10) -> str:
        """
        Search employees by name, user name, or job code.

        This tool is intended for keyword searches. Use execute_sql for
        listing, sorting, ranking, or other ad hoc SQL requests.
        """
        term = query.strip()
        if not term:
            return "ERROR: query is required."

        # Apply reasonable limits to the number of returned rows.
        if limit < 1:
            limit = 1
        if limit > 50:
            limit = 50

        pattern = f"%{term}%"

        try:
            with connection_factory() as conn:
                with conn.cursor() as cursor:
                    cursor.execute(
                        """
                        SELECT *
                        FROM (
                            SELECT employee_id,
                                   first_name,
                                   last_name,
                                   user_name,
                                   phone_number,
                                   job_code,
                                   manager_id,
                                   department_id,
                                   salary
                            FROM hr.employees
                            WHERE UPPER(first_name || ' ' || last_name) LIKE UPPER(:pattern)
                               OR UPPER(user_name) LIKE UPPER(:pattern)
                               OR UPPER(job_code) LIKE UPPER(:pattern)
                            ORDER BY employee_id
                        )
                        WHERE ROWNUM <= :limit
                        """,
                        pattern=pattern,
                        limit=limit,
                    )

                    rows = cursor.fetchall()
                    if not rows:
                        return "NO_DATA_FOUND"

                    return _format_rows(cursor, rows)

        except Exception as exc:
            return f"DATABASE_ERROR: {exc}"

    @tool
    def get_my_direct_reports(limit: int = 25) -> str:
        """
        Return the authenticated user's direct reports.
        """
        # Apply reasonable limits to the number of returned rows.
        if limit < 1:
            limit = 1
        if limit > 100:
            limit = 100

        try:
            with connection_factory() as conn:
                # Resolve the authenticated user to an HR employee record.
                manager_employee_id = _current_employee_id(conn)
                if manager_employee_id is None:
                    return (
                        "NO_MATCH: the authenticated user is not mapped to an HR.EMPLOYEES row."
                    )

                with conn.cursor() as cursor:
                    cursor.execute(
                        """
                        SELECT *
                        FROM (
                            SELECT employee_id,
                                   first_name,
                                   last_name,
                                   user_name,
                                   job_code,
                                   manager_id,
                                   department_id,
                                   salary
                            FROM hr.employees
                            WHERE manager_id = :manager_employee_id
                            ORDER BY employee_id
                        )
                        WHERE ROWNUM <= :limit
                        """,
                        manager_employee_id=manager_employee_id,
                        limit=limit,
                    )

                    rows = cursor.fetchall()
                    if not rows:
                        return "NO_DIRECT_REPORTS"

                    return _format_rows(cursor, rows)

        except Exception as exc:
            return f"DATABASE_ERROR: {exc}"

    @tool
    def get_salary_summary(department_id: int | None = None) -> str:
        """
        Summarize visible salary data for the current database identity.
        Protected salaries remain NULL or absent if not visible.
        """
        try:
            with connection_factory() as conn:
                with conn.cursor() as cursor:
                    if department_id is None:
                        cursor.execute(
                            """
                            SELECT COUNT(*) AS employee_count,
                                   COUNT(salary) AS visible_salary_count,
                                   MIN(salary) AS min_salary,
                                   AVG(salary) AS avg_salary,
                                   MAX(salary) AS max_salary
                            FROM hr.employees
                            """
                        )
                    else:
                        cursor.execute(
                            """
                            SELECT COUNT(*) AS employee_count,
                                   COUNT(salary) AS visible_salary_count,
                                   MIN(salary) AS min_salary,
                                   AVG(salary) AS avg_salary,
                                   MAX(salary) AS max_salary
                            FROM hr.employees
                            WHERE department_id = :department_id
                            """,
                            department_id=department_id,
                        )

                    row = cursor.fetchone()
                    if not row:
                        return "NO_DATA_FOUND"

                    employee_count, visible_salary_count, min_salary, avg_salary, max_salary = row
                    department_label = "all departments" if department_id is None else f"department {department_id}"
                    return (
                        f"Salary summary for {department_label}:\n"
                        f"- Employee rows: {employee_count}\n"
                        f"- Visible salary values: {visible_salary_count}\n"
                        f"- Min salary: {min_salary if min_salary is not None else 'NULL'}\n"
                        f"- Avg salary: {avg_salary if avg_salary is not None else 'NULL'}\n"
                        f"- Max salary: {max_salary if max_salary is not None else 'NULL'}"
                    )
        except Exception as exc:
            return f"DATABASE_ERROR: {exc!r}\n{traceback.format_exc()}"

    @tool
    def execute_sql(query: str) -> str:
        """
        Execute SQL or PL/SQL using the current database session.
        The database security model determines what succeeds.
        """
        clean_query = (
            query.replace("```sql", "")
            .replace("```", "")
            .strip()
            .rstrip(";")
        )

        if not clean_query:
            return "ERROR: Empty SQL statement."

        try:
            with connection_factory() as conn:
                def _run_sql(sql_text: str) -> str:
                    with conn.cursor() as cursor:
                        cursor.execute(sql_text)

                        if cursor.description:
                            rows = cursor.fetchall()
                            if not rows:
                                return "NO_DATA_FOUND"
                            return _format_rows(cursor, rows)

                        try:
                            conn.commit()
                        except Exception:
                            pass

                        rowcount = cursor.rowcount
                        if rowcount is None or rowcount < 0:
                            return "SUCCESS"
                        return f"SUCCESS: {rowcount} row(s) affected"

                try:
                    return _run_sql(clean_query)
                except Exception as exc:
                    error_text = str(exc)

                    if "ORA-00942" in error_text:
                        try:
                            hr_tables = _hr_table_names(conn)
                            rewritten_query = _rewrite_unqualified_hr_tables(
                                clean_query,
                                hr_tables,
                            )
                            if rewritten_query != clean_query:
                                return _run_sql(rewritten_query)
                        except Exception:
                            pass

                    return f"DATABASE_ERROR: {exc}"
        except Exception as exc:
            return f"DATABASE_ERROR: {exc}"

    return [
        get_current_user,
        list_tables,
        describe_table,
        get_employee,
        search_employees,
        get_my_direct_reports,
        get_salary_summary,
        execute_sql,
    ]
