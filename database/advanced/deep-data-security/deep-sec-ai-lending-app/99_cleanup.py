import oracledb

from deal_db import connect


OBJECTS = [
    ("data grant", "deal_policy_underwriter"),
    ("data grant", "deal_policy_general_to_underwriter"),
    ("data grant", "deal_policy_officer"),
    ("data grant", "deal_policy_general_to_officer"),
    ("data grant", "deal_underwriter_read"),
    ("data grant", "deal_loan_officer_read"),
    ("data role", "underwriter_role"),
    ("data role", "loan_officer_role"),
]


def try_execute(cur, statement):
    try:
        cur.execute(statement)
        print(f"Ran: {statement}")
    except oracledb.DatabaseError as exc:
        error = exc.args[0]
        print(f"Skipped: {statement} (ORA-{error.code})")


with connect() as conn:
    cur = conn.cursor()
    try_execute(cur, "set use data grants only on loan_applications disabled")
    try_execute(cur, "set use data grants only on loan_policies disabled")
    for kind, name in OBJECTS:
        try_execute(cur, f"drop {kind} {name}")
    try_execute(cur, "drop table loan_policies purge")
    try_execute(cur, "drop table loan_applications purge")
    conn.commit()
