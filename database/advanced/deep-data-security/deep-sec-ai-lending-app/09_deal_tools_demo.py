from deal_tools import (
    get_loan_applications,
    search_policies,
)


print("Tool demo: linda")
linda_loans = get_loan_applications("linda")
linda_policies = search_policies("linda", "credit risk")
print(f"  get_loan_applications returned {len(linda_loans)} rows.")
print(f"  search_policies returned {len(linda_policies)} policy documents.")

print("\nTool demo: wendy")
wendy_loans = get_loan_applications("wendy")
wendy_policies = search_policies("wendy", "credit risk")
print(f"  get_loan_applications returned {len(wendy_loans)} rows.")
print(f"  search_policies returned {len(wendy_policies)} policy documents.")
