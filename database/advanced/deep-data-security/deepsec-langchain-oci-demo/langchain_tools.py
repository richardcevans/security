# Copyright (c) 2026, Oracle and/or its affiliates.
# LangChain tools for the Oracle HR demo application.
# Provides HR-oriented helper tools, read-only SQL access, update proposals,
# and execution of explicitly confirmed changes for the authenticated session.
#
# Dependencies:
# - langchain_core
# - python-oracledb
# - Oracle Deep Data Security end-user security provider
# - app_config.py
# - get_user_token.py

from __future__ import annotations

import re
import traceback
from typing import Optional

from langchain_core.tools import tool

# Demo schema focus.
HR_OWNER = "HR"
HR_EMPLOYEES_TABLE = "EMPLOYEES"

_TABLE_NAME_RE = re.compile(r"^[A-Z][A-Z0-9_$#]*$")

_SQL_TABLE_REF_RE = re.compile(
    r"(\b(?:FROM|JOIN|UPDATE|INTO|DELETE\s+FROM)\s+)"
    r"([A-Z][A-Z0-9_$#]*)(?!\s*\.)",
    re.IGNORECASE,
)

_MUTATION_SQL_RE = re.compile(
    r"^(?:"
    r"UPDATE\s+(?:HR\.)?(?:EMPLOYEES|PERFORMANCE_NOTES)\b|"
    r"INSERT\s+INTO\s+(?:HR\.)?PERFORMANCE_NOTES\b|"
    r"DELETE\s+FROM\s+(?:HR\.)?PERFORMANCE_NOTES\b"
    r")",
    re.IGNORECASE,
)

_UNQUALIFIED_MUTATION_TABLE_RE = re.compile(
    r"^(UPDATE\s+|INSERT\s+INTO\s+|DELETE\s+FROM\s+)"
    r"(EMPLOYEES|PERFORMANCE_NOTES)\b",
    re.IGNORECASE,
)


def _clean_sql(query: str) -> str:
    """Remove presentation formatting and one trailing SQL terminator."""
    return (
        query.replace("```sql", "")
        .replace("```", "")
        .strip()
        .rstrip(";")
        .strip()
    )


def _qualify_unqualified_mutation_table(query: str) -> str:
    """Qualify the supported unqualified mutation targets with the HR owner."""
    return _UNQUALIFIED_MUTATION_TABLE_RE.sub(
        lambda match: f"{match.group(1)}{HR_OWNER}.{match.group(2)}",
        query,
        count=1,
    )


def execute_confirmed_mutation(connection_factory, query: str) -> str:
    """
    Execute one user-confirmed HR mutation.

    The CLI confirmation gate calls this function directly; it is deliberately
    not exposed as an LLM tool. Deep Data Security still evaluates the current
    end-user context, data-role grants, allowed columns, and row predicates.
    """
    raw_query = query.replace("```sql", "").replace("```", "").strip()
    clean_query = _qualify_unqualified_mutation_table(_clean_sql(raw_query))
    normalized = clean_query.upper()

    if not clean_query:
        return "DATABASE_ERROR: Empty update request."
    if ";" in clean_query:
        return "DATABASE_ERROR: Only one SQL statement may be confirmed."
    if not _MUTATION_SQL_RE.match(clean_query):
        return (
            "DATABASE_ERROR: Confirmed changes are limited to UPDATE on "
            "HR.EMPLOYEES or HR.PERFORMANCE_NOTES, INSERT into "
            "HR.PERFORMANCE_NOTES, and DELETE from HR.PERFORMANCE_NOTES."
        )
    if normalized.startswith(("UPDATE ", "DELETE ")) and not re.search(
        r"\bWHERE\b", normalized
    ):
        return "DATABASE_ERROR: UPDATE and DELETE statements must include a WHERE clause."

    try:
        with connection_factory() as conn:
            with conn.cursor() as cursor:
                cursor.execute(clean_query)
                affected_rows = cursor.rowcount
                if affected_rows == 0:
                    conn.rollback()
                    return "No rows were changed; the requested record was not eligible."
                conn.commit()
                return (
                    "Change completed successfully. "
                    f"Rows affected: {affected_rows}."
                )
    except Exception as exc:
        return f"DATABASE_ERROR: {exc}"


def _hr_table_names(conn) -> set[str]:
    """
    Return the set of table names visible in the HR schema.
    """
    with conn.cursor() as cursor:
        cursor.execute(
            """
            SELECT table_name
            FROM all_tables
            WHERE owner = :owner
            """,
            owner=HR_OWNER,
        )
        return {
            str(row[0]).upper()
            for row in cursor.fetchall()
            if row and row[0]
        }


