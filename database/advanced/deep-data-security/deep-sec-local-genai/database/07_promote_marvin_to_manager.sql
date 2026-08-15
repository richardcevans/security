-- Run as ADB ADMIN after Marvin's employee-policy demonstration.
-- This is a legitimate database authorization change, not an application edit.

whenever sqlerror exit sql.sqlcode rollback
set echo off

prompt Creating MARVIN's manager data grant.
prompt The manager grant includes MARVIN and SALES_TEAM rows. Its select list omits sensitive columns and its predicate excludes FINANCE rows.
-- A manager can see Marvin and SALES_TEAM accounts and their credit limits,
-- but never sensitive identifiers or FINANCE accounts.
prompt SQL> CREATE OR REPLACE DATA GRANT APPLAB.MARVIN_MANAGER_CUSTOMER_ACCESS AS SELECT (... core columns ...) ON APPLAB.CUSTOMERS WHERE SALES_REP IN ('SALES_TEAM', 'MARVIN') TO APP_SALES_MANAGER
create or replace data grant APPLAB.marvin_manager_customer_access
  as select (customer_id, customer_name, region, sales_rep, revenue)
  on APPLAB.customers
  where sales_rep in ('SALES_TEAM', 'MARVIN')
  to app_sales_manager;

-- Marvin remains an employee. Add the manager role as an additional business
-- responsibility; Deep Data Security adds the applicable employee and manager
-- data grants. Their combined authorization still excludes rows and columns
-- that neither grant permits.
prompt SQL> GRANT DATA ROLE APP_SALES_MANAGER TO MARVIN
prompt MARVIN retains the employee role. Oracle combines the applicable data grants without expanding access beyond either grant's rows and columns.
grant data role app_sales_manager to marvin;

prompt Manager promotion ready: MARVIN retains APP_SALES_EMPLOYEE and adds APP_SALES_MANAGER.
prompt Oracle authorizes MARVIN and SALES_TEAM rows, but not FINANCE rows, CREDIT_LIMIT, or SENSITIVE_IDENTIFIER.
