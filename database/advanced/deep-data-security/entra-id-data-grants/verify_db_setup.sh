#!/bin/bash
# Verify database-side Entra ID and data grants setup.

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

export PDB_NAME="${PDB_NAME:-FREEPDB1}"
export DB_SID="${DB_SID:-FREE}"
export ORACLE_SID="$DB_SID"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Verify Database Setup for Entra ID Data Grants                        ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}  ORACLE_SID = ${ORACLE_SID}${NC}"
echo -e "${CYAN}  PDB_NAME   = ${PDB_NAME}${NC}"
echo

if ! sqlplus -s / as sysdba <<EOF
set echo off
set feedback on
set lines 180
set pages 9999
whenever sqlerror exit sql.sqlcode

BEGIN
  EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE ${PDB_NAME} OPEN';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -65019 THEN
      RAISE;
    END IF;
END;
/

ALTER SESSION SET CONTAINER = ${PDB_NAME};

prompt
prompt ========================================================================
prompt PDB
prompt ========================================================================
show con_name

prompt
prompt ========================================================================
prompt Identity Provider Parameters
prompt ========================================================================
col name format a38
col value format a120
SELECT name, value
  FROM v\$parameter
 WHERE name IN ('identity_provider_type','identity_provider_config')
 ORDER BY name;

prompt
prompt ========================================================================
prompt Data Roles and Mappings
prompt ========================================================================
col data_role format a24
col mapped_to format a40
col enabled_by_default format a20
SELECT data_role, mapped_to, enabled_by_default
  FROM dba_data_roles
 WHERE data_role IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS')
 ORDER BY data_role;

prompt
prompt ========================================================================
prompt Direct Logon Role and Grants
prompt ========================================================================
col role format a30
SELECT role
  FROM dba_roles
 WHERE role = 'DIRECT_LOGON_ROLE';

col granted_role format a30
col grantee format a30
SELECT grantee, granted_role
  FROM dba_role_privs
 WHERE granted_role = 'DIRECT_LOGON_ROLE'
    OR grantee IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS')
 ORDER BY grantee, granted_role;

col privilege format a30
SELECT grantee, privilege
  FROM dba_sys_privs
 WHERE grantee = 'DIRECT_LOGON_ROLE'
 ORDER BY privilege;

prompt
prompt ========================================================================
prompt Data Grants on HR.EMPLOYEES
prompt ========================================================================
col grant_name format a35
col privilege format a12
col object_owner format a15
col object_name format a20
SELECT grant_name, privilege, grantee, object_owner, object_name
  FROM dba_data_grants
 WHERE object_owner = 'HR'
 ORDER BY grant_name, privilege, grantee;

prompt
prompt ========================================================================
prompt HR Rows
prompt ========================================================================
SELECT COUNT(*) AS hr_employee_rows FROM hr.employees;

exit;
EOF
then
  echo
  echo -e "${RED}ERROR: Database setup verification failed.${NC}"
  exit 1
fi

echo
echo -e "${GREEN}Database setup verification completed.${NC}"
echo
