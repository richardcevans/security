#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTRA_LAB_ENV="${ENTRA_LAB_ENV:-${SCRIPT_DIR}/../entra-id-data-grants/.entra-id-data-grants.env}"

if [ -f "$ENTRA_LAB_ENV" ]; then
  # shellcheck disable=SC1090
  source "$ENTRA_LAB_ENV"
fi

: "${PDB_NAME:?PDB_NAME is required}"
DB_SID="${DB_SID:-FREE}"
export ORACLE_SID="$DB_SID"

echo "Configuring Unified Audit policy for HR.EMPLOYEES in PDB ${PDB_NAME}"

sqlplus -s / as sysdba <<EOF
set echo off
set serveroutput on
set lines 180
set pages 9999
whenever sqlerror exit sql.sqlcode

ALTER SESSION SET CONTAINER = ${PDB_NAME};

BEGIN
  BEGIN EXECUTE IMMEDIATE 'NOAUDIT POLICY web_hr_app_employee_audit'; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN EXECUTE IMMEDIATE 'DROP AUDIT POLICY web_hr_app_employee_audit'; EXCEPTION WHEN OTHERS THEN NULL; END;
END;
/

CREATE AUDIT POLICY web_hr_app_employee_audit
  ACTIONS SELECT ON hr.employees,
          UPDATE ON hr.employees;

AUDIT POLICY web_hr_app_employee_audit;

GRANT AUDIT_VIEWER TO web_hr_app_user;

prompt
prompt ========================================================================
prompt Web HR App employee audit policy enabled
prompt ========================================================================

col policy_name format a32
SELECT policy_name, audit_option, object_schema, object_name
  FROM audit_unified_policies
 WHERE policy_name = 'WEB_HR_APP_EMPLOYEE_AUDIT'
 ORDER BY audit_option;

prompt
prompt Run app SELECT/UPDATE actions, then refresh the app audit panel or query:
prompt
prompt SELECT event_timestamp, dbusername, end_user_name, action_name, return_code
prompt   FROM unified_audit_trail
prompt  WHERE object_schema = 'HR'
prompt    AND object_name = 'EMPLOYEES'
prompt  ORDER BY event_timestamp DESC;

prompt
prompt The web app queries UNIFIED_AUDIT_TRAIL through the AUDIT_VIEWER role.

exit;
EOF

echo
echo "Unified Audit policy configured."
