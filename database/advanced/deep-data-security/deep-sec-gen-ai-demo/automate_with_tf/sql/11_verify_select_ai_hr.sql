-- Validate the ADMIN-owned Select AI profile using one fixed HR.EMPLOYEES prompt.
-- Default action is showsql, which does not execute generated SQL.

set echo off
set verify off
set feedback on
set serveroutput on size unlimited
set linesize 200
set pagesize 100
set long 1000000
set longchunksize 1000000
whenever sqlerror exit sql.sqlcode rollback

define SELECT_AI_ACTION = '&1'

prompt ============================================================================
prompt Select AI profile and action
prompt ============================================================================
BEGIN
  DBMS_CLOUD_AI.SET_PROFILE('DEEPSEC_HR_CHAT');
END;
/

SELECT DBMS_CLOUD_AI.GET_PROFILE() AS active_profile FROM dual;
SELECT '&SELECT_AI_ACTION' AS select_ai_action FROM dual;

prompt ============================================================================
prompt Fixed HR.EMPLOYEES prompt
prompt ============================================================================
prompt Prompt: How many employees are in HR.EMPLOYEES?
prompt
prompt For showsql, inspect the returned SQL before ever choosing --run.

SELECT DBMS_CLOUD_AI.GENERATE(
         prompt       => 'How many employees are in HR.EMPLOYEES?',
         profile_name => 'DEEPSEC_HR_CHAT',
         action       => '&SELECT_AI_ACTION'
       ) AS response
FROM dual;

exit success
