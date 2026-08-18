-- What this step does. Safe to copy — no live secrets appear here.
-- Run as an ADB administrator. It materializes each representative's manager
-- on protected customer rows so Oracle can evaluate the manager data grant.

-- 1. Synchronize MANAGER_NAME from the named representative hierarchy.
UPDATE APPLAB.CUSTOMERS C
   SET MANAGER_NAME = (
     SELECT R.MANAGER_NAME
       FROM APPLAB.SALES_REPS R
      WHERE UPPER(R.REP_NAME) = UPPER(C.SALES_REP)
   );
COMMIT;
