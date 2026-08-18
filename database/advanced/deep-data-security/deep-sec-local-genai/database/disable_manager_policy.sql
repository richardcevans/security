-- Run as ADB ADMIN from the Deep Sec DEMO Setup or SQL*Plus.
whenever sqlerror exit sql.sqlcode rollback
set echo off

prompt SQL> REVOKE DATA ROLE APP_SALES_MANAGER FROM MARVIN
prompt Removing this data role stops the manager data grant from applying to MARVIN's new queries.
revoke data role app_sales_manager from marvin;

prompt Manager policy disabled: APP_SALES_MANAGER is no longer active for MARVIN.
