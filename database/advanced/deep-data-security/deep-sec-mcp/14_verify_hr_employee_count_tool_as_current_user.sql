whenever sqlerror exit failure rollback
set echo off
set feedback on
set pagesize 100
set linesize 220

prompt ============================================================================
prompt Current OCI IAM database session
prompt SELECT authenticated identity and current user FROM dual
prompt ============================================================================

COLUMN current_user FORMAT A20
COLUMN authenticated_identity FORMAT A50
SELECT SYS_CONTEXT('USERENV', 'CURRENT_USER') AS current_user,
       SYS_CONTEXT('USERENV', 'AUTHENTICATED_IDENTITY') AS authenticated_identity
  FROM dual;

prompt ============================================================================
prompt Fixed native MCP tool function
prompt SELECT ADMIN.DEEPSEC_HR_EMPLOYEE_COUNT() FROM dual
prompt ============================================================================

COLUMN tool_result FORMAT A120
SELECT admin.deepsec_hr_employee_count() AS tool_result
  FROM dual;

exit success
