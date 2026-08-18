-- What this step does. Safe to copy — no live secrets appear here.
-- Run as an ADB administrator. Marvin is a password-authenticated local
-- database end user, not an OCI IAM identity.

-- 1. Drop Marvin if a previous run left him behind.
DROP END USER MARVIN;

-- 2. Create Marvin using the shared Stack password from the Pre-Lab step.
--    This is the same password used for ADMIN, Marvin, and Emma throughout
--    this disposable lab, and it is never written to a file or logged.
CREATE END USER MARVIN IDENTIFIED BY <shared Stack password>;

-- 3. Marvin starts with full access, so the lab can show the before-and-
--    after effect once the employee policy is applied later.
GRANT DATA ROLE APP_FULL_ACCESS TO MARVIN;
