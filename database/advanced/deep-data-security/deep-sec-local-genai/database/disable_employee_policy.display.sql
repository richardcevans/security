-- What this step does. Safe to copy — no live secrets appear here.
-- Run as an ADB administrator.

-- 1. Revoke the employee role so its employee data grant stops applying to
--    Marvin's new database queries.
REVOKE DATA ROLE APP_SALES_EMPLOYEE FROM MARVIN;
