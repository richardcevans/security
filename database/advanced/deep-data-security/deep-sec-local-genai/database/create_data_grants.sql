-- Run as an ADB administrator. Defines what APP_FULL_ACCESS and
-- APP_SALES_EMPLOYEE can retrieve. APP_SALES_MANAGER's grant comes later,
-- once its end-user context exists.
whenever sqlerror exit sql.sqlcode rollback
set echo off

prompt Creating the full-access data grant.
prompt SQL> CREATE OR REPLACE DATA GRANT APPLAB.MARVIN_FULL_CUSTOMER_ACCESS AS SELECT (... all columns ...) ON APPLAB.CUSTOMERS TO APP_FULL_ACCESS
prompt This grant deliberately authorizes every customer row and every displayed column for the full-access demonstration.
create or replace data grant APPLAB.marvin_full_customer_access
  as select (customer_id, customer_name, region, sales_rep, revenue, credit_limit, sensitive_identifier)
  on APPLAB.customers
  to app_full_access;

prompt Creating the employee data grant.
prompt SQL> CREATE OR REPLACE DATA GRANT APPLAB.MARVIN_EMPLOYEE_CUSTOMER_ACCESS AS SELECT (... core columns ...) ON APPLAB.CUSTOMERS WHERE SALES_REP = authenticated user TO APP_SALES_EMPLOYEE
prompt The row predicate uses Oracle's authenticated end-user context. The select
prompt list intentionally omits CREDIT_LIMIT and SENSITIVE_IDENTIFIER.
create or replace data grant APPLAB.marvin_employee_customer_access
  as select (customer_id, customer_name, region, sales_rep, revenue)
  on APPLAB.customers
  where upper(sales_rep) = upper(ora_end_user_context.username)
  to app_sales_employee;

prompt Data grants ready. APP_FULL_ACCESS and APP_SALES_EMPLOYEE both authorize
prompt real data now, before either role is ever granted to an end user.
prompt Whoever holds each role, in any order, sees exactly what its grant defines.
