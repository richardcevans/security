"""Direct ADMIN database access for the fixed Deep Sec administrator console."""

from contextlib import contextmanager

import oracledb

from admin_config import AdminSettings


def _enable_thick_mode(config_dir: str) -> None:
    try:
        # In Thick mode, Oracle Net reads aliases during client initialization.
        # Set the supplied generated wallet directory here instead of letting
        # Instant Client fall back to its own network/admin directory.
        oracledb.init_oracle_client(config_dir=config_dir)
    except oracledb.Error as exc:
        raise RuntimeError("Oracle Instant Client could not be initialized.") from exc


@contextmanager
def database_connection(settings: AdminSettings, username: str, password: str):
    if not password:
        raise ValueError("Database password is required")
    _enable_thick_mode(settings.wallet_location)
    connection = oracledb.connect(
        user=username,
        password=password,
        dsn=settings.dsn,
        config_dir=settings.wallet_location,
        wallet_location=settings.wallet_location,
    )
    try:
        yield connection
    finally:
        connection.close()


def verify_admin(settings: AdminSettings, password: str) -> str:
    """Authenticate the console user directly as the ADB ADMIN account."""
    with database_connection(settings, "ADMIN", password) as connection:
        with connection.cursor() as cursor:
            cursor.execute("select user from dual")
            return cursor.fetchone()[0]


def completed_setup_actions(settings: AdminSettings, password: str) -> set[str]:
    """Infer the guided setup position from durable Oracle state.

    Browser sessions are deliberately short-lived, so setup progress must never
    depend on a Flask login surviving. The authentication-model script is
    informational and creates no object; a loaded customer table therefore
    represents both that step and the preceding data-load step.
    """
    completed: set[str] = set()
    with database_connection(settings, "ADMIN", password) as connection:
        with connection.cursor() as cursor:
            cursor.execute("select count(*) from all_users where username = 'APPLAB'")
            if cursor.fetchone()[0] != 1:
                return completed
            try:
                cursor.execute("select count(*) from APPLAB.customers")
                customer_count = cursor.fetchone()[0]
            except oracledb.DatabaseError:
                customer_count = 0
            if customer_count >= 22:
                completed.add("setup_database")

    try:
        # CREATE END USER is not consistently represented in ordinary user
        # dictionary views across ADB releases. A direct local sign-in is the
        # authoritative test for the MARVIN setup step.
        with database_connection(settings, "MARVIN", password) as connection:
            with connection.cursor() as cursor:
                cursor.execute("select 1 from dual")
                cursor.fetchone()
                cursor.execute("select role_name from v$end_user_data_role")
                active_roles = {row[0] for row in cursor}
        # MARVIN can be created only after the data roles exist.
        completed.update({"create_roles", "create_marvin"})
        if "APP_FULL_ACCESS" in active_roles:
            completed.add("enable_full_access")
        if "APP_SALES_EMPLOYEE" in active_roles:
            completed.add("enable_employee")
        if "APP_SALES_MANAGER" in active_roles:
            completed.add("enable_manager")
    except oracledb.DatabaseError:
        pass

    try:
        # Emma is the fixed comparison user. Authenticate directly because
        # local end users are not reliably represented in ordinary user views.
        with database_connection(settings, "EMMA", password) as connection:
            with connection.cursor() as cursor:
                cursor.execute("select 1 from dual")
                cursor.fetchone()
        completed.add("create_emma")
    except oracledb.DatabaseError:
        pass

    try:
        with database_connection(settings, "ADMIN", password) as connection:
            with connection.cursor() as cursor:
                cursor.execute("select count(*) from all_tables where owner = 'APPLAB' and table_name = 'SALES_REPS'")
                if cursor.fetchone()[0] == 1:
                    completed.add("create_manager_context")
    except oracledb.DatabaseError:
        pass
    return completed


def validation_comparison(settings: AdminSettings, password: str) -> dict:
    """Return Oracle-derived roles and grants for the Emma/Marvin comparison."""
    query = "SELECT * FROM APPLAB.customers ORDER BY revenue DESC"
    with database_connection(settings, "ADMIN", password) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                select grant_name,
                       grantee,
                       predicate,
                       listagg(nvl(column_name, 'ALL COLUMNS'), ', ')
                         within group (order by column_name) as columns
                  from dba_data_grants
                 where object_owner = 'APPLAB'
                   and object_name = 'CUSTOMERS'
                 group by grant_name, grantee, predicate
                 order by grantee, grant_name
                """
            )
            grants = [
                {"name": row[0], "role": row[1], "predicate": row[2] or "All rows", "columns": row[3]}
                for row in cursor
            ]

    personas = []
    for username in ("EMMA", "MARVIN"):
        try:
            with database_connection(settings, username, password) as connection:
                with connection.cursor() as cursor:
                    cursor.execute("select role_name from v$end_user_data_role order by role_name")
                    roles = [row[0] for row in cursor]
                    cursor.execute("select count(*) from applab.customers")
                    row_count = cursor.fetchone()[0]
            personas.append(
                {
                    "username": username,
                    "roles": roles,
                    "row_count": row_count,
                    "grants": [grant for grant in grants if grant["role"] in roles],
                    "available": True,
                }
            )
        except oracledb.DatabaseError as exc:
            personas.append(
                {
                    "username": username,
                    "roles": [],
                    "row_count": None,
                    "grants": [],
                    "available": False,
                    "message": str(exc),
                }
            )
    return {"query": query, "personas": personas}


def lab_state(settings: AdminSettings, password: str) -> dict:
    """Read the current authorization result as MARVIN, never infer it in Flask."""
    with database_connection(settings, "MARVIN", password) as connection:
        with connection.cursor() as cursor:
            cursor.execute("select * from APPLAB.customers order by revenue desc")
            columns = [column[0].lower() for column in cursor.description]
            row_count = sum(1 for _ in cursor)
            cursor.execute("select ora_end_user_context.username from dual")
            (end_user,) = cursor.fetchone()
            cursor.execute(
                """
                select distinct sales_rep
                  from applab.customers
                 where upper(sales_rep) <> upper(ora_end_user_context.username)
                 order by sales_rep
                """
            )
            direct_reports = [row[0] for row in cursor]
            cursor.execute("select role_name from v$end_user_data_role order by role_name")
            data_roles = [row[0] for row in cursor]
    return {
        "end_user": end_user,
        "data_roles": data_roles,
        "row_count": row_count,
        "visible_columns": columns,
        "direct_reports": direct_reports,
    }
