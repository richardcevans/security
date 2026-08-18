-- What this step does. Safe to copy — no live secrets appear here.
-- Run as an ADB administrator. This changes the authorization boundary from
-- broad access to the employee policy; the application query does not change.

-- 1. Define the employee data grant. The row predicate uses the authenticated
--    Oracle end-user context. CREDIT_LIMIT and SENSITIVE_IDENTIFIER are omitted.
CREATE OR REPLACE DATA GRANT APPLAB.MARVIN_EMPLOYEE_CUSTOMER_ACCESS
  AS SELECT (CUSTOMER_ID, CUSTOMER_NAME, REGION, SALES_REP, REVENUE)
  ON APPLAB.CUSTOMERS
  WHERE UPPER(SALES_REP) = UPPER(ORA_END_USER_CONTEXT.USERNAME)
  TO APP_SALES_EMPLOYEE;

-- 2. Replace Marvin's broad role with the employee role. Oracle now returns
--    only his assigned rows and the five selected columns.
REVOKE DATA ROLE APP_FULL_ACCESS FROM MARVIN;
GRANT DATA ROLE APP_SALES_EMPLOYEE TO MARVIN;
