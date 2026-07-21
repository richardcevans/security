set echo off
set verify off
set feedback on
set linesize 200
set long 1000000
whenever sqlerror exit sql.sqlcode rollback
column active_profile format a40
define SELECT_AI_ACTION = '&1'
prompt BEGIN DBMS_CLOUD_AI.SET_PROFILE('DEEPSEC_HR_CHAT'); END;
BEGIN DBMS_CLOUD_AI.SET_PROFILE('DEEPSEC_HR_CHAT'); END;
/
prompt SELECT DBMS_CLOUD_AI.GET_PROFILE() AS active_profile FROM dual;
SELECT DBMS_CLOUD_AI.GET_PROFILE() AS active_profile FROM dual;
prompt ============================================================================
prompt Fixed HR.EMPLOYEES prompt
prompt ============================================================================
prompt Prompt: How many employees are in HR.EMPLOYEES?
prompt For showsql, inspect generated SQL before choosing --run.
prompt SELECT DBMS_CLOUD_AI.GENERATE(<fixed HR prompt>, 'DEEPSEC_HR_CHAT', '&SELECT_AI_ACTION') AS response FROM dual;
SELECT DBMS_CLOUD_AI.GENERATE('How many employees are in HR.EMPLOYEES?', 'DEEPSEC_HR_CHAT', '&SELECT_AI_ACTION') AS response FROM dual;
exit success
