from deal_db import connect


def execute_ignore_existing(cur, sql, existing_codes):
    try:
        cur.execute(sql)
        return True
    except Exception as exc:
        error = exc.args[0]
        if getattr(error, "code", None) in existing_codes:
            return False
        raise


with connect() as conn:
    cur = conn.cursor()

    print("Using prepared Deep Sec end users: LINDA, WENDY")

    if execute_ignore_existing(cur, "create data role loan_officer_role", {955, 52514}):
        print("Created data role: LOAN_OFFICER_ROLE")
    else:
        print("Data role already exists: LOAN_OFFICER_ROLE")

    if execute_ignore_existing(cur, "create data role underwriter_role", {955, 52514}):
        print("Created data role: UNDERWRITER_ROLE")
    else:
        print("Data role already exists: UNDERWRITER_ROLE")

    cur.execute("grant data role loan_officer_role to linda")
    print("Granted LOAN_OFFICER_ROLE to LINDA.")

    cur.execute("grant data role underwriter_role to wendy")
    print("Granted UNDERWRITER_ROLE to WENDY.")

    grants = [
        """
        create or replace data grant deal_loan_officer_read as
        select (
            all columns except customer_ssn, customer_income,
            customer_credit_score, underwriting_decision,
            risk_score, underwriting_notes
        )
        on loan_applications
        where assigned_officer = ORA_END_USER_CONTEXT.username
        to loan_officer_role
        """,
        """
        create or replace data grant deal_underwriter_read as
        select on loan_applications
        where in_underwriting_queue = 'Y'
        to underwriter_role
        """,
        """
        create or replace data grant deal_policy_general_to_officer as
        select on loan_policies
        where audience = 'general'
        to loan_officer_role
        """,
        """
        create or replace data grant deal_policy_officer as
        select on loan_policies
        where audience = 'loan_officer'
        to loan_officer_role
        """,
        """
        create or replace data grant deal_policy_general_to_underwriter as
        select on loan_policies
        where audience = 'general'
        to underwriter_role
        """,
        """
        create or replace data grant deal_policy_underwriter as
        select on loan_policies
        where audience = 'underwriter'
        to underwriter_role
        """,
    ]

    for grant in grants:
        cur.execute(grant)

    conn.commit()

    print("Created loan application read grants.")
    print("Created loan policy read grants.")
    print("Configured Deep Data Security for DEAL.")
