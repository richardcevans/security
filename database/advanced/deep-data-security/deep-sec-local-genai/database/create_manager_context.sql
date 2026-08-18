-- Run as an ADB administrator, after create_sales_reps.sql.
-- Creates a session-scoped end user context and the PL/SQL package that
-- populates it. Adapted for local end users; no external identity provider
-- is involved, unlike the Entra ID version of this pattern.
whenever sqlerror exit sql.sqlcode rollback
set echo off

prompt Oracle's ORA_END_USER_CONTEXT.username is built in; every session gets
prompt it for free. There is no built-in for "which reps report to this
prompt manager." This step creates a custom context attribute for exactly
prompt that, loaded once per session the first time it is read from a lookup
prompt table, not from a column synchronized onto CUSTOMERS ahead of time.

prompt SQL> CREATE END USER CONTEXT APPLAB.MGR_CTX
create or replace end user context APPLAB.mgr_ctx using json schema '{
  "type": "object",
  "properties": {
    "REPORTS": {
      "type": "string",
      "o:onFirstRead": "APPLAB.mgr_ctx_pkg.init_reports"
    }
  }
}';

prompt SQL> CREATE PACKAGE APPLAB.MGR_CTX_PKG
prompt When REPORTS is first read in a session, Oracle calls this procedure,
prompt which queries the SALES_REPS lookup table for the authenticated user's
prompt direct reports and stores the result for the rest of that session.
create or replace package APPLAB.mgr_ctx_pkg as
  procedure init_reports;
end;
/

create or replace package body APPLAB.mgr_ctx_pkg as
  procedure init_reports is
    v_reports varchar2(4000);
  begin
    select listagg(rep_name, ',') within group (order by rep_name)
      into v_reports
      from APPLAB.sales_reps
     where upper(manager_name) = upper(ora_end_user_context.username);

    update end_user_context t
       set t.context.reports = nvl(v_reports, '')
     where owner = 'APPLAB'
       and name = 'MGR_CTX';
  end init_reports;
end;
/

prompt SQL> GRANT UPDATE ANY END USER CONTEXT TO APPLAB
grant update any end user context to applab;

prompt SQL> CREATE ROLE APPLAB_MGR_CTX_ADMIN (if needed)
begin
  execute immediate 'create role applab_mgr_ctx_admin';
exception
  when others then
    if sqlcode != -1921 then raise; end if;
end;
/
prompt SQL> GRANT EXECUTE ON APPLAB.MGR_CTX_PKG TO APPLAB_MGR_CTX_ADMIN
grant execute on APPLAB.mgr_ctx_pkg to applab_mgr_ctx_admin;
prompt SQL> GRANT APPLAB_MGR_CTX_ADMIN TO APP_SALES_EMPLOYEE, APP_SALES_MANAGER
prompt This bridge role connects the context package to both data roles, so
prompt whichever role is active, a session can trigger the handler.
grant applab_mgr_ctx_admin to app_sales_employee;
grant applab_mgr_ctx_admin to app_sales_manager;

prompt SQL> CREATE OR REPLACE DATA GRANT APPLAB.MGR_CTX_ACCESS AS SELECT ON SYS.END_USER_CONTEXT WHERE OWNER = 'APPLAB' AND NAME = 'MGR_CTX' TO APP_SALES_EMPLOYEE, APP_SALES_MANAGER
prompt A session also needs authorization to read the context object itself,
prompt separate from being able to execute its handler package.
create or replace data grant APPLAB.mgr_ctx_access
  as select
  on sys.end_user_context
  where owner = 'APPLAB' and name = 'MGR_CTX'
  to app_sales_employee, app_sales_manager;

prompt End user context ready. The manager data grant, created next, reads
prompt ora_end_user_context.APPLAB.MGR_CTX.reports instead of a subquery
prompt or a pre-synchronized column.
