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
            completed.add("create_schema")

            try:
                cursor.execute("select count(*) from APPLAB.customers")
                customer_count = cursor.fetchone()[0]
            except oracledb.DatabaseError:
                customer_count = 0
            if customer_count >= 22:
                completed.update({"load_data", "show_architecture"})

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
    return completed


def lab_state(settings: AdminSettings, password: str) -> dict:
    """Read the current authorization result as MARVIN, never infer it in Flask."""
    with database_connection(settings, "MARVIN", password) as connection:
        with connection.cursor() as cursor:
            cursor.execute("select * from APPLAB.customers order by revenue desc")
            columns = [column[0].lower() for column in cursor.description]
            row_count = sum(1 for _ in cursor)
            cursor.execute("select ora_end_user_context.username from dual")
            (end_user,) = cursor.fetchone()
            cursor.execute("select role_name from v$end_user_data_role order by role_name")
            data_roles = [row[0] for row in cursor]
    return {
        "end_user": end_user,
        "data_roles": data_roles,
        "row_count": row_count,
        "visible_columns": columns,
    }
