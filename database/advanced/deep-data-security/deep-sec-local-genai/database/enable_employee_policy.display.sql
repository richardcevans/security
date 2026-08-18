-- What this step does. Safe to copy — no live secrets appear here.
-- Run as an ADB administrator. This replaces Marvin's broad role with the
-- employee role. Oracle now returns
--    only his assigned rows and the five selected columns.
REVOKE DATA ROLE APP_FULL_ACCESS FROM MARVIN;
GRANT DATA ROLE APP_SALES_EMPLOYEE TO MARVIN;
