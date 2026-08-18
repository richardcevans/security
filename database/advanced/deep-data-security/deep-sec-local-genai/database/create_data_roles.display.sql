-- What this step does. Safe to copy — no live secrets appear here.
-- Run as an ADB administrator. A data role carries authorization; a data
-- grant specifies the rows and columns that role is allowed to retrieve.

-- 1. Create the three roles used to demonstrate broad, employee, and manager access.
CREATE OR REPLACE DATA ROLE APP_FULL_ACCESS;
CREATE OR REPLACE DATA ROLE APP_SALES_EMPLOYEE;
CREATE OR REPLACE DATA ROLE APP_SALES_MANAGER;

-- 2. Attach the ordinary APP_LOCAL_CONNECT role created on the previous
--    page. APPLAB table access remains data-grant controlled.
GRANT APP_LOCAL_CONNECT TO APP_FULL_ACCESS;
GRANT APP_LOCAL_CONNECT TO APP_SALES_EMPLOYEE;
GRANT APP_LOCAL_CONNECT TO APP_SALES_MANAGER;
