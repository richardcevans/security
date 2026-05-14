#!/bin/bash
# Enable OCI IAM authentication on Autonomous Database using DBMS_CLOUD_ADMIN.

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/lib_adb.sh"
require_adb_env

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 1: Enable OCI IAM Authentication on ADB                          ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}Executing as ADMIN on ${ADB_SERVICE}${NC}"
echo -e "${CYAN}SQL*Plus command:${NC}"
show_cmd sqlplus -L -s "admin/<hidden>@${ADB_SERVICE}"
echo -e "${CYAN}SQL block:${NC}"
cat <<'SQL'
BEGIN
  DBMS_CLOUD_ADMIN.ENABLE_EXTERNAL_AUTHENTICATION(
    type  => 'OCI_IAM',
    force => TRUE
  );
END;
/
SQL
echo

admin_sqlplus <<'SQL'
set echo on
set serveroutput on
set lines 180
whenever sqlerror exit sql.sqlcode

BEGIN
  DBMS_CLOUD_ADMIN.ENABLE_EXTERNAL_AUTHENTICATION(
    type  => 'OCI_IAM',
    force => TRUE
  );
END;
/

col name format a40
col value format a80
SELECT name, value
  FROM v$parameter
 WHERE name = 'identity_provider_type';

exit;
SQL

echo
echo -e "${GREEN}Task 1 completed. Next: run ./02_create_hr_schema.sh${NC}"
echo
