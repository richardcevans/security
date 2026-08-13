-- Run as an ADB administrator. Removes only objects created by this lab.
whenever sqlerror exit sql.sqlcode rollback
set echo off

begin execute immediate 'drop end user marvin'; exception when others then if sqlcode != -52515 then raise; end if; end;
/
begin execute immediate 'drop user applab cascade'; exception when others then if sqlcode != -1918 then raise; end if; end;
/
begin execute immediate 'drop data role app_sales_employee'; exception when others then if sqlcode != -28231 then raise; end if; end;
/
begin execute immediate 'drop data role app_sales_manager'; exception when others then if sqlcode != -28231 then raise; end if; end;
/
begin execute immediate 'drop data role app_baseline_access'; exception when others then if sqlcode != -28231 then raise; end if; end;
/
begin execute immediate 'drop role app_local_connect'; exception when others then if sqlcode != -1921 then raise; end if; end;
/
