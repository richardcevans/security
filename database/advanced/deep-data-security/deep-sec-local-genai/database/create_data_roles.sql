-- Run as ADB ADMIN before creating the local end user.
-- This full-access role is for the before-and-after lab demonstration only.
-- Task 6 replaces it with Deep Data Security grants.

whenever sqlerror exit sql.sqlcode rollback
set echo off

prompt Creating Oracle Deep Data Security data roles and grants.
prompt A data role carries Oracle data authorization. A data grant defines the rows and columns that role may retrieve.
prompt SQL> CREATE OR REPLACE DATA ROLE APP_FULL_ACCESS
create or replace data role app_full_access;
prompt SQL> CREATE OR REPLACE DATA ROLE APP_SALES_EMPLOYEE
create or replace data role app_sales_employee;
prompt SQL> CREATE OR REPLACE DATA ROLE APP_SALES_MANAGER
create or replace data role app_sales_manager;

-- Direct local end users land in XS$NULL. Bind only CREATE SESSION through a
-- normal database role; table access remains controlled by data grants.
prompt SQL> CREATE ROLE APP_LOCAL_CONNECT (if needed)
begin
  execute immediate 'create role app_local_connect';
exception
  when others then
    if sqlcode != -1921 then raise; end if;
end;
/
prompt SQL> GRANT CREATE SESSION TO APP_LOCAL_CONNECT
grant create session to app_local_connect;
prompt SQL> GRANT APP_LOCAL_CONNECT TO APP_FULL_ACCESS, APP_SALES_EMPLOYEE, APP_SALES_MANAGER
grant app_local_connect to app_full_access;
grant app_local_connect to app_sales_employee;
grant app_local_connect to app_sales_manager;

-- Full access: Marvin can request every customer row and every displayed
-- column. Do not use this grant in a production application.
prompt SQL> CREATE OR REPLACE DATA GRANT APPLAB.MARVIN_FULL_CUSTOMER_ACCESS AS SELECT (... all columns ...) ON APPLAB.CUSTOMERS TO APP_FULL_ACCESS
prompt This grant deliberately authorizes every customer row and every displayed column for the full-access demonstration.
create or replace data grant APPLAB.marvin_full_customer_access
  as select (customer_id, customer_name, region, sales_rep, revenue, credit_limit, sensitive_identifier)
  on APPLAB.customers
  to app_full_access;

prompt Full access ready: APP_FULL_ACCESS permits all APPLAB.CUSTOMERS rows and columns.
prompt Script 05 grants this full-access role to MARVIN for the before-and-after demonstration.
prompt Do not use this full-access data grant in a production application.
