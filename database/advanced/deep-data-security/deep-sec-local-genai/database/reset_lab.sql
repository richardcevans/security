-- Run as an ADB administrator. Removes only objects created by this lab.
whenever sqlerror exit sql.sqlcode rollback
set echo off

prompt SQL> DROP END USER MARVIN (if it exists)
begin execute immediate 'drop end user marvin'; exception when others then if sqlcode != -52515 then raise; end if; end;
/
prompt SQL> DROP END USER EMMA (if it exists)
begin execute immediate 'drop end user emma'; exception when others then if sqlcode != -52515 then raise; end if; end;
/
prompt SQL> DROP USER APPLAB CASCADE (if it exists)
begin execute immediate 'drop user applab cascade'; exception when others then if sqlcode != -1918 then raise; end if; end;
/
prompt SQL> DROP DATA ROLE APP_SALES_EMPLOYEE (if it exists)
begin execute immediate 'drop data role app_sales_employee'; exception when others then if sqlcode != -52507 then raise; end if; end;
/
prompt SQL> DROP DATA ROLE APP_SALES_MANAGER (if it exists)
begin execute immediate 'drop data role app_sales_manager'; exception when others then if sqlcode != -52507 then raise; end if; end;
/
prompt SQL> DROP DATA ROLE APP_FULL_ACCESS (if it exists)
begin execute immediate 'drop data role app_full_access'; exception when others then if sqlcode != -52507 then raise; end if; end;
/
prompt SQL> DROP ROLE APP_LOCAL_CONNECT (if it exists)
begin execute immediate 'drop role app_local_connect'; exception when others then if sqlcode != -1921 then raise; end if; end;
/
prompt SQL> DROP ROLE APPLAB_MGR_CTX_ADMIN (if it exists)
begin execute immediate 'drop role applab_mgr_ctx_admin'; exception when others then if sqlcode != -1921 then raise; end if; end;
/
prompt Reset complete: the APPLAB schema, MARVIN, EMMA, and this lab's roles and data roles have been removed.
