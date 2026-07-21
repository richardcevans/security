-- Verify Select AI from the OCI IAM user represented by the current token.
-- Default HR action is showsql; --run uses runsql in this same user session.

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
prompt Current OCI IAM-authenticated database session
prompt ============================================================================
col current_user format a30
col current_schema format a30
col authenticated_identity format a70
col authentication_method format a25
SELECT
  sys_context('USERENV', 'CURRENT_USER') AS current_user,
  sys_context('USERENV', 'CURRENT_SCHEMA') AS current_schema,
  sys_context('USERENV', 'AUTHENTICATED_IDENTITY') AS authenticated_identity,
  sys_context('USERENV', 'AUTHENTICATION_METHOD') AS authentication_method
FROM dual;

prompt ============================================================================
prompt Harmless Select AI chat through the current OCI IAM user session
prompt ============================================================================
SELECT DBMS_CLOUD_AI.GENERATE(
         prompt       => 'Reply with exactly: OCI IAM Select AI user-session smoke test passed.',
         profile_name => 'DEEPSEC_HR_CHAT',
         action       => 'chat'
       ) AS response
FROM dual;

prompt ============================================================================
prompt HR.EMPLOYEES Select AI request under current OCI IAM data roles
prompt ============================================================================
SELECT '&SELECT_AI_ACTION' AS select_ai_action FROM dual;
SELECT DBMS_CLOUD_AI.GENERATE(
         prompt       => 'How many employees are in HR.EMPLOYEES?',
         profile_name => 'DEEPSEC_HR_CHAT',
         action       => '&SELECT_AI_ACTION'
       ) AS response
FROM dual;

exit success
