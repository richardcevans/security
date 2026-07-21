set echo off
set feedback on
set serveroutput on
set linesize 180
set pagesize 100
whenever sqlerror exit sql.sqlcode rollback

host printf '\033[0;32m'
prompt ============================================================================
prompt Disable the lab policy if it is enabled
prompt NOAUDIT POLICY DEEPSEC_HR_EMPLOYEES_AUDIT;
prompt ============================================================================
host printf '\033[0m'

DECLARE
  enabled_count PLS_INTEGER;
BEGIN
  SELECT COUNT(*)
    INTO enabled_count
    FROM audit_unified_enabled_policies
   WHERE policy_name = 'DEEPSEC_HR_EMPLOYEES_AUDIT';

  IF enabled_count > 0 THEN
    EXECUTE IMMEDIATE 'NOAUDIT POLICY DEEPSEC_HR_EMPLOYEES_AUDIT';
    DBMS_OUTPUT.PUT_LINE('Disabled DEEPSEC_HR_EMPLOYEES_AUDIT.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('DEEPSEC_HR_EMPLOYEES_AUDIT is not enabled.');
  END IF;
END;
/

prompt
host printf '\033[0;32m'
prompt ============================================================================
prompt Drop the lab policy if it exists
prompt DROP AUDIT POLICY DEEPSEC_HR_EMPLOYEES_AUDIT;
prompt ============================================================================
host printf '\033[0m'

DECLARE
  policy_count PLS_INTEGER;
BEGIN
  SELECT COUNT(*)
    INTO policy_count
    FROM audit_unified_policies
   WHERE policy_name = 'DEEPSEC_HR_EMPLOYEES_AUDIT';

  IF policy_count > 0 THEN
    EXECUTE IMMEDIATE 'DROP AUDIT POLICY DEEPSEC_HR_EMPLOYEES_AUDIT';
    DBMS_OUTPUT.PUT_LINE('Dropped DEEPSEC_HR_EMPLOYEES_AUDIT.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('DEEPSEC_HR_EMPLOYEES_AUDIT is already absent.');
  END IF;
END;
/

exit success
