-- Run as ADB ADMIN before creating the local end user.
-- This intentionally insecure baseline is for the before-and-after lab
-- demonstration only. Task 6 replaces it with Deep Data Security grants.

whenever sqlerror exit sql.sqlcode rollback
set echo off

create or replace data role app_baseline_access;
create or replace data role app_sales_employee;
create or replace data role app_sales_manager;

-- Direct local end users land in XS$NULL. Bind only CREATE SESSION through a
-- normal database role; table access remains controlled by data grants.
begin
  execute immediate 'create role app_local_connect';
exception
  when others then
    if sqlcode != -1921 then raise; end if;
end;
/
grant create session to app_local_connect;
grant app_local_connect to app_baseline_access;
grant app_local_connect to app_sales_employee;
grant app_local_connect to app_sales_manager;

-- Intentionally insecure baseline: Marvin can request every customer row and
-- every displayed column. Do not use this grant in a production application.
create or replace data grant APPLAB.marvin_insecure_customer_access
  as select (customer_id, customer_name, region, sales_rep, revenue, credit_limit, sensitive_identifier)
  on APPLAB.customers
  to app_baseline_access;

prompt Baseline ready: APP_BASELINE_ACCESS permits all APPLAB.CUSTOMERS rows and columns.
prompt Script 05 grants this deliberately excessive role to MARVIN for the before-and-after demonstration.
prompt Do not use this baseline data grant in a production application.