def _rewrite_unqualified_hr_tables(query: str, hr_tables: set[str]) -> str:
    """
    Qualify bare HR table references like:
      FROM employees   -> FROM HR.EMPLOYEES
      JOIN departments -> JOIN HR.DEPARTMENTS
    Only rewrites names that exist in the HR catalog.
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


def build_system_prompt(user: str, agent_mode: str = "hr") -> str:
    """
    Build system instructions for the selected agent mode.
    """
    if agent_mode == "compensation":
        return f"""
        You are an Oracle HR salary-summary assistant for a CLI demo.

        Authenticated user: {user}

        You may only answer aggregate salary questions for HR.EMPLOYEES.
        Use the available tools only to provide salary aggregates such as:
        - min salary
        - max salary
        - average salary
        - employee count
        - visible salary count

        These are the available salary tools:
        - get_salary_summary
        - get_job_pay_range
        - get_salary_statistics_by_location

        Rules:
        - Do not answer row-level employee questions.
        - Do not reveal individual employee records.
        - Do not use SQL directly.
        - If the user asks for anything outside aggregate salary analysis, explain that this agent only handles salary summaries.
        - Salary or other protected fields may come back as NULL when not visible; treat NULL as "not visible" rather than missing data.
        """.strip()

    return f"""
    You are an Oracle HR assistant for a CLI demo.

    Authenticated user: {user}

    Use the tools available to you as needed. The database enforces access
    control through Deep Data Security / XS security, so you should trust
    the session visibility returned by the database.

    Guidance:
    - Use HR schema objects by default.
    - HR.EMPLOYEES is the main demo table, but other HR tables may be queried
      if they help answer the user.
    - Prefer purpose-built HR tools for common requests:
    - get_current_user
    - get_employee
    - search_employees
    - get_my_direct_reports
    - get_salary_summary
    - Use describe_table when you need schema details.
    - Use execute_sql for ad hoc SELECT queries only. It never changes data.
    - If the user asks to change data, first identify the exact target row with
      a SELECT query. Then use propose_update with a single HR UPDATE, INSERT,
      or DELETE statement and a clear change description.
    - Never use execute_sql for a write. propose_update never writes data; the
      CLI separately asks the user to reply exactly "yes" before the proposed
      statement is executed.
    - For another employee's record, first identify the employee_id. For
      performance-note changes, identify the note_id first.
    - For a self-service request using "my", "me", or "I", the proposed SQL
      must use UPPER(user_name) = UPPER(ORA_END_USER_CONTEXT.username) in its
      WHERE clause. Never substitute a literal username, a remembered name, or
      an invented employee_id for ORA_END_USER_CONTEXT.username.
    - If the user asks for "my", "me", or "I", interpret that relative to the
      authenticated database identity.
    - Salary or other protected fields may come back as NULL when not visible;
      treat NULL as "not visible" rather than as missing data.
    - Return responses in plain English unless the user explicitly asks for SQL.
    - Do not invent column names; use describe_table if unsure.
    """.strip()

def create_tools(connection_factory, agent_mode: str = "hr"):
    """Create tools that acquire and release one pooled connection per call."""

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
                with conn.cursor() as cursor:
                    cursor.execute(
                        """
                        SELECT table_name
                        FROM all_tables
                        WHERE owner = :owner
                        ORDER BY table_name
                        """,
                        owner=HR_OWNER,
                    )
                    tables = [f"{HR_OWNER}.{row[0]}" for row in cursor.fetchall()]
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
                    if ident.isdigit():
                        cursor.execute(
                            """
                            SELECT employee_id, first_name, last_name, user_name,
                                   phone_number, job_code, manager_id, department_id,
                                   salary, ssn
                            FROM hr.employees
                            WHERE employee_id = :employee_id
                            """,
                            employee_id=int(ident),
                        )
                    else:
                        cursor.execute(
                            """
                            SELECT employee_id, first_name, last_name, user_name,
                                   phone_number, job_code, manager_id, department_id,
                                   salary, ssn
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
                manager_employee_id = _current_employee_id(conn)
                if manager_employee_id is None:
                    return "NO_MATCH: the authenticated user is not mapped to an HR.EMPLOYEES row."
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
    def get_job_pay_range(job_code: str | None = None) -> str:
        """
        Return salary statistics for one job, or for all jobs if no job_code is given.

        Uses visible salary values from HR.EMPLOYEES only.
        """
        try:
            with connection_factory() as conn:
                with conn.cursor() as cursor:
                    if job_code is None:
                        cursor.execute(
                        """
                        SELECT job_code,
                            COUNT(*) AS employee_count,
                            COUNT(salary) AS visible_salary_count,
                            MIN(salary) AS min_salary,
                            AVG(salary) AS avg_salary,
                            MAX(salary) AS max_salary
                        FROM hr.employees
                        GROUP BY job_code
                        ORDER BY job_code
                        """
                    )
                    else:
                        cleaned_job_code = job_code.strip()
                        if not cleaned_job_code:
                            return "ERROR: job_code is required."
                        cursor.execute(
                            """
                            SELECT job_code,
                                COUNT(*) AS employee_count,
                                COUNT(salary) AS visible_salary_count,
                                MIN(salary) AS min_salary,
                                AVG(salary) AS avg_salary,
                                MAX(salary) AS max_salary
                            FROM hr.employees
                            WHERE UPPER(job_code) = UPPER(:job_code)
                            GROUP BY job_code
                            """,
                            job_code=cleaned_job_code,
                        )

                    rows = cursor.fetchall()
                    if not rows:
                        if job_code is None:
                            return "NO_DATA_FOUND"
                        return f"NO_DATA_FOUND for job_code {job_code}"
                    return _format_rows(cursor, rows)

        except Exception as exc:
            return f"DATABASE_ERROR: {exc!r}\n{traceback.format_exc()}"

    @tool
    def get_salary_statistics_by_location(
        city: str | None = None,
        state_province: str | None = None,
        country_id: str | None = None,
    ) -> str:
        """
        Return aggregate salary statistics for employees by location.

        This version only uses HR.EMPLOYEES, HR.DEPARTMENTS, and HR.LOCATIONS.
        It does not join HR.COUNTRIES.
        """
        try:
            with connection_factory() as conn:
                with conn.cursor() as cursor:
                    base_sql = """
                    SELECT l.location_id,
                        l.city,
                        l.state_province,
                        l.country_id,
                        COUNT(*) AS employee_count,
                        COUNT(e.salary) AS visible_salary_count,
                        MIN(e.salary) AS min_salary,
                        AVG(e.salary) AS avg_salary,
                        MAX(e.salary) AS max_salary
                    FROM hr.employees e
                    JOIN hr.departments d
                    ON e.department_id = d.department_id
                    JOIN hr.locations l
                    ON d.location_id = l.location_id
                """

                    binds = {}
                    where_clauses = []

                    if city is not None:
                        where_clauses.append("UPPER(l.city) = UPPER(:city)")
                        binds["city"] = city.strip()

                    if state_province is not None:
                        where_clauses.append(
                            "UPPER(NVL(l.state_province, '')) = UPPER(:state_province)"
                        )
                        binds["state_province"] = state_province.strip()

                    if country_id is not None:
                        where_clauses.append("UPPER(l.country_id) = UPPER(:country_id)")
                        binds["country_id"] = country_id.strip()

                    if where_clauses:
                        base_sql += " WHERE " + " AND ".join(where_clauses)

                    base_sql += """
                    GROUP BY l.location_id,
                            l.city,
                            l.state_province,
                            l.country_id
                    ORDER BY l.city, l.state_province, l.location_id
                """

                    cursor.execute(base_sql, **binds)
                    rows = cursor.fetchall()
                    if not rows:
                        return "NO_DATA_FOUND"
                    return _format_rows(cursor, rows)

        except Exception as exc:
            return f"DATABASE_ERROR: {exc!r}\n{traceback.format_exc()}"


    @tool
    def execute_sql(query: str) -> str:
        """
        Execute a read-only SELECT statement using the current database session.
        For requested changes, use propose_update instead.
        """
        clean_query = _clean_sql(query)

        if not clean_query:
            return "ERROR: Empty SQL statement."
        if not clean_query.upper().startswith("SELECT "):
            return (
                "DATABASE_ERROR: execute_sql supports SELECT statements only. "
                "Use propose_update for a requested change."
            )

        try:
            with connection_factory() as conn:
                def _run_sql(sql_text: str) -> str:
                    with conn.cursor() as cursor:
                        cursor.execute(sql_text)
                        rows = cursor.fetchall()
                        return _format_rows(cursor, rows) if rows else "NO_DATA_FOUND"

                try:
                    return _run_sql(clean_query)
                except Exception as exc:
                    if "ORA-00942" in str(exc):
                        rewritten_query = _rewrite_unqualified_hr_tables(
                            clean_query, _hr_table_names(conn)
                        )
                        if rewritten_query != clean_query:
                            return _run_sql(rewritten_query)
                    return f"DATABASE_ERROR: {exc}"
        except Exception as exc:
            return f"DATABASE_ERROR: {exc}"

    @tool
    def propose_update(sql: str, description: str) -> str:
        """
        Propose one HR database change for explicit CLI confirmation.

        This tool never executes SQL. Use it only after identifying the target
        record with SELECT and include a concise, user-facing description.
        """
        clean_sql = _clean_sql(sql)
        if not clean_sql:
            return "ERROR: A SQL statement is required for the proposed change."
        if not description.strip():
            return "ERROR: A clear description is required for the proposed change."
        if re.match(r"^UPDATE\s+(?:HR\.)?EMPLOYEES\b", clean_sql, re.IGNORECASE):
            if "ORA_END_USER_CONTEXT.USERNAME" not in clean_sql.upper():
                return (
                    "ERROR: Employee self-service updates must use "
                    "UPPER(user_name) = UPPER(ORA_END_USER_CONTEXT.username) "
                    "in the WHERE clause. Do not use a literal username or "
                    "employee_id."
                )
        return "CONFIRMATION_REQUIRED"

    if agent_mode == "compensation":
        return [
            get_current_user,
            get_salary_summary,
            get_job_pay_range,
            get_salary_statistics_by_location,
        ]

    return [
        get_current_user,
        list_tables,
        describe_table,
        get_employee,
        search_employees,
        get_my_direct_reports,
        get_salary_summary,
        execute_sql,
        propose_update,
    ]
