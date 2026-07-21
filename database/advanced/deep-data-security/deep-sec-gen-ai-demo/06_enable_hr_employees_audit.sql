set echo off
set feedback on
set serveroutput on
set linesize 180
set pagesize 100
whenever sqlerror exit sql.sqlcode rollback

host printf '\033[0;32m'
prompt ============================================================================
prompt Create the narrowly scoped Unified Auditing policy if it is absent
prompt CREATE AUDIT POLICY DEEPSEC_HR_EMPLOYEES_AUDIT
prompt   ACTIONS SELECT ON HR.EMPLOYEES, UPDATE ON HR.EMPLOYEES,
prompt           DELETE ON HR.EMPLOYEES;
prompt ============================================================================
host printf '\033[0m'

DECLARE
  policy_count PLS_INTEGER;
BEGIN
  SELECT COUNT(*)
    INTO policy_count
    FROM audit_unified_policies
   WHERE policy_name = 'DEEPSEC_HR_EMPLOYEES_AUDIT';

  IF policy_count = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE AUDIT POLICY DEEPSEC_HR_EMPLOYEES_AUDIT
        ACTIONS SELECT ON HR.EMPLOYEES,
                UPDATE ON HR.EMPLOYEES,
                DELETE ON HR.EMPLOYEES
    ]';
    DBMS_OUTPUT.PUT_LINE('Created DEEPSEC_HR_EMPLOYEES_AUDIT.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('DEEPSEC_HR_EMPLOYEES_AUDIT already exists; leaving its definition unchanged.');
  END IF;
END;
/

prompt
host printf '\033[0;32m'
prompt ============================================================================
prompt Enable the policy for all database users if it is not already enabled
prompt AUDIT POLICY DEEPSEC_HR_EMPLOYEES_AUDIT;
prompt ============================================================================
host printf '\033[0m'

DECLARE
  enabled_count PLS_INTEGER;
BEGIN
  SELECT COUNT(*)
    INTO enabled_count
    FROM audit_unified_enabled_policies
   WHERE policy_name = 'DEEPSEC_HR_EMPLOYEES_AUDIT';

  IF enabled_count = 0 THEN
    EXECUTE IMMEDIATE 'AUDIT POLICY DEEPSEC_HR_EMPLOYEES_AUDIT';
    DBMS_OUTPUT.PUT_LINE('Enabled DEEPSEC_HR_EMPLOYEES_AUDIT for all users.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('DEEPSEC_HR_EMPLOYEES_AUDIT is already enabled.');
  END IF;
END;
/

prompt
host printf '\033[0;32m'
prompt ============================================================================
prompt Verify policy definition
prompt SELECT policy_name, audit_option_type, audit_option, object_schema,
prompt        object_name FROM AUDIT_UNIFIED_POLICIES ...
prompt ============================================================================
host printf '\033[0m'

column policy_name format a34
column audit_option_type format a17
column audit_option format a12
column object_schema format a16
column object_name format a20

SELECT policy_name,
       audit_option_type,
       audit_option,
       object_schema,
       object_name
  FROM audit_unified_policies
 WHERE policy_name = 'DEEPSEC_HR_EMPLOYEES_AUDIT'
 ORDER BY audit_option;

prompt
host printf '\033[0;32m'
prompt ============================================================================
prompt Verify policy enablement
prompt SELECT policy_name, enabled_option, entity_name FROM
prompt        AUDIT_UNIFIED_ENABLED_POLICIES ...
prompt ============================================================================
host printf '\033[0m'

column enabled_option format a18
column entity_name format a35

SELECT policy_name,
       enabled_option,
       entity_name
  FROM audit_unified_enabled_policies
 WHERE policy_name = 'DEEPSEC_HR_EMPLOYEES_AUDIT'
 ORDER BY enabled_option, entity_name;

exit success
