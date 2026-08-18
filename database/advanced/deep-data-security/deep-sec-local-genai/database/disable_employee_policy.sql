-- Run as ADB ADMIN from the Deep Sec DEMO Setup or SQL*Plus.
whenever sqlerror exit sql.sqlcode rollback
set echo off

prompt SQL> REVOKE DATA ROLE APP_SALES_EMPLOYEE FROM MARVIN
prompt Removing this data role stops the employee data grant from applying to MARVIN's new queries.
revoke data role app_sales_employee from marvin;

prompt Employee policy disabled: APP_SALES_EMPLOYEE is no longer active for MARVIN.
