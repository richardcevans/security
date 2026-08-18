-- What this step does. Safe to copy — no live secrets appear here.
-- Run as an ADB administrator. It removes only objects created by this lab so
-- the initial setup action can recreate a clean, predictable environment.

-- 1. Remove the two local end users used by the Customer Sales application.
DROP END USER MARVIN;
DROP END USER EMMA;

-- 2. Remove APPLAB and the protected customer data it owns.
DROP USER APPLAB CASCADE;

-- 3. Remove the Deep Data Security roles and their data grants.
DROP DATA ROLE APP_SALES_EMPLOYEE;
DROP DATA ROLE APP_SALES_MANAGER;
DROP DATA ROLE APP_FULL_ACCESS;
DROP ROLE APP_LOCAL_CONNECT;
