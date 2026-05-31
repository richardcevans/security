from array import array

from deal_db import connect


loans = [
    (101, "Avery Stone", 320000, "Home purchase", "RECEIVED",
     "Missing final pay stub.", "111-22-3333", 128000, 720,
     "PENDING_REVIEW", 41, "Not reviewed yet.", "LINDA", "N"),
    (102, "Noah Rivers", 485000, "Home purchase", "UNDER_REVIEW",
     "Customer uploaded tax documents.", "222-33-4444", 151000, 695,
     "PENDING_REVIEW", 72, "Watch revolving debt.", "LINDA", "Y"),
    (103, "Maya Chen", 210000, "Refinance", "UNDER_REVIEW",
     "Transferred from branch intake.", "333-44-5555", 98000, 681,
     "PENDING_REVIEW", 68, "Check income variability.", "raj", "Y"),
    (104, "Grace Hill", 150000, "Home equity", "NEEDS_DOCS",
     "Awaiting insurance statement.", "444-55-6666", 87000, 735,
     "NOT_STARTED", 35, "Not in queue.", "amir", "N"),
    (105, "Owen Park", 640000, "Jumbo mortgage", "UNDER_REVIEW",
     "Customer requested expedited review.", "555-66-7777", 220000, 705,
     "PENDING_REVIEW", 77, "Large loan amount.", "LINDA", "Y"),
    (106, "Sofia Reyes", 390000, "Investment property", "ESCALATED",
     "Escalated by branch manager.", "666-77-8888", 132000, 660,
     "PENDING_REVIEW", 83, "Exception review needed.", "raj", "Y"),
]

policies = [
    (1, "General lending eligibility",
     "Baseline eligibility requirements for consumer lending applications.",
     "general", array("f", [0.75, 0.20, 0.05])),
    (2, "Income verification basics",
     "Required documents for income verification and employment review.",
     "general", array("f", [0.65, 0.30, 0.05])),
    (3, "Document retention requirements",
     "Retention periods for lending documents and customer communications.",
     "general", array("f", [0.30, 0.20, 0.50])),
    (4, "Loan officer workflow checklist",
     "Loan officer workflow for intake, status updates, and customer follow-up.",
     "loan_officer", array("f", [0.85, 0.10, 0.05])),
    (5, "Officer notes standards",
     "Standards for writing clear customer-facing officer notes.",
     "loan_officer", array("f", [0.80, 0.05, 0.15])),
    (6, "Credit risk escalation policy",
     "When credit risk signals require underwriting escalation.",
     "underwriter", array("f", [0.05, 0.90, 0.05])),
    (7, "Debt-to-income exception review",
     "Underwriting guidance for debt-to-income ratio exceptions.",
     "underwriter", array("f", [0.10, 0.85, 0.05])),
    (8, "Collateral review guidance",
     "Collateral review requirements for underwriting decisions.",
     "underwriter", array("f", [0.05, 0.75, 0.20])),
]


with connect() as conn:
    cur = conn.cursor()

    cur.executemany(
        """
        insert into loan_applications (
            id, customer_name, loan_amount, purpose, status, officer_notes,
            customer_ssn, customer_income, customer_credit_score,
            underwriting_decision, risk_score, underwriting_notes,
            assigned_officer, in_underwriting_queue
        ) values (:1, :2, :3, :4, :5, :6, :7, :8, :9, :10, :11, :12, :13, :14)
        """,
        loans,
    )

    cur.executemany(
        """
        insert into loan_policies (id, title, body, audience, embedding)
        values (:1, :2, :3, :4, :5)
        """,
        policies,
    )

    conn.commit()

    print(f"Inserted {len(loans)} loan applications.")
    print(f"Inserted {len(policies)} loan policy documents.")
    print("Synthetic data load complete.")
