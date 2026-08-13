-- Run as ADB ADMIN after Marvin's employee-policy demonstration.
-- This is a legitimate database authorization change, not an application edit.

whenever sqlerror exit sql.sqlcode rollback
set echo off

-- A manager can see Marvin and SALES_TEAM accounts and their credit limits,
-- but never sensitive identifiers or FINANCE accounts.
create or replace data grant APPLAB.marvin_manager_customer_access
  as select (customer_id, customer_name, region, sales_rep, revenue)
  on APPLAB.customers
  where sales_rep in ('SALES_TEAM', 'MARVIN')
  to app_sales_manager;

-- Marvin remains an employee. Add the manager role as an additional business
-- responsibility; Deep Data Security adds the applicable employee and manager
-- data grants. Their combined authorization still excludes rows and columns
-- that neither grant permits.
grant data role app_sales_manager to marvin;

prompt Manager promotion ready: MARVIN retains APP_SALES_EMPLOYEE and adds APP_SALES_MANAGER.
prompt Oracle authorizes MARVIN and SALES_TEAM rows, but not FINANCE rows, CREDIT_LIMIT, or SENSITIVE_IDENTIFIER.
