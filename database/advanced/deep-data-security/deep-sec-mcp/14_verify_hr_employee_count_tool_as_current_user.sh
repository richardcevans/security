#!/usr/bin/env bash
# Verify the native MCP tool function respects the current OCI IAM database session.
set -Eeuo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"

[[ -f "$ENV_FILE" ]] || { printf '%bERROR: .deep-sec-mcp.env not found.%b\n' "$RED" "$NC" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
ADB_LAB_ENV_FILE="${ADB_LAB_ENV_FILE:-${SCRIPT_DIR}/../adb-oci-iam/.adb-oci-iam.env}"
[[ -f "$ADB_LAB_ENV_FILE" ]] || { printf '%bERROR: ADB_LAB_ENV_FILE is missing or unreadable: %s%b\n' "$RED" "$ADB_LAB_ENV_FILE" "$NC" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ADB_LAB_ENV_FILE"
TOKEN_CHECKER="$(dirname "$ADB_LAB_ENV_FILE")/lib_token_check.sh"
[[ -f "$TOKEN_CHECKER" ]] || { printf '%bERROR: Token checker is missing: %s%b\n' "$RED" "$TOKEN_CHECKER" "$NC" >&2; exit 1; }
# shellcheck disable=SC1090
source "$TOKEN_CHECKER"
command -v sqlplus >/dev/null || { printf '%bERROR: sqlplus is required.%b\n' "$RED" "$NC" >&2; exit 1; }

check_current_oauth_token >&2
echo
printf '%b============================================================================%b\n' "$GREEN" "$NC"
printf '%b  Verify Native MCP Tool Function as Current OCI IAM User                  %b\n' "$GREEN" "$NC"
printf '%b============================================================================%b\n' "$GREEN" "$NC"
echo
echo 'The fixed function executes with AUTHID CURRENT_USER.'
echo 'It returns only the HR.EMPLOYEES row count authorized for this OCI IAM database session.'
echo
sqlplus -L -s "/@${ADB_SERVICE}" @"${SCRIPT_DIR}/14_verify_hr_employee_count_tool_as_current_user.sql"
