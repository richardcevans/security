set echo off
set verify off
set feedback on
set linesize 200
set long 1000000
whenever sqlerror exit sql.sqlcode rollback
define SELECT_AI_ACTION = '&1'
prompt ============================================================================
prompt Current OCI IAM-authenticated database session
prompt ============================================================================
prompt SELECT SYS_CONTEXT values for the current session FROM dual;
SELECT sys_context('USERENV', 'CURRENT_USER') AS current_user,
       sys_context('USERENV', 'AUTHENTICATED_IDENTITY') AS authenticated_identity
  FROM dual;
prompt ============================================================================
prompt Harmless Select AI chat through the current OCI IAM user session
prompt ============================================================================
prompt SELECT DBMS_CLOUD_AI.GENERATE(<fixed harmless prompt>, 'DEEPSEC_HR_CHAT', 'chat') AS response FROM dual;
SELECT DBMS_CLOUD_AI.GENERATE('Reply with exactly: OCI IAM Select AI user-session smoke test passed.', 'DEEPSEC_HR_CHAT', 'chat') AS response FROM dual;
prompt ============================================================================
prompt HR.EMPLOYEES request under current OCI IAM data roles
prompt ============================================================================
prompt SELECT DBMS_CLOUD_AI.GENERATE(<fixed HR prompt>, 'DEEPSEC_HR_CHAT', '&SELECT_AI_ACTION') AS response FROM dual;
SELECT DBMS_CLOUD_AI.GENERATE('How many employees are in HR.EMPLOYEES?', 'DEEPSEC_HR_CHAT', '&SELECT_AI_ACTION') AS response FROM dual;
exit success
