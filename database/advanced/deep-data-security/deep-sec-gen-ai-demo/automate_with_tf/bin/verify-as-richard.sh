#!/usr/bin/env bash
# Verify ADB OCI IAM data grants with Richard's OAuth2 token.

set -Eeuo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "${script_dir}/../lib/common.sh"
load_legacy_environment

# Reuse the established wallet, token, and JWT-preflight logic from the
# original OCI IAM data-grants lab. This script only changes the persona.
# shellcheck disable=SC1091 # Resolved from the adjacent legacy lab directory.
source "${LEGACY_LAB_ROOT}/lib_adb.sh"
# shellcheck disable=SC1091 # Resolved from the adjacent legacy lab directory.
source "${LEGACY_LAB_ROOT}/lib_token_check.sh"
require_adb_env

export RICHARD_USERNAME="${RICHARD_USERNAME:-richard.c.evans@oracle.com}"
export OCI_IAM_EMPLOYEE_GROUP="${OCI_IAM_EMPLOYEE_GROUP:-EMPLOYEES}"
export OCI_IAM_MANAGER_GROUP="${OCI_IAM_MANAGER_GROUP:-MANAGERS}"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}  Verify HR Data Grants as Richard via OCI IAM                            ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${PURPLE}First obtain an OAuth token and sign in as ${RICHARD_USERNAME}.${NC}"
echo -e "${PURPLE}Required groups: ${OCI_IAM_EMPLOYEE_GROUP}, ${OCI_IAM_MANAGER_GROUP}${NC}"
echo -e "${CYAN}TOKEN_LOCATION=${OCI_TOKEN_DIR:-$HOME/.oci/adb-oci-iam}${NC}"
echo

check_oauth_token "$RICHARD_USERNAME" "$OCI_IAM_EMPLOYEE_GROUP" "$OCI_IAM_MANAGER_GROUP"
require_sqlplus
echo
echo "  sqlplus -L -s /@${ADB_SERVICE}"
echo

sqlplus -L -s "/@${ADB_SERVICE}" <<'SQL'
set echo on
set pagesize 100
set linesize 180
set tab off
set trimspool on
whenever sqlerror exit sql.sqlcode

prompt
prompt ========================================================================
prompt Richard's OCI IAM Session Identity
prompt ========================================================================

col current_user format a30
col authenticated_identity format a45
col auth_method format a25

SELECT
  sys_context('USERENV', 'CURRENT_USER') AS current_user,
  sys_context('USERENV', 'AUTHENTICATED_IDENTITY') AS authenticated_identity,
  sys_context('USERENV', 'AUTHENTICATION_METHOD') AS auth_method
FROM dual;

prompt
prompt ========================================================================
prompt Richard's Active Data Roles
prompt ========================================================================

col role_name format a30
SELECT role_name
FROM v$end_user_data_role
WHERE role_name IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS')
ORDER BY role_name;

prompt
prompt Direct Logon Session Role
prompt ========================================================================

col role format a30
SELECT role
FROM session_roles
WHERE role = 'DIRECT_LOGON_ROLE';

prompt
prompt ========================================================================
prompt Richard's Query: manager result set
prompt - Richard is mapped to the HR manager row.
prompt - The result includes Richard and direct reports.
prompt - SSN is visible only on Richard's own row.
prompt ========================================================================

col first_name format a12
col last_name format a12
col user_name format a32
col ssn format a15
col phone_number format a15
SELECT employee_id, first_name, last_name, user_name, ssn, salary, phone_number, manager_id
FROM hr.employees
ORDER BY employee_id;

prompt
prompt ========================================================================
prompt Richard's Column Authorization
prompt ========================================================================

col ssn_authorized format a16
SELECT
  first_name,
  DECODE(ORA_IS_COLUMN_AUTHORIZED(ssn), TRUE, 'TRUE', FALSE, 'FALSE') AS ssn_authorized
FROM hr.employees
ORDER BY employee_id;

exit;
SQL

echo
echo -e "${GREEN}Richard OCI IAM data-grants verification completed.${NC}"
echo
