import oracledb

from deal_db import connect


DDL = [
    """
    create table loan_applications (
        id number primary key,
        customer_name varchar2(100) not null,
        loan_amount number(12,2) not null,
        purpose varchar2(100) not null,
        status varchar2(40) not null,
        officer_notes varchar2(4000),
        customer_ssn varchar2(20),
        customer_income number(12,2),
        customer_credit_score number(4),
        underwriting_decision varchar2(40),
        risk_score number(5,2),
        underwriting_notes varchar2(4000),
        assigned_officer varchar2(40) not null,
        in_underwriting_queue char(1) check (in_underwriting_queue in ('Y','N'))
    )
    """,
    """
    create table loan_policies (
        id number primary key,
        title varchar2(200) not null,
        body varchar2(4000) not null,
        audience varchar2(40) not null,
        embedding vector(3, float32)
    )
    """,
]


def drop_if_exists(cur, table_name):
    try:
        cur.execute(f"drop table {table_name} purge")
    except oracledb.DatabaseError as exc:
        error = exc.args[0]
        if error.code != 942:
            raise


with connect() as conn:
    cur = conn.cursor()

    drop_if_exists(cur, "loan_policies")
    drop_if_exists(cur, "loan_applications")
    print("Dropped existing DEAL demo tables if they existed.")

    for statement in DDL:
        cur.execute(statement)

    print("Created loan_applications.")
    print("Created loan_policies with VECTOR(3, FLOAT32) embedding column.")
    print("Schema setup complete.")
