"""Direct local-end-user database access. No application-side authorization."""

from contextlib import contextmanager
from typing import Optional
import oracledb

from config import Settings


def _enable_thick_mode(wallet_location: str) -> None:
    """Use Thick mode only for the legacy mTLS wallet deployment."""
    try:
        oracledb.init_oracle_client(config_dir=wallet_location)
    except oracledb.Error as exc:
        raise RuntimeError(
            "Oracle Instant Client could not be initialized. "
            "Run bash verify_app_server.sh and confirm the client is installed."
        ) from exc


PERSONAS = {
    "MARVIN": {"label": "Marvin — Sales", "role": "Database-managed"},
    "EMMA": {"label": "Emma — Sales", "role": "Database-managed"},
}

QUERY_TEMPLATE = """
    SELECT *
      FROM {schema}.customers
     ORDER BY revenue DESC
"""

END_USER_QUERY = "select ora_end_user_context.username from dual"
DATA_ROLES_QUERY = "select role_name from v$end_user_data_role order by role_name"
ORDER_HISTORY_QUERY = """
    SELECT *
      FROM APPLAB.order_history
     ORDER BY order_date DESC
     FETCH FIRST 50 ROWS ONLY
"""


def oracle_queries(settings: Settings) -> list[str]:
    """Return the Oracle statements used by a customer or AI request."""
    return [
        " ".join(QUERY_TEMPLATE.format(schema=settings.db_schema).split()),
        END_USER_QUERY,
        DATA_ROLES_QUERY,
    ]


@contextmanager
def _connection(settings: Settings, username: str, password: str):
    """Open one direct local end-user session and close it after the request."""
    if not password:
        raise ValueError("Database password is required")
    kwargs = {"user": username, "password": password, "dsn": settings.dsn}
    if settings.wallet_location:
        _enable_thick_mode(settings.wallet_location)
        kwargs.update({"config_dir": settings.wallet_location, "wallet_location": settings.wallet_location})
    connection = oracledb.connect(**kwargs)
    try:
        yield connection
    finally:
        connection.close()


def verify_persona_credentials(settings: Settings, persona: str, password: str) -> dict:
    """Authenticate directly as the chosen local database end user."""
    if persona not in PERSONAS:
        raise ValueError("Choose Marvin or Emma")
    with _connection(settings, persona, password) as connection:
        with connection.cursor() as cursor:
            cursor.execute(END_USER_QUERY)
            (end_user,) = cursor.fetchone()
            cursor.execute(DATA_ROLES_QUERY)
            data_roles = ", ".join(row[0] for row in cursor) or "No active data role"
    return {"end_user": end_user, "data_role": data_roles}


def fetch_authorized_customers(settings: Settings, persona: str, password: str) -> tuple[list[dict], dict]:
    """Run the identical query before and after the Deep Sec role change."""
    if persona not in PERSONAS:
        raise ValueError("Choose Marvin or Emma")
    query = QUERY_TEMPLATE.format(schema=settings.db_schema)
    with _connection(settings, persona, password) as connection:
        with connection.cursor() as cursor:
            cursor.execute(query)
            names = [column[0].lower() for column in cursor.description]
            rows = [dict(zip(names, row)) for row in cursor]
            cursor.execute(END_USER_QUERY)
            (end_user,) = cursor.fetchone()
            cursor.execute(DATA_ROLES_QUERY)
            data_roles = ", ".join(row[0] for row in cursor) or "No active data role"
    return rows, {"end_user": end_user, "data_role": data_roles}


def fetch_order_history(settings: Settings, persona: str, password: str) -> tuple[list[dict], int, dict[str, str]]:
    """Return Order History rows, their authorized count, and session context."""
    if persona not in PERSONAS:
        raise ValueError("Choose Marvin or Emma")
    with _connection(settings, persona, password) as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT COUNT(*) FROM APPLAB.order_history")
            row_count = int(cursor.fetchone()[0])
            cursor.execute(ORDER_HISTORY_QUERY)
            columns = [column[0].lower() for column in cursor.description]
            rows = [dict(zip(columns, row)) for row in cursor]
            cursor.execute(END_USER_QUERY)
            (end_user,) = cursor.fetchone()
            cursor.execute(DATA_ROLES_QUERY)
            data_roles = ", ".join(row[0] for row in cursor) or "No active data role"
    return rows, row_count, {"end_user": end_user, "data_role": data_roles}


def execute_vibe_statement(settings: Settings, persona: str, password: str, sql: str) -> dict:
    """Run one published Vibe statement as the Customer Sales App end user, never as ADMIN."""
    if persona not in PERSONAS:
        raise ValueError("Choose Marvin or Emma")
    operation = sql.lstrip().split(None, 1)[0].upper()
    # A WITH clause is a query in the Vibe contract. DML starts with its own
    # keyword, so it remains unambiguous to present in the browser.
    if operation == "WITH":
        operation = "SELECT"
    with _connection(settings, persona, password) as connection:
        with connection.cursor() as cursor:
            if operation == "SELECT":
                cursor.execute(f"SELECT COUNT(*) FROM ({sql})")
                row_count = int(cursor.fetchone()[0])
                cursor.execute(sql)
                if not cursor.description:
                    raise ValueError("The published Vibe query did not return rows.")
                columns = [column[0].lower() for column in cursor.description]
                rows = [dict(zip(columns, row)) for row in cursor.fetchmany(100)]
                affected_rows = None
            elif operation in {"INSERT", "UPDATE", "DELETE"}:
                cursor.execute(sql)
                affected_rows = max(cursor.rowcount, 0)
                connection.commit()
                row_count = affected_rows
                rows = []
            else:
                raise ValueError("Vibe statements must start with SELECT, INSERT, UPDATE, or DELETE.")
            cursor.execute(END_USER_QUERY)
            (end_user,) = cursor.fetchone()
            cursor.execute(DATA_ROLES_QUERY)
            data_roles = ", ".join(row[0] for row in cursor) or "No active data role"
    return {
        "operation": operation,
        "rows": rows,
        "row_count": row_count,
        "affected_rows": affected_rows,
        "context": {"end_user": end_user, "data_role": data_roles},
    }


def oracle_error_code(error: Exception) -> Optional[int]:
    """Return an Oracle error number without exposing Oracle text to callers."""
    if not isinstance(error, oracledb.DatabaseError) or not error.args:
        return None
    return getattr(error.args[0], "code", None)
