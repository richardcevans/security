-- What this step does. Safe to copy — no live secrets appear here.
-- Run as an ADB administrator.

-- 1. Grant the full-access role to Marvin. Its data grant authorizes every
--    APPLAB.CUSTOMERS row and every displayed column for the demonstration.
GRANT DATA ROLE APP_FULL_ACCESS TO MARVIN;
