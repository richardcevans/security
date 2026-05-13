#!/bin/bash
# =========================================================================================
# Script Name : 01_configure_db_identity_provider.sh
#
# Parameter   : None (uses environment variables)
#
# Notes       : Task 7 - Configure the database identity provider parameters.
#               Sets identity_provider_type and identity_provider_oauth_config for
#               OCI IAM OAuth2 authentication and creates the OCI IAM domain credential.
#
# Environment : OCI_DB_APP_ID          - Application ID of the OCI IAM database app
#               OCI_DOMAIN_URL         - OCI IAM identity domain URL
#               OCI_DB_CLIENT_ID       - Client ID from the database app OAuth config
#               OCI_DB_CLIENT_SECRET   - Client secret from the database app OAuth config
#               PDB_NAME               - Pluggable database name (default: pdb1)
#               DBUSR_SYS              - SYS username (default: sys)
#               DBUSR_PWD              - SYS password (default: Oracle123)
# =========================================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 7: Configure Database Identity Provider for OCI IAM              ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

export PDB_NAME="${PDB_NAME:-pdb1}"
export DBUSR_SYS="${DBUSR_SYS:-sys}"
export DBUSR_PWD="${DBUSR_PWD:-Oracle123}"

for var in OCI_DB_APP_ID OCI_DOMAIN_URL OCI_DB_CLIENT_ID OCI_DB_CLIENT_SECRET; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}ERROR: ${var} is not set.${NC}"
        exit 1
    fi
done

echo -e "${PURPLE}Using the following OCI IAM configuration:${NC}"
echo -e "${CYAN}  OCI_DB_APP_ID        = ${OCI_DB_APP_ID}${NC}"
echo -e "${CYAN}  OCI_DOMAIN_URL       = ${OCI_DOMAIN_URL}${NC}"
echo -e "${CYAN}  OCI_DB_CLIENT_ID     = ${OCI_DB_CLIENT_ID}${NC}"
echo -e "${CYAN}  OCI_DB_CLIENT_SECRET = ******${NC}"
echo -e "${CYAN}  PDB_NAME             = ${PDB_NAME}${NC}"
echo

echo -e "${YELLOW}Setting OCI IAM identity provider parameters and credential (as SYS)...${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${DBUSR_SYS}/******@${PDB_NAME} as sysdba${NC}"
echo

sqlplus -s ${DBUSR_SYS}/${DBUSR_PWD}@${PDB_NAME} as sysdba <<EOF

set echo off
set serveroutput on
set lines 160
set pages 9999

prompt
prompt ========================================================================
prompt Step 1: Set identity_provider_type = OCI_IAM
prompt ========================================================================

prompt ALTER SYSTEM SET identity_provider_type = OCI_IAM SCOPE = BOTH;
ALTER SYSTEM SET identity_provider_type = OCI_IAM SCOPE = BOTH;

prompt
prompt ========================================================================
prompt Step 2: Set identity_provider_oauth_config with OCI IAM details
prompt ========================================================================

prompt ALTER SYSTEM SET identity_provider_oauth_config = '...' SCOPE = BOTH;
ALTER SYSTEM SET identity_provider_oauth_config =
'{
  "app_id": "${OCI_DB_APP_ID}",
  "domain_url": "${OCI_DOMAIN_URL}"
}' SCOPE = BOTH;

prompt
prompt ========================================================================
prompt Step 3: Create OCI_IAM_DOMAIN_DB_CRED$ credential
prompt ========================================================================

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

prompt
prompt ========================================================================
prompt Step 4: Verify the parameters
prompt ========================================================================

col name   format a40
col value  format a100

SELECT name, value
  FROM v\$parameter
 WHERE name IN ('identity_provider_type','identity_provider_oauth_config');

exit;
EOF

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 7 Completed: OCI IAM Identity Provider Configured!               ${NC}"
echo -e "${GREEN}      Next: run 02_configure_network.sh                                     ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
