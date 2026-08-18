-- What this step does. Safe to copy — no live secrets appear here.
-- Run as an ADB administrator.

-- 1. Revoke the broad role. Its data grant no longer applies to Marvin's
--    new database queries.
REVOKE DATA ROLE APP_FULL_ACCESS FROM MARVIN;
