-- Run as ADB ADMIN after create_sales_reps.sql.
-- Materialize each representative's manager on the protected customer rows.
-- The manager data grant can then use a simple, reliable row predicate.
whenever sqlerror exit sql.sqlcode rollback
set echo off

prompt SQL> UPDATE APPLAB.CUSTOMERS SET MANAGER_NAME FROM APPLAB.SALES_REPS
prompt Each customer's MANAGER_NAME is synchronized from the named representative hierarchy.
update applab.customers c
   set manager_name = (
     select r.manager_name
       from applab.sales_reps r
      where upper(r.rep_name) = upper(c.sales_rep)
   );

prompt SQL> COMMIT
commit;

prompt Manager hierarchy ready: EMMA's six WEST customers have MANAGER_NAME = MARVIN. The manager policy reads this protected-row attribute directly.
