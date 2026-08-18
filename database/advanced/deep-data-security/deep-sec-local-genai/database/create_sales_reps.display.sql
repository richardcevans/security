-- What this step does. Safe to copy — no live secrets appear here.
-- Run as an ADB administrator. The hierarchy makes manager authorization
-- data-driven rather than relying on a generic application-side team value.

-- 1. Recreate the direct-report table for a predictable lab reset.
DROP TABLE APPLAB.SALES_REPS PURGE;
CREATE TABLE APPLAB.SALES_REPS (
  REP_NAME      VARCHAR2(100) PRIMARY KEY,
  MANAGER_NAME  VARCHAR2(100) NOT NULL
);

-- 2. Record the one direct report in this lab. Emma owns the WEST accounts
--    that Marvin gains when the manager data role is later enabled.
INSERT INTO APPLAB.SALES_REPS (REP_NAME, MANAGER_NAME) VALUES ('EMMA', 'MARVIN');
COMMIT;
