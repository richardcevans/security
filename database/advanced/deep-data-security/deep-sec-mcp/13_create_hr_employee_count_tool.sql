whenever sqlerror exit failure rollback
set echo off
set feedback on
set pagesize 100
set linesize 220
set serveroutput on

prompt ============================================================================
prompt Create invoker-rights function
prompt CREATE OR REPLACE FUNCTION ADMIN.DEEPSEC_HR_EMPLOYEE_COUNT AUTHID CURRENT_USER
prompt ============================================================================

CREATE OR REPLACE FUNCTION admin.deepsec_hr_employee_count
  RETURN CLOB
  AUTHID CURRENT_USER
IS
  l_result CLOB;
BEGIN
  SELECT JSON_OBJECT(
           'visible_employee_rows' VALUE COUNT(*)
           RETURNING CLOB
         )
    INTO l_result
    FROM hr.employees;
  RETURN l_result;
END;
/

prompt ============================================================================
prompt Grant function execution
prompt GRANT EXECUTE ON ADMIN.DEEPSEC_HR_EMPLOYEE_COUNT TO PUBLIC
prompt ============================================================================

GRANT EXECUTE ON admin.deepsec_hr_employee_count TO PUBLIC;

prompt ============================================================================
prompt Register the native ADB MCP tool
prompt DBMS_CLOUD_AI_AGENT.DROP_TOOL then CREATE_TOOL for DEEPSEC_HR_EMPLOYEE_COUNT
prompt ============================================================================

BEGIN
  DBMS_CLOUD_AI_AGENT.DROP_TOOL(
    tool_name => 'DEEPSEC_HR_EMPLOYEE_COUNT',
    force     => TRUE
  );

  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'DEEPSEC_HR_EMPLOYEE_COUNT',
    attributes => q'~{
      "instruction":"Return only the number of HR.EMPLOYEES rows visible to the authenticated caller. This tool has no inputs and must not be used for any other purpose.",
      "function":"ADMIN.DEEPSEC_HR_EMPLOYEE_COUNT"
    }~',
    status      => 'ENABLED',
    description => 'Returns only the authenticated caller-visible HR.EMPLOYEES row count.'
  );
END;
/

prompt ============================================================================
prompt Verify native ADB MCP tool metadata
prompt SELECT OWNER, TOOL_NAME, STATUS FROM DBA_AI_AGENT_TOOLS ...
prompt ============================================================================

COLUMN owner FORMAT A12
COLUMN tool_name FORMAT A36
COLUMN status FORMAT A10
SELECT owner, tool_name, status
  FROM dba_ai_agent_tools
 WHERE tool_name = 'DEEPSEC_HR_EMPLOYEE_COUNT'
 ORDER BY owner, tool_name;

exit success
