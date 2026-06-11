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

echo "Configuring DBA policy toggle demo procedures in PDB ${PDB_NAME}"
echo
echo "This script will create or replace two SYS definer-rights procedures"
echo "and grant WEB_HR_APP_USER execute rights on them:"
echo "  SYS.WEB_HR_DISABLE_SALARY_UPDATES"
echo "  SYS.WEB_HR_ENABLE_SALARY_UPDATES"

sqlplus -s / as sysdba <<EOF
set echo off
set serveroutput on
set lines 180
set pages 9999
whenever sqlerror exit sql.sqlcode

ALTER SESSION SET CONTAINER = ${PDB_NAME};

prompt
prompt ========================================================================
prompt Create or replace DBA policy toggle procedures
prompt ========================================================================
prompt WEB_HR_DISABLE_SALARY_UPDATES recreates HR.HRAPP_MANAGER_ACCESS without UPDATE(salary).
prompt WEB_HR_ENABLE_SALARY_UPDATES recreates HR.HRAPP_MANAGER_ACCESS with UPDATE(salary).
prompt Both grants include UPDATE(employee_id) so web app updates can target rows by employee_id.

CREATE OR REPLACE PROCEDURE sys.web_hr_disable_salary_updates
AUTHID DEFINER
AS
BEGIN
  EXECUTE IMMEDIATE q'[
    CREATE OR REPLACE DATA GRANT hr.HRAPP_MANAGER_ACCESS
      AS SELECT (ALL COLUMNS EXCEPT ssn), UPDATE (employee_id, department_id, first_name)
      ON hr.employees
      WHERE manager_id = ORA_END_USER_CONTEXT.HR.EMP_CTX.ID
      TO HRAPP_MANAGERS
  ]';
END;
/

CREATE OR REPLACE PROCEDURE sys.web_hr_enable_salary_updates
AUTHID DEFINER
AS
BEGIN
  EXECUTE IMMEDIATE q'[
    CREATE OR REPLACE DATA GRANT hr.HRAPP_MANAGER_ACCESS
      AS SELECT (ALL COLUMNS EXCEPT ssn), UPDATE (employee_id, salary, department_id, first_name)
      ON hr.employees
      WHERE manager_id = ORA_END_USER_CONTEXT.HR.EMP_CTX.ID
      TO HRAPP_MANAGERS
  ]';
END;
/

prompt Granting execute on DBA policy toggle procedures to WEB_HR_APP_USER.
GRANT EXECUTE ON sys.web_hr_disable_salary_updates TO web_hr_app_user;
GRANT EXECUTE ON sys.web_hr_enable_salary_updates TO web_hr_app_user;

prompt
prompt ========================================================================
prompt DBA policy toggle demo configured
prompt ========================================================================

col table_name format a36
col grantee format a28
col privilege format a12
SELECT table_name, grantee, privilege
  FROM dba_tab_privs
 WHERE owner = 'SYS'
   AND table_name IN ('WEB_HR_DISABLE_SALARY_UPDATES', 'WEB_HR_ENABLE_SALARY_UPDATES')
 ORDER BY table_name, grantee;

exit;
EOF

echo
echo "DBA policy toggle demo procedures configured."
