#!/bin/bash
# Simulate AI prompts mapped to database tool calls against the live lab database.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/lib_deepsec_mcp.sh"

MODE="admin"
PROMPT_SET="all"

usage() {
  cat <<'EOF'
Usage:
  ./simulate_ai_tool_access.sh [--mode admin|oauth] [--prompt all|sensitive|directory|self]

Modes:
  admin     Use ADMIN password authentication. This simulates an overprivileged
            application or tool connection.
  oauth     Use the current OCI IAM OAuth token through /@ADB_SERVICE. Run
            ./04_get_iam_oauth_token.sh first and sign in as the test user.

Prompts:
  all        Run every prompt scenario.
  sensitive  Ask for employee PII and compensation data.
  directory  Ask for a business directory view.
  self       Ask for the current user's session and data-role context.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --prompt)
      PROMPT_SET="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo -e "${RED}ERROR: Unknown option: $1${NC}" >&2
      usage
      exit 1
      ;;
  esac
done

if [ "$MODE" != "admin" ] && [ "$MODE" != "oauth" ]; then
  echo -e "${RED}ERROR: --mode must be admin or oauth.${NC}" >&2
  exit 1
fi

if [ "$PROMPT_SET" != "all" ] && [ "$PROMPT_SET" != "sensitive" ] && [ "$PROMPT_SET" != "directory" ] && [ "$PROMPT_SET" != "self" ]; then
  echo -e "${RED}ERROR: --prompt must be all, sensitive, directory, or self.${NC}" >&2
  exit 1
fi

require_adb_env
require_sqlplus
require_wallet_files

if [ "$MODE" = "oauth" ]; then
  export OCI_TOKEN_DIR="${OCI_TOKEN_DIR:-$HOME/.oci/deep-sec-mcp}"
  if [ ! -d "$OCI_TOKEN_DIR" ]; then
    echo -e "${RED}ERROR: OCI_TOKEN_DIR does not exist: ${OCI_TOKEN_DIR}${NC}" >&2
    echo -e "${YELLOW}Run ./04_get_iam_oauth_token.sh and sign in as the test user, then rerun this script.${NC}" >&2
    exit 1
  fi
fi

run_sql_tool() {
  local label="$1"
  local prompt="$2"
  local sql_text="$3"
  local connect_string

  if [ "$MODE" = "admin" ]; then
    connect_string="admin/${ADMIN_PWD}@${ADB_SERVICE}"
  else
    connect_string="/@${ADB_SERVICE}"
  fi

  echo
  echo -e "${GREEN}============================================================================${NC}"
  echo -e "${GREEN}      ${label}${NC}"
  echo -e "${GREEN}============================================================================${NC}"
  echo
  echo -e "${PURPLE}AI prompt:${NC}"
  echo "  ${prompt}"
  echo
  echo -e "${CYAN}Simulated tool call:${NC}"
  echo "  tool: database.sql.query"
  echo "  connection: ${ADB_SERVICE}"
  echo "  auth_mode: ${MODE}"
  echo "  sql:"
  printf '%s\n' "$sql_text" | sed 's/^/    /'
  echo
  echo -e "${CYAN}Tool result:${NC}"

  sqlplus -L -s "$connect_string" <<SQL
set pagesize 100
set linesize 220
set tab off
set trimspool on
whenever sqlerror exit sql.sqlcode

${sql_text}

exit;
SQL
}

run_self_prompt() {
  run_sql_tool \
    "Prompt: Explain My Database Identity" \
    "Who am I connected as, and which Deep Data Security data roles are active?" \
    "col current_user format a30
col authenticated_identity format a45
col auth_method format a25
col role_name format a30
SELECT
  sys_context('USERENV', 'CURRENT_USER') AS current_user,
  sys_context('USERENV', 'AUTHENTICATED_IDENTITY') AS authenticated_identity,
  sys_context('USERENV', 'AUTHENTICATION_METHOD') AS auth_method
FROM dual;

SELECT role_name
FROM v\$end_user_data_role
WHERE role_name IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS')
ORDER BY role_name;"
}

run_directory_prompt() {
  run_sql_tool \
    "Prompt: Build Employee Directory" \
    "Build an employee directory with names, usernames, departments, managers, and phone numbers." \
    "col first_name format a12
col last_name format a12
col user_name format a34
col phone_number format a16
SELECT employee_id, first_name, last_name, user_name, department_id, manager_id, phone_number
FROM hr.employees
ORDER BY employee_id;"
}

run_sensitive_prompt() {
  run_sql_tool \
    "Prompt: Retrieve Sensitive Employee Data" \
    "Show all employees, including salary, SSN, phone number, manager, and department." \
    "col first_name format a12
col last_name format a12
col user_name format a34
col ssn format a15
col phone_number format a16
SELECT employee_id, first_name, last_name, user_name, ssn, salary, phone_number, manager_id, department_id
FROM hr.employees
ORDER BY employee_id;"
}

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      DeepSec MCP AI Prompt and Tool Access Simulator                        ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}ADB_SERVICE = ${ADB_SERVICE}${NC}"
echo -e "${CYAN}MODE        = ${MODE}${NC}"
echo -e "${CYAN}PROMPT_SET  = ${PROMPT_SET}${NC}"
echo
if [ "$MODE" = "admin" ]; then
  echo -e "${YELLOW}This is the overprivileged baseline path. It uses ADMIN and can expose data the AI prompt should not need.${NC}"
else
  echo -e "${YELLOW}This is the end-user OAuth path. Results should reflect active OCI IAM data roles and data grants.${NC}"
fi

case "$PROMPT_SET" in
  all)
    run_self_prompt
    run_directory_prompt
    run_sensitive_prompt
    ;;
  self)
    run_self_prompt
    ;;
  directory)
    run_directory_prompt
    ;;
  sensitive)
    run_sensitive_prompt
    ;;
esac

echo
echo -e "${GREEN}Simulation completed.${NC}"
echo
