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
fi

: "${PDB_NAME:?PDB_NAME is required}"
DB_SID="${DB_SID:-FREE}"
export ORACLE_SID="$DB_SID"

sqlplus -s / as sysdba <<EOF
set echo off
set lines 160
set pages 9999
whenever sqlerror exit sql.sqlcode

ALTER SESSION SET CONTAINER = ${PDB_NAME};

prompt
prompt ========================================================================
prompt Web HR App database user
prompt ========================================================================

col username format a22
col authentication_type format a22
col external_name format a80
SELECT username, authentication_type, external_name
  FROM dba_users
 WHERE username = 'WEB_HR_APP_USER';

col privilege format a36
SELECT grantee, privilege
  FROM dba_sys_privs
 WHERE grantee = 'WEB_HR_APP_USER'
   AND privilege IN (
     'CREATE SESSION',
     'CREATE END USER SECURITY CONTEXT',
     'UPDATE ANY END USER CONTEXT'
   )
 ORDER BY privilege;

prompt
prompt ========================================================================
prompt Application identity
prompt ========================================================================

col application_name format a28
col mapped_to format a80
SELECT application_name, mapped_to
  FROM dba_application_identities
 WHERE application_name = 'WEB_HR_APP';

prompt
prompt ========================================================================
prompt Pooled application user base object access
prompt ========================================================================

col owner format a12
col table_name format a24
col grantee format a28
col privilege format a12
SELECT owner, table_name, grantee, privilege
  FROM dba_tab_privs
 WHERE owner = 'HR'
   AND table_name = 'EMPLOYEES'
   AND grantee = 'WEB_HR_APP_USER'
 ORDER BY privilege;

prompt
prompt ========================================================================
prompt Elevation role granted to application identity
prompt ========================================================================

col grantee format a28
col data_role format a32
col grantee_type format a20
SELECT grantee, grantee_type, data_role
  FROM dba_data_role_grants
 WHERE grantee = 'WEB_HR_APP'
   AND data_role IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS', 'HRAPP_COMPENSATION_ANALYST')
 ORDER BY data_role;

prompt
prompt ========================================================================
prompt Compensation summary data grant
prompt ========================================================================

col grant_name format a36
col privilege format a20
col grantee format a32
SELECT grant_name, privilege, grantee
  FROM dba_data_grants
 WHERE grant_name = 'HRAPP_COMPENSATION_SUMMARY'
 ORDER BY grant_name;

exit;
EOF
