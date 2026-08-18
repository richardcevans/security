-- What this step does. Safe to copy — no live secrets appear here.
-- Run as an ADB administrator. Emma is a fixed comparison user.

-- 1. Drop Emma if a previous run left her behind.
DROP END USER EMMA;

-- 2. Create Emma using the same shared Stack password as Marvin.
CREATE END USER EMMA IDENTIFIED BY <shared Stack password>;

-- 3. Emma always holds APP_SALES_EMPLOYEE only, unlike Marvin, her role
--    never changes for the rest of the lab. Sign in as Emma at any point
--    to see a stable employee-level view for comparison.
GRANT DATA ROLE APP_SALES_EMPLOYEE TO EMMA;
