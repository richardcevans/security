#!/usr/bin/env bash
set -euo pipefail

TNS_ALIAS="${WEB_HR_TNS_ALIAS:-${PDB_NAME:-FREEPDB1}}"
DBA_CONNECT="${WEB_HR_DBA_CONNECT:-sys/Oracle123@${TNS_ALIAS} as sysdba}"

usage() {
  cat <<'EOF'
Usage:
  ./setup_audit_policy.sh [options]

Options:
  --tns-alias <alias>
      Target database service alias. Default: WEB_HR_TNS_ALIAS, PDB_NAME, or FREEPDB1.

  --dba-connect <connect-string>
      SQL*Plus DBA connection string. Default: sys/Oracle123@<alias> as sysdba.

  -h, --help
      Show this help.

Creates and enables a Unified Audit policy for SELECT and UPDATE on
HR.EMPLOYEES, then grants AUDIT_VIEWER to deepsec_admin.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tns-alias)
      TNS_ALIAS="${2:?--tns-alias requires a value}"
      DBA_CONNECT="sys/Oracle123@${TNS_ALIAS} as sysdba"
      shift 2
      ;;
    --dba-connect)
      DBA_CONNECT="${2:?--dba-connect requires a value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v sqlplus >/dev/null 2>&1; then
  echo "ERROR: sqlplus was not found on PATH." >&2
  exit 1
fi

echo
echo "Configuring Unified Audit policy"
echo "  TNS alias   = ${TNS_ALIAS}"
echo "  DBA connect = ${DBA_CONNECT}"
echo

sqlplus -s "$DBA_CONNECT" <<SQL
SET ECHO OFF FEEDBACK ON VERIFY OFF HEADING ON PAGESIZE 200 LINESIZE 200 SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
  l_count NUMBER;
BEGIN
  SELECT COUNT(*)
    INTO l_count
    FROM dba_tables
   WHERE owner = 'HR'
     AND table_name = 'EMPLOYEES';

  IF l_count = 0 THEN
    RAISE_APPLICATION_ERROR(-20001, 'HR.EMPLOYEES was not found. Run end-user-data-grants setup first.');
  END IF;
END;
/

BEGIN
  BEGIN
    EXECUTE IMMEDIATE 'NOAUDIT POLICY end_user_web_hr_employee_audit';
    DBMS_OUTPUT.PUT_LINE('Disabled existing END_USER_WEB_HR_EMPLOYEE_AUDIT policy.');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('No existing enabled END_USER_WEB_HR_EMPLOYEE_AUDIT policy to disable.');
  END;

  BEGIN
    EXECUTE IMMEDIATE 'DROP AUDIT POLICY end_user_web_hr_employee_audit';
    DBMS_OUTPUT.PUT_LINE('Dropped existing END_USER_WEB_HR_EMPLOYEE_AUDIT policy.');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('No existing END_USER_WEB_HR_EMPLOYEE_AUDIT policy to drop.');
  END;
END;
/

CREATE AUDIT POLICY end_user_web_hr_employee_audit
  ACTIONS SELECT ON hr.employees,
          UPDATE ON hr.employees;

AUDIT POLICY end_user_web_hr_employee_audit;

DECLARE
  l_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_count FROM dba_users WHERE username = 'DEEPSEC_ADMIN';
  IF l_count = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER deepsec_admin IDENTIFIED BY Oracle123';
  ELSE
    EXECUTE IMMEDIATE 'ALTER USER deepsec_admin IDENTIFIED BY Oracle123 ACCOUNT UNLOCK';
  END IF;
END;
/

GRANT CREATE SESSION TO deepsec_admin;
GRANT AUDIT_VIEWER TO deepsec_admin;

PROMPT
PROMPT Unified Audit policy:
SELECT policy_name, audit_option, object_schema, object_name
  FROM audit_unified_policies
 WHERE policy_name = 'END_USER_WEB_HR_EMPLOYEE_AUDIT'
 ORDER BY audit_option;

PROMPT
PROMPT Enabled audit policies:
SELECT policy_name, enabled_option, success, failure
  FROM audit_unified_enabled_policies
 WHERE policy_name = 'END_USER_WEB_HR_EMPLOYEE_AUDIT';

EXIT
SQL

cat <<EOF

Audit policy is enabled.

Generate records:
  1. Sign in to the app as emma or marvin.
  2. Click Load Employees or edit an allowed field.
  3. Click Refresh Audit Events.

Manual query:
  sqlplus deepsec_admin/Oracle123@${TNS_ALIAS}
EOF
