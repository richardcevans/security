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

-- Direct local end users land in XS$NULL. APP_LOCAL_CONNECT, an ordinary
-- Oracle role, was created on the previous page. Table access remains
-- controlled entirely by data grants below, not by this role.
prompt SQL> GRANT APP_LOCAL_CONNECT TO APP_FULL_ACCESS, APP_SALES_EMPLOYEE, APP_SALES_MANAGER
prompt A database role like APP_LOCAL_CONNECT cannot be granted straight to an end user.
prompt It must first be granted to a data role using the standard GRANT statement,
prompt then that data role can be granted to Marvin or Emma. This is what lets a
prompt data role carry ordinary Oracle privileges alongside its Deep Sec data grants.
grant app_local_connect to app_full_access;
grant app_local_connect to app_sales_employee;
grant app_local_connect to app_sales_manager;

prompt Data roles ready: APP_FULL_ACCESS, APP_SALES_EMPLOYEE, and APP_SALES_MANAGER
prompt now each carry CREATE SESSION through APP_LOCAL_CONNECT. None of them
prompt authorize any table data yet, that comes from the data grants created next.
