-- What this step does. Safe to copy — no live secrets appear here.
-- Run as an ADB administrator.

-- 1. Full access sees every row and every column. This is the deliberately
--    excessive starting state the lab tears down later.
CREATE OR REPLACE DATA GRANT APPLAB.MARVIN_FULL_CUSTOMER_ACCESS
  AS SELECT (CUSTOMER_ID, CUSTOMER_NAME, REGION, SALES_REP, REVENUE, CREDIT_LIMIT, SENSITIVE_IDENTIFIER)
  ON APPLAB.CUSTOMERS
  TO APP_FULL_ACCESS;

-- 2. An employee sees only accounts assigned to them, and never credit
--    limit or sensitive identifier.
CREATE OR REPLACE DATA GRANT APPLAB.MARVIN_EMPLOYEE_CUSTOMER_ACCESS
  AS SELECT (CUSTOMER_ID, CUSTOMER_NAME, REGION, SALES_REP, REVENUE)
  ON APPLAB.CUSTOMERS
  WHERE SALES_REP = <the authenticated end user>
  TO APP_SALES_EMPLOYEE;
