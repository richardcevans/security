-- Run as ADB ADMIN from the Deep Sec Admin Console or SQL*Plus.
whenever sqlerror exit sql.sqlcode rollback
set echo off

prompt SQL> REVOKE DATA ROLE APP_FULL_ACCESS FROM MARVIN
prompt Removing this data role stops its full-access data grant from applying to new MARVIN queries.
revoke data role app_full_access from marvin;

prompt Full access disabled: APP_FULL_ACCESS is no longer active for MARVIN.
