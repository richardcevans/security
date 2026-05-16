#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTRA_LAB_ENV="${ENTRA_LAB_ENV:-${SCRIPT_DIR}/../entra-id-data-grants/.entra-id-data-grants.env}"

if [ -f "$ENTRA_LAB_ENV" ]; then
  # shellcheck disable=SC1090
  source "$ENTRA_LAB_ENV"
fi

if [ -f "${SCRIPT_DIR}/.web-hr-app.env" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.web-hr-app.env"
else
  echo "ERROR: Missing .web-hr-app.env. Run ./00_setup_entra_web_app.sh first."
  exit 1
fi

: "${PDB_NAME:?PDB_NAME is required}"
: "${WEB_HR_APP_CLIENT_ID:?WEB_HR_APP_CLIENT_ID is required}"

DB_SID="${DB_SID:-FREE}"
export ORACLE_SID="$DB_SID"

echo "Configuring database application identity in PDB ${PDB_NAME}"
echo "  WEB_HR_APP_CLIENT_ID = ${WEB_HR_APP_CLIENT_ID}"
echo

sqlplus -s / as sysdba <<EOF
set echo off
set serveroutput on
set lines 160
set pages 9999
whenever sqlerror exit sql.sqlcode

ALTER SESSION SET CONTAINER = ${PDB_NAME};

prompt
prompt ========================================================================
prompt Create application database user mapped to the Web HR App client ID
prompt ========================================================================

DECLARE
  user_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO user_exists
    FROM dba_users
   WHERE username = 'WEB_HR_APP_USER';

  IF user_exists = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE USER web_hr_app_user IDENTIFIED GLOBALLY
      AS 'AZURE_CLIENT_ID=${WEB_HR_APP_CLIENT_ID}'
    ]';
  END IF;
END;
/

GRANT CREATE SESSION TO web_hr_app_user;
GRANT CREATE END USER SECURITY CONTEXT TO web_hr_app_user;
GRANT SELECT ON hr.employees TO web_hr_app_user;

prompt
prompt ========================================================================
prompt Require Deep Data Security data grants for HR.EMPLOYEES access
prompt ========================================================================

SET USE DATA GRANTS ONLY ON hr.employees ENABLED;

prompt
prompt ========================================================================
prompt Create Oracle application identity mapped to the same Entra client ID
prompt ========================================================================

CREATE OR REPLACE APPLICATION IDENTITY web_hr_app
  MAPPED TO 'AZURE_CLIENT_ID=${WEB_HR_APP_CLIENT_ID}';

prompt
prompt ========================================================================
prompt Create a disabled elevation role for application-mediated access
prompt ========================================================================

CREATE DATA ROLE IF NOT EXISTS hrapp_compensation_analyst DISABLED;

GRANT DATA ROLE hrapp_compensation_analyst TO web_hr_app;

prompt
prompt ========================================================================
prompt Create a salary summary grant available only during application elevation
prompt ========================================================================

CREATE OR REPLACE DATA GRANT hr.HRAPP_COMPENSATION_SUMMARY
  AS SELECT (salary, employee_id, department_id)
  ON hr.employees
  WHERE 1 = 1
  TO HRAPP_COMPENSATION_ANALYST;

prompt
prompt ========================================================================
prompt Verify application identities and data-role grants
prompt ========================================================================

col application_name format a28
col mapped_to format a80
SELECT application_name, mapped_to
  FROM dba_application_identities
 WHERE application_name = 'WEB_HR_APP';

col grantee format a28
col data_role format a32
col grantee_type format a20
SELECT grantee, grantee_type, data_role
  FROM dba_data_role_grants
 WHERE grantee = 'WEB_HR_APP'
   AND data_role = 'HRAPP_COMPENSATION_ANALYST'
 ORDER BY data_role;

col grant_name format a36
col privilege format a20
SELECT grant_name, privilege, grantee
  FROM dba_data_grants
 WHERE grant_name = 'HRAPP_COMPENSATION_SUMMARY'
 ORDER BY grant_name;

exit;
EOF

echo
echo "Database application identity configured."
