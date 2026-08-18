-- Run as an ADB administrator. Swaps Marvin from full access to the
-- employee data role. The employee data grant already exists, created on
-- the Deep Sec Basics page, so this step only changes which role Marvin
-- holds; the Flask query never changes.

whenever sqlerror exit sql.sqlcode rollback
set echo off

prompt SQL> REVOKE DATA ROLE APP_FULL_ACCESS FROM MARVIN
revoke data role app_full_access from marvin;
prompt SQL> GRANT DATA ROLE APP_SALES_EMPLOYEE TO MARVIN
prompt The Flask query stays the same. Oracle now returns only the rows and columns authorized by the employee grant, already in place.
grant data role app_sales_employee to marvin;

prompt Employee policy ready: MARVIN now uses APP_SALES_EMPLOYEE.
prompt Oracle authorizes only MARVIN rows and does not authorize CREDIT_LIMIT or SENSITIVE_IDENTIFIER.
