-- What this step does. Safe to copy — no live secrets appear here.
-- Run as an ADB administrator. A data role carries authorization; a data
-- grant specifies the rows and columns that role is allowed to retrieve.

-- 1. Create the three roles used to demonstrate broad, employee, and manager access.
CREATE OR REPLACE DATA ROLE APP_FULL_ACCESS;
CREATE OR REPLACE DATA ROLE APP_SALES_EMPLOYEE;
CREATE OR REPLACE DATA ROLE APP_SALES_MANAGER;

-- 2. Give each data role the ordinary CREATE SESSION capability through a
--    normal database role. APPLAB table access remains data-grant controlled.
CREATE ROLE APP_LOCAL_CONNECT;
GRANT CREATE SESSION TO APP_LOCAL_CONNECT;
GRANT APP_LOCAL_CONNECT TO APP_FULL_ACCESS;
GRANT APP_LOCAL_CONNECT TO APP_SALES_EMPLOYEE;
GRANT APP_LOCAL_CONNECT TO APP_SALES_MANAGER;

-- 3. Define the deliberately broad starting grant. It authorizes all rows
--    and displayed columns only for the disposable before-and-after exercise.
CREATE OR REPLACE DATA GRANT APPLAB.MARVIN_FULL_CUSTOMER_ACCESS
  AS SELECT (CUSTOMER_ID, CUSTOMER_NAME, REGION, SALES_REP, REVENUE, CREDIT_LIMIT, SENSITIVE_IDENTIFIER)
  ON APPLAB.CUSTOMERS
  TO APP_FULL_ACCESS;
