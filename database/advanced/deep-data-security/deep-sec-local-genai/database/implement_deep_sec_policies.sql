-- Run as ADB ADMIN after the full-access demonstration in Task 6.
-- This applies Marvin's sales-employee Deep Data Security policy.

whenever sqlerror exit sql.sqlcode rollback
set echo off

prompt Creating MARVIN's employee data grant.
prompt The row predicate uses Oracle's authenticated end-user context. The select list intentionally omits CREDIT_LIMIT and SENSITIVE_IDENTIFIER.
-- An employee sees only assigned accounts and core business fields. Credit
-- limit and sensitive identifier are intentionally not selected.
prompt SQL> CREATE OR REPLACE DATA GRANT APPLAB.MARVIN_EMPLOYEE_CUSTOMER_ACCESS AS SELECT (... core columns ...) ON APPLAB.CUSTOMERS WHERE SALES_REP = authenticated MARVIN TO APP_SALES_EMPLOYEE
create or replace data grant APPLAB.marvin_employee_customer_access
  as select (customer_id, customer_name, region, sales_rep, revenue)
  on APPLAB.customers
  where upper(sales_rep) = upper(ora_end_user_context.username)
  to app_sales_employee;

-- Replace the full-access role with the employee role. The
-- application query does not change; Oracle now enforces the narrower grant.
prompt SQL> REVOKE DATA ROLE APP_FULL_ACCESS FROM MARVIN
revoke data role app_full_access from marvin;
prompt SQL> GRANT DATA ROLE APP_SALES_EMPLOYEE TO MARVIN
prompt The Flask query stays the same. Oracle now returns only the rows and columns authorized by the employee grant.
grant data role app_sales_employee to marvin;

prompt Employee policy ready: MARVIN now uses APP_SALES_EMPLOYEE.
prompt Oracle authorizes only MARVIN rows and does not authorize CREDIT_LIMIT or SENSITIVE_IDENTIFIER.
