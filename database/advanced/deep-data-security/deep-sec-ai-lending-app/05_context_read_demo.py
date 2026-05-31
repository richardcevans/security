from deal_db import object_name, run_for_user


SQL = """
select *
from {loan_applications}
order by id
""".format(loan_applications=object_name("loan_applications"))

FIELDS_TO_SHOW = [
    "customer_ssn",
    "customer_credit_score",
    "underwriting_decision",
    "risk_score",
]


def display_value(value):
    return "NULL" if value is None else value


def rows_for(end_user):
    def work(conn):
        cur = conn.cursor()
        cur.execute(SQL)
        columns = [col[0].lower() for col in cur.description]
        return [dict(zip(columns, row)) for row in cur.fetchall()]

    return run_for_user(end_user, work)


def show(end_user):
    rows = rows_for(end_user)
    ids = [str(row["id"]) for row in rows]

    print(f"\nAs {end_user}:")
    print(f"  Rows returned: {len(rows)}")
    print(f"  Visible application ids: {', '.join(ids)}")

    sample = rows[0] if rows else {}
    print("  Selected sensitive and underwriting fields:")
    for field in FIELDS_TO_SHOW:
        print(f"    {field}: {display_value(sample.get(field))}")


print("Read and column enforcement demo")
show("linda")
show("wendy")
