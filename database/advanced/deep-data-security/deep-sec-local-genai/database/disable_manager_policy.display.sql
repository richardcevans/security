-- What this step does. Safe to copy — no live secrets appear here.
-- Run as an ADB administrator.

-- 1. Revoke the manager role. The manager data grant no longer applies to
--    Marvin's new queries; his employee role may still remain active.
REVOKE DATA ROLE APP_SALES_MANAGER FROM MARVIN;
