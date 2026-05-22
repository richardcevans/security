#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTRA_LAB_ENV="${ENTRA_LAB_ENV:-${SCRIPT_DIR}/../entra-id-data-grants/.entra-id-data-grants.env}"

if [ -f "$ENTRA_LAB_ENV" ]; then
  # shellcheck disable=SC1090
  source "$ENTRA_LAB_ENV"
fi
if [ -f "${SCRIPT_DIR}/.find-the-money.env" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.find-the-money.env"
fi

: "${PDB_NAME:?PDB_NAME is required}"
FIND_MONEY_APP_DB_USER="${FIND_MONEY_APP_DB_USER:-find_money_app_user}"
FIND_MONEY_APPLICATION_IDENTITY="${FIND_MONEY_APPLICATION_IDENTITY:-find_money_app}"
DB_SID="${DB_SID:-FREE}"
ORACLE_HOME="${ORACLE_HOME:-/opt/oracle/product/26ai/dbhome_1}"
if [ -x "$ORACLE_HOME/bin/sqlplus" ]; then
  export ORACLE_HOME
  export PATH="$ORACLE_HOME/bin:$PATH"
  export LD_LIBRARY_PATH="$ORACLE_HOME/lib:${LD_LIBRARY_PATH:-}"
fi
export ORACLE_SID="$DB_SID"

echo "Verifying Find the Money database configuration in PDB ${PDB_NAME}"
echo "This script is read-only."
echo

sqlplus -s / as sysdba <<EOF
set echo off
set lines 180
set pages 9999
whenever sqlerror exit sql.sqlcode

ALTER SESSION SET CONTAINER = ${PDB_NAME};

prompt
prompt ========================================================================
prompt FIN schema objects
prompt ========================================================================

col object_type format a20
col object_name format a34
SELECT object_type, object_name, status
  FROM dba_objects
 WHERE owner = 'FIN'
   AND object_type IN ('TABLE', 'FUNCTION', 'PROPERTY GRAPH')
 ORDER BY object_type, object_name;

prompt
prompt ========================================================================
prompt Find the Money database user and application identity
prompt ========================================================================

col username format a24
col authentication_type format a22
col external_name format a80
SELECT username, authentication_type, external_name
  FROM dba_users
 WHERE username = UPPER('${FIND_MONEY_APP_DB_USER}');

col privilege format a36
SELECT grantee, privilege
  FROM dba_sys_privs
 WHERE grantee = UPPER('${FIND_MONEY_APP_DB_USER}')
   AND privilege IN ('CREATE SESSION', 'CREATE END USER SECURITY CONTEXT', 'UPDATE ANY END USER CONTEXT')
 ORDER BY privilege;

col application_name format a28
col mapped_to format a80
SELECT application_name, mapped_to
  FROM dba_application_identities
 WHERE application_name = UPPER('${FIND_MONEY_APPLICATION_IDENTITY}');

prompt
prompt ========================================================================
prompt Pooled application user FIN object access
prompt ========================================================================

col owner format a12
col table_name format a28
col grantee format a28
col privilege format a12
SELECT owner, table_name, grantee, privilege
  FROM dba_tab_privs
 WHERE owner = 'FIN'
   AND grantee = UPPER('${FIND_MONEY_APP_DB_USER}')
 ORDER BY table_name, privilege;

prompt
prompt ========================================================================
prompt FIN data roles and grants
prompt ========================================================================

col data_role format a34
col mapped_to format a36
SELECT data_role, mapped_to, enabled_by_default
  FROM dba_data_roles
 WHERE data_role LIKE 'FINAPP%'
    OR data_role IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS')
 ORDER BY data_role;

col grant_name format a38
col object_name format a30
col grantee format a34
SELECT grant_name, object_name, privilege, grantee
  FROM dba_data_grants
 WHERE object_owner = 'FIN'
 ORDER BY object_name, grant_name, privilege;

exit;
EOF
