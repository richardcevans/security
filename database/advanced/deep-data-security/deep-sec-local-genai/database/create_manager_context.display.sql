-- What this step does. Safe to copy — no live secrets appear here.
-- Run as an ADB administrator.

-- 1. A session-scoped object that can hold custom attributes, loaded lazily.
CREATE OR REPLACE END USER CONTEXT APPLAB.MGR_CTX USING JSON SCHEMA '{
  "type": "object",
  "properties": {
    "REPORTS": {
      "type": "string",
      "o:onFirstRead": "APPLAB.MGR_CTX_PKG.INIT_REPORTS"
    }
  }
}';

-- 2. The handler Oracle calls the first time REPORTS is read in a session.
--    It queries SALES_REPS for the authenticated user's direct reports and
--    caches the result for the rest of that session.
CREATE OR REPLACE PACKAGE APPLAB.MGR_CTX_PKG AS
  PROCEDURE INIT_REPORTS;
END;
CREATE OR REPLACE PACKAGE BODY APPLAB.MGR_CTX_PKG AS
  PROCEDURE INIT_REPORTS IS
    v_reports VARCHAR2(4000);
  BEGIN
    SELECT LISTAGG(rep_name, ',') WITHIN GROUP (ORDER BY rep_name)
      INTO v_reports
      FROM APPLAB.SALES_REPS
     WHERE UPPER(manager_name) = UPPER(ORA_END_USER_CONTEXT.username);
    UPDATE END_USER_CONTEXT t
       SET t.CONTEXT.REPORTS = NVL(v_reports, '')
     WHERE owner = 'APPLAB' AND name = 'MGR_CTX';
  END;
END;

-- 3. A bridge role connects the handler package to whichever data role is
--    active, and a data grant authorizes reading the context object itself.
GRANT UPDATE ANY END USER CONTEXT TO APPLAB;
CREATE ROLE APPLAB_MGR_CTX_ADMIN;
GRANT EXECUTE ON APPLAB.MGR_CTX_PKG TO APPLAB_MGR_CTX_ADMIN;
GRANT APPLAB_MGR_CTX_ADMIN TO APP_SALES_EMPLOYEE, APP_SALES_MANAGER;
CREATE OR REPLACE DATA GRANT APPLAB.MGR_CTX_ACCESS
  AS SELECT
  ON SYS.END_USER_CONTEXT
  WHERE OWNER = 'APPLAB' AND NAME = 'MGR_CTX'
  TO APP_SALES_EMPLOYEE, APP_SALES_MANAGER;
