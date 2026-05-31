from deal_tools import (
    get_application_detail,
    get_loan_applications,
    search_policies,
)


def display_value(value):
    return "NULL" if value is None else value


def titles(rows):
    return ", ".join(row["title"] for row in rows)


def linda_session():
    print("========================")
    print("DEAL session: linda")
    print("========================")

    loans = get_loan_applications("linda")
    ids = [str(row["id"]) for row in loans]
    detail = get_application_detail("linda", 102)
    policies = search_policies("linda", "credit risk")

    print(f"Visible applications: {len(loans)}")
    print(f"Application ids: {', '.join(ids)}")
    print(f"Restricted risk_score: {display_value(detail.get('risk_score'))}")
    print(f"Policy results: {titles(policies)}")


def wendy_session():
    print("\n========================")
    print("DEAL session: wendy")
    print("========================")

    loans = get_loan_applications("wendy")
    ids = [str(row["id"]) for row in loans]
    detail = get_application_detail("wendy", 102)
    policies = search_policies("wendy", "credit risk")

    print(f"Visible applications: {len(loans)}")
    print(f"Application ids: {', '.join(ids)}")
    print(f"Underwriting risk_score: {display_value(detail.get('risk_score'))}")
    print(f"Policy results: {titles(policies)}")


def bypass_check():
    print("\n========================")
    print("Bypass check")
    print("========================")

    linda_rows = get_loan_applications("linda")
    wendy_rows = get_loan_applications("wendy")
    linda_docs = search_policies("linda", "credit risk")
    wendy_docs = search_policies("wendy", "credit risk")

    print(f"Broad loan query returned {len(linda_rows)} Linda-scoped rows for linda.")
    print(f"Broad loan query returned {len(wendy_rows)} Wendy-scoped rows for wendy.")
    print(f"Linda policy titles: {titles(linda_docs)}")
    print(f"Wendy policy titles: {titles(wendy_docs)}")
    print("No application-side row filter, redaction, or audience filter was used.")


linda_session()
wendy_session()
bypass_check()
