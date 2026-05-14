#!/bin/bash
# Enable OCI IAM authentication on Autonomous Database using DBMS_CLOUD_ADMIN.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
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
require_wallet_files

for var in OCI_DB_APP_ID OCI_DOMAIN_URL OCI_DB_CLIENT_ID OCI_DB_CLIENT_SECRET; do
  if [ -z "${!var:-}" ]; then
    echo -e "${RED}ERROR: ${var} is not set.${NC}"
    echo -e "${YELLOW}Run ./00_setup_adb.sh, source ./.adb-oci-iam.env, then rerun this script.${NC}"
    exit 1
  fi
done

echo
echo -e "${CYAN}SQL*Plus command:${NC}"
show_cmd sqlplus -L -s "admin/<hidden>@${ADB_SERVICE}"
echo -e "${CYAN}SQL block:${NC}"
cat <<SQL
BEGIN
  DBMS_CLOUD_ADMIN.ENABLE_EXTERNAL_AUTHENTICATION(
    type  => 'OCI_IAM',
    force => TRUE
  );
END;
/

ALTER SYSTEM SET identity_provider_oauth_config =
'{
  "app_id": "${OCI_DB_APP_ID}",
  "domain_url": "${OCI_DOMAIN_URL}"
}' SCOPE = BOTH;

BEGIN
  BEGIN
    DBMS_CREDENTIAL.DROP_CREDENTIAL(credential_name => 'OCI_IAM_DOMAIN_DB_CRED$');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE NOT IN (-27476, -20000) THEN
        NULL;
      END IF;
  END;

  DBMS_CREDENTIAL.CREATE_CREDENTIAL(
    credential_name => 'OCI_IAM_DOMAIN_DB_CRED$',
    username        => '${OCI_DB_CLIENT_ID}',
    password        => '<hidden>'
  );
END;
/
SQL
echo

admin_sqlplus <<SQL
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

ALTER SYSTEM SET identity_provider_oauth_config =
'{
  "app_id": "${OCI_DB_APP_ID}",
  "domain_url": "${OCI_DOMAIN_URL}"
}' SCOPE = BOTH;

BEGIN
  BEGIN
    DBMS_CREDENTIAL.DROP_CREDENTIAL(credential_name => 'OCI_IAM_DOMAIN_DB_CRED$');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE NOT IN (-27476, -20000) THEN
        NULL;
      END IF;
  END;

  DBMS_CREDENTIAL.CREATE_CREDENTIAL(
    credential_name => 'OCI_IAM_DOMAIN_DB_CRED$',
    username        => '${OCI_DB_CLIENT_ID}',
    password        => '${OCI_DB_CLIENT_SECRET}'
  );
END;
/

col name format a40
col value format a120
SELECT name, value
  FROM v$parameter
 WHERE name IN ('identity_provider_type', 'identity_provider_oauth_config');

exit;
SQL

echo
echo -e "${GREEN}Task 1 completed. Next: run ./02_create_hr_schema.sh${NC}"
echo
