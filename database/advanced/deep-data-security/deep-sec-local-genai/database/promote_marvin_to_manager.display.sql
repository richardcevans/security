-- What this step does. Safe to copy — no live secrets appear here.
-- Run as an ADB administrator. This is an Oracle authorization change, not
-- an application edit. Sensitive identifiers remain outside this data grant.

-- 1. Define the manager data grant. It permits Marvin's own rows and rows
--    assigned to a direct report named in APPLAB.MGR_CTX.REPORTS. CREDIT_LIMIT
--    is included.
CREATE OR REPLACE DATA GRANT APPLAB.MARVIN_MANAGER_CUSTOMER_ACCESS
  AS SELECT (CUSTOMER_ID, CUSTOMER_NAME, REGION, SALES_REP, REVENUE, CREDIT_LIMIT)
  ON APPLAB.CUSTOMERS
  WHERE UPPER(SALES_REP) = UPPER(ORA_END_USER_CONTEXT.USERNAME)
     OR INSTR(','||ORA_END_USER_CONTEXT.APPLAB.MGR_CTX.reports||',', ','||UPPER(SALES_REP)||',') > 0
  TO APP_SALES_MANAGER;

-- 2. Add the manager role while Marvin keeps the employee role. Oracle
--    combines the applicable data grants without revealing an omitted column.
GRANT DATA ROLE APP_SALES_MANAGER TO MARVIN;
