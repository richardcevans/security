#!/bin/bash
# =========================================================================================
# Script Name : 01_configure_db_identity_provider.sh
#
# Parameter   : None (uses environment variables)
#
# Notes       : Task 7 - Configure the database identity provider parameters.
#               Sets identity_provider_type and identity_provider_config for
#               Microsoft Entra ID (Azure AD) OAuth2 authentication.
#
# Environment : APP_ID       - Oracle Database 26ai app registration Application ID
#               APP_ID_URI   - Application ID URI (https://<tenant>.onmicrosoft.com/<app-id>)
#               TENANT_ID    - Azure Directory (tenant) ID
#               PDB_NAME     - Pluggable database name (default: pdb1)
#               DBUSR_SYS    - SYS username (default: sys)
#               DBUSR_PWD    - SYS password (default: Oracle123)
#
# Modified by         Date         Change
# Oracle DB Security  04/02/2026   Creation
# =========================================================================================

# Define colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 7: Configure Database Identity Provider for Entra ID             ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"
export DBUSR_SYS="${DBUSR_SYS:-sys}"
export DBUSR_PWD="${DBUSR_PWD:-Oracle123}"

if [ -z "$APP_ID" ]; then
    echo -e "${RED}ERROR: APP_ID is not set.${NC}"
    echo -e "${YELLOW}  export APP_ID=<your-oracle-db-app-id>${NC}"
    exit 1
fi

if [ -z "$APP_ID_URI" ]; then
    echo -e "${RED}ERROR: APP_ID_URI is not set.${NC}"
    echo -e "${YELLOW}  export APP_ID_URI=https://<tenant>.onmicrosoft.com/<app-id>${NC}"
    exit 1
fi

if [ -z "$TENANT_ID" ]; then
    echo -e "${RED}ERROR: TENANT_ID is not set.${NC}"
    echo -e "${YELLOW}  export TENANT_ID=<your-tenant-id>${NC}"
    exit 1
fi

echo -e "${PURPLE}Using the following Entra ID configuration:${NC}"
echo -e "${CYAN}  APP_ID     = ${APP_ID}${NC}"
echo -e "${CYAN}  APP_ID_URI = ${APP_ID_URI}${NC}"
echo -e "${CYAN}  TENANT_ID  = ${TENANT_ID}${NC}"
echo -e "${CYAN}  PDB_NAME   = ${PDB_NAME}${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Set identity provider parameters
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
echo -e "${YELLOW}Setting identity provider parameters (as SYS)...${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${DBUSR_SYS}/******@${PDB_NAME} as sysdba${NC}"
echo

sqlplus -s ${DBUSR_SYS}/${DBUSR_PWD}@${PDB_NAME} as sysdba <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999

prompt
prompt ========================================================================
prompt Step 1: Set identity_provider_type = AZURE_AD
prompt ========================================================================

prompt ALTER SYSTEM SET identity_provider_type = AZURE_AD SCOPE = BOTH;
ALTER SYSTEM SET identity_provider_type = AZURE_AD SCOPE = BOTH;

prompt
prompt ========================================================================
prompt Step 2: Set identity_provider_config with Entra ID details
prompt ========================================================================

prompt ALTER SYSTEM SET identity_provider_config = '...' SCOPE = BOTH;
ALTER SYSTEM SET identity_provider_config =
'{
  "application_id_uri": "${APP_ID_URI}",
  "tenant_id": "${TENANT_ID}",
  "app_id": "${APP_ID}"
}' SCOPE = BOTH;

prompt
prompt ========================================================================
prompt Step 3: Verify the parameters
prompt ========================================================================

col name   format a30
col value  format a80

SELECT name, value
  FROM v\$parameter
 WHERE name IN ('identity_provider_type','identity_provider_config');

exit;
EOF

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 7 Completed: Identity Provider Configured!                       ${NC}"
echo -e "${GREEN}      Next: run 02_configure_network.sh                                     ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
