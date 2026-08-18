-- Run as ADB ADMIN from the Deep Sec DEMO Setup or SQL*Plus.
-- Restores full access for the before-and-after demonstration.
whenever sqlerror exit sql.sqlcode rollback
set echo off

prompt SQL> GRANT DATA ROLE APP_FULL_ACCESS TO MARVIN
prompt APP_FULL_ACCESS activates the full-access data grant, which authorizes every APPLAB.CUSTOMERS row and displayed column.
grant data role app_full_access to marvin;

prompt Full access enabled: MARVIN can request every APPLAB.CUSTOMERS row and displayed column.
prompt This full-access authorization is for the lab demonstration only.
