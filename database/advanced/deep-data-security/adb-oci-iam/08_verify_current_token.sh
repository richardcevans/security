#!/bin/bash
# Verify the current OCI IAM OAuth token without hard-coding a lab persona.

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "${SCRIPT_DIR}/lib_adb.sh"
# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "${SCRIPT_DIR}/lib_token_check.sh"

usage() {
  cat <<'EOF'
Usage: ./08_verify_current_token.sh [--expect-user USER] [--require-group GROUP]...

Uses the JWT currently stored in $OCI_TOKEN_DIR/token (or
$HOME/.oci/adb-oci-iam/token). The token, not this command, determines the
OCI IAM user that connects. --expect-user only prevents an accidental test
with a token issued for someone else.

Examples:
  ./08_verify_current_token.sh
  ./08_verify_current_token.sh --expect-user richard.c.evans@oracle.com
  ./08_verify_current_token.sh --require-group EMPLOYEES --require-group MANAGERS
EOF
}

expected_user=''
required_groups=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --expect-user)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      expected_user=$2
      shift 2
      ;;
    --require-group)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      required_groups+=("$2")
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

require_adb_env

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Verify Current OCI IAM OAuth Token                                    ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}TOKEN_LOCATION=${OCI_TOKEN_DIR:-$HOME/.oci/adb-oci-iam}${NC}"
require_sqlplus
check_current_oauth_token "$expected_user" "${required_groups[@]}"

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
prompt Current OCI IAM Session Identity
prompt ========================================================================

col current_user format a30
col authenticated_identity format a55
col auth_method format a25

SELECT
  sys_context('USERENV', 'CURRENT_USER') AS current_user,
  sys_context('USERENV', 'AUTHENTICATED_IDENTITY') AS authenticated_identity,
  sys_context('USERENV', 'AUTHENTICATION_METHOD') AS auth_method
FROM dual;

prompt
prompt ========================================================================
prompt Active Data Roles and Session Roles
prompt ========================================================================

col role_name format a30
SELECT role_name
FROM v$end_user_data_role
ORDER BY role_name;

col role format a30
SELECT role
FROM session_roles
ORDER BY role;

prompt
prompt ========================================================================
prompt HR Employees Visible to the Current Token Subject
prompt ========================================================================

col first_name format a12
col last_name format a12
col user_name format a40
col ssn format a15
col phone_number format a15
SELECT employee_id, first_name, last_name, user_name, ssn, salary, phone_number, manager_id
FROM hr.employees
ORDER BY employee_id;

prompt
prompt ========================================================================
prompt Column Authorization
prompt ========================================================================

col ssn_authorized format a16
SELECT
  first_name,
  DECODE(ORA_IS_COLUMN_AUTHORIZED(ssn), TRUE, 'TRUE', FALSE, 'FALSE') AS ssn_authorized
FROM hr.employees
ORDER BY employee_id;

exit;
SQL
