#!/usr/bin/env bash
# Create one narrow native ADB MCP tool that returns only the caller-visible HR row count.
set -Eeuo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"
SQL_FILE="${SCRIPT_DIR}/13_create_hr_employee_count_tool.sql"
ACCEPT=false

usage() {
  cat <<'EOF'
Usage: ./13_create_hr_employee_count_tool.sh [--accept]

Creates or replaces the ADMIN.DEEPSEC_HR_EMPLOYEE_COUNT invoker-rights
function and registers the DEEPSEC_HR_EMPLOYEE_COUNT native ADB MCP tool.
The tool accepts no arguments and returns only a count of HR.EMPLOYEES rows
visible to its caller. It never accepts or executes caller-supplied SQL.

The script displays the database changes and requires CREATE unless --accept
is supplied. ADMIN_PWD or TF_VAR_adb_admin_password must be set.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --accept) ACCEPT=true ;;
    -h|--help) usage; exit 0 ;;
    *) printf '%bERROR: Unknown argument: %s%b\n' "$RED" "$1" "$NC" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[[ -f "$ENV_FILE" ]] || { printf '%bERROR: .deep-sec-mcp.env not found. Run ./00_configure_lab_env.sh first.%b\n' "$RED" "$NC" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
ADB_LAB_ENV_FILE="${ADB_LAB_ENV_FILE:-${SCRIPT_DIR}/../adb-oci-iam/.adb-oci-iam.env}"
[[ -f "$ADB_LAB_ENV_FILE" ]] || { printf '%bERROR: ADB_LAB_ENV_FILE is missing or unreadable: %s%b\n' "$RED" "$ADB_LAB_ENV_FILE" "$NC" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ADB_LAB_ENV_FILE"

ADMIN_PWD="${ADMIN_PWD:-${TF_VAR_adb_admin_password:-}}"
[[ -n "$ADMIN_PWD" ]] || { printf '%bERROR: Set ADMIN_PWD or TF_VAR_adb_admin_password first.%b\n' "$RED" "$NC" >&2; exit 1; }
command -v sqlplus >/dev/null || { printf '%bERROR: sqlplus is required.%b\n' "$RED" "$NC" >&2; exit 1; }
[[ -n "${ADB_SERVICE:-}" ]] || { printf '%bERROR: ADB_SERVICE is required.%b\n' "$RED" "$NC" >&2; exit 1; }

echo
printf '%b============================================================================%b\n' "$GREEN" "$NC"
printf '%b  Create Narrow Native ADB MCP Tool for HR.EMPLOYEES                       %b\n' "$GREEN" "$NC"
printf '%b============================================================================%b\n' "$GREEN" "$NC"
echo
echo "ADB service = $ADB_SERVICE"
echo "Tool        = ${ADB_MCP_HR_TOOL_NAME:-DEEPSEC_HR_EMPLOYEE_COUNT}"
echo 'Planned database changes:'
echo '  1. Create or replace ADMIN.DEEPSEC_HR_EMPLOYEE_COUNT as AUTHID CURRENT_USER.'
echo '  2. Grant EXECUTE on that function to PUBLIC.'
echo '  3. Replace only this lab Select AI Agent tool.'
echo 'The function contains one fixed SELECT COUNT(*) FROM HR.EMPLOYEES.'
echo "It accepts no SQL and cannot bypass the caller's HR data grants."
echo
if [[ "$ACCEPT" != true ]]; then
  read -r -p 'Type CREATE to continue: ' answer
  [[ "$answer" == CREATE ]] || { echo 'No database objects were changed.'; exit 0; }
fi

sqlplus -L -s "admin/${ADMIN_PWD}@${ADB_SERVICE}" @"$SQL_FILE"
echo
echo -e "${GREEN}Native MCP tool registration completed.${NC}"
echo 'Next: run ./14_verify_hr_employee_count_tool_as_current_user.sh with a current OCI IAM database token.'
