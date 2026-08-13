-- Run as ADB ADMIN after the insecure baseline demonstration in Task 6.
-- This applies Marvin's sales-employee Deep Data Security policy.

whenever sqlerror exit sql.sqlcode rollback
set echo off

-- An employee sees only assigned accounts and core business fields. Credit
-- limit and sensitive identifier are intentionally not selected.
create or replace data grant APPLAB.marvin_employee_customer_access
  as select (customer_id, customer_name, region, sales_rep, revenue)
  on APPLAB.customers
  where upper(sales_rep) = upper(ora_end_user_context.username)
  to app_sales_employee;

-- Replace the deliberately broad baseline role with the employee role. The
-- application query does not change; Oracle now enforces the narrower grant.
revoke data role app_baseline_access from marvin;
grant data role app_sales_employee to marvin;

prompt Employee policy ready: MARVIN now uses APP_SALES_EMPLOYEE.
prompt Oracle authorizes only MARVIN rows and does not authorize CREDIT_LIMIT or SENSITIVE_IDENTIFIER.
