#!/bin/bash
# Remove DeepSec MCP demo database objects and optional MCP Server Tools resources.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

FORCE=false
CLEAN_DB_OBJECTS=true
REMOVE_MCP_RESOURCES=false
DELETE_BUCKET=false
CLEAN_LOCAL_CACHE=true
CLEANUP_FAILURES=()

usage() {
  cat <<'EOF'
Usage:
  ./08_cleanup_deepsec_mcp.sh [options]

Default:
  Remove DeepSec MCP database demo objects and local OAuth token cache.

Options:
  --mcp-resources       Delete MCP toolset, MCP server, Database Tools connection, and clear their OCIDs from .deep-sec-mcp.env.
  --delete-bucket       Also delete the MCP Object Storage bucket. Implies --mcp-resources and empties the bucket first.
  --post-adb-oci-iam    Remove only DeepSec MCP-specific MCP resources and token cache; keep ADB-S, OCI IAM apps, groups, users, wallet, and DB objects.
  --keep-db-objects     Do not drop HR, data roles, data grants, or local DB roles.
  --keep-local-cache    Do not remove the local OAuth token cache.
  -f, --force, --DELETE Do not prompt for confirmation.
  -h, --help            Show this help.
EOF
}
for arg in "$@"; do
  case "$arg" in
    --mcp-resources)
      REMOVE_MCP_RESOURCES=true
      ;;
    --delete-bucket)
      REMOVE_MCP_RESOURCES=true
      DELETE_BUCKET=true
      ;;
    --post-adb-oci-iam)
      CLEAN_DB_OBJECTS=false
      REMOVE_MCP_RESOURCES=true
      CLEAN_LOCAL_CACHE=true
      ;;
    --keep-db-objects)
      CLEAN_DB_OBJECTS=false
      ;;
    --keep-local-cache)
      CLEAN_LOCAL_CACHE=false
      ;;
    -f|--force|--DELETE)
      FORCE=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
source "${SCRIPT_DIR}/lib_deepsec_mcp.sh"

confirm() {
  local prompt="$1"

  if [ "$FORCE" = true ]; then
    return 0
  fi

  echo -n "${prompt} Type DELETE to continue: "
  read -r answer
  [ "$answer" = "DELETE" ]
}

record_cleanup_failure() {
  CLEANUP_FAILURES+=("$1")
}

run_cleanup_cmd() {
  local description="$1"
  shift

  echo -e "${CYAN}${description}:${NC}"
  show_cmd "$@"
  if "$@"; then
    echo -e "${CYAN}  OK${NC}"
  else
    local status=$?
    echo -e "${YELLOW}  Failed with exit code ${status}; continuing.${NC}"
    record_cleanup_failure "${description} failed with exit code ${status}"
  fi
}

oci_query() {
  PYTHONWARNINGS="${PYTHONWARNINGS:+${PYTHONWARNINGS},}ignore::FutureWarning:urllib3.poolmanager" \
    oci "$@"
}

clear_env_key() {
  local key="$1"
  [ -f "$ENV_FILE" ] || return 0

  if grep -q "^export ${key}=" "$ENV_FILE"; then
    perl -pi -e "s|^export ${key}=.*|export ${key}=\\\"\\\"|" "$ENV_FILE"
  fi
}

delete_mcp_toolset() {
  if [ -z "${MCP_BUILT_IN_SQL_TOOLSET_ID:-}" ]; then
    echo -e "${YELLOW}Skipping MCP toolset; MCP_BUILT_IN_SQL_TOOLSET_ID is not set.${NC}"
    return 0
  fi

  run_cleanup_cmd "Deleting MCP built-in SQL toolset ${MCP_BUILT_IN_SQL_TOOLSET_ID}" \
    oci_query dbtools mcp-toolset delete \
      --mcp-toolset-id "$MCP_BUILT_IN_SQL_TOOLSET_ID" \
      --force
  clear_env_key MCP_BUILT_IN_SQL_TOOLSET_ID
}

delete_mcp_server() {
  if [ -z "${MCP_SERVER_ID:-}" ]; then
    echo -e "${YELLOW}Skipping MCP server; MCP_SERVER_ID is not set.${NC}"
    return 0
  fi

  run_cleanup_cmd "Deleting MCP server ${MCP_SERVER_ID}" \
    oci_query dbtools mcp-server delete \
      --mcp-server-id "$MCP_SERVER_ID" \
      --force
  clear_env_key MCP_SERVER_ID
  clear_env_key MCP_SERVER_ENDPOINT
}

delete_database_tools_connection() {
  if [ -z "${DATABASE_TOOLS_CONNECTION_ID:-}" ]; then
    echo -e "${YELLOW}Skipping Database Tools connection; DATABASE_TOOLS_CONNECTION_ID is not set.${NC}"
    return 0
  fi

  run_cleanup_cmd "Deleting Database Tools connection ${DATABASE_TOOLS_CONNECTION_ID}" \
    oci_query dbtools connection delete \
      --connection-id "$DATABASE_TOOLS_CONNECTION_ID" \
      --force
  clear_env_key DATABASE_TOOLS_CONNECTION_ID
}

delete_mcp_bucket() {
  if [ -z "${MCP_BUCKET_NAME:-}" ]; then
    echo -e "${YELLOW}Skipping MCP bucket; MCP_BUCKET_NAME is not set.${NC}"
    return 0
  fi

  local namespace="${NAMESPACE:-}"
  if [ -z "$namespace" ]; then
    namespace=$(oci_query os ns get --raw-output --query data 2>/dev/null || true)
  fi

  if [ -z "$namespace" ] || [ "$namespace" = "null" ]; then
    echo -e "${YELLOW}Skipping MCP bucket; Object Storage namespace could not be determined.${NC}"
    return 0
  fi

  run_cleanup_cmd "Deleting MCP Object Storage bucket ${MCP_BUCKET_NAME}" \
    oci_query os bucket delete \
      --namespace-name "$namespace" \
      --bucket-name "$MCP_BUCKET_NAME" \
      --empty \
      --force
}

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Clean Up DeepSec MCP                                                  ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}ADB_SERVICE          = ${ADB_SERVICE:-<not set>}${NC}"
echo -e "${CYAN}CLEAN_DB_OBJECTS     = ${CLEAN_DB_OBJECTS}${NC}"
echo -e "${CYAN}REMOVE_MCP_RESOURCES = ${REMOVE_MCP_RESOURCES}${NC}"
echo -e "${CYAN}DELETE_BUCKET        = ${DELETE_BUCKET}${NC}"
echo

if [ "$CLEAN_DB_OBJECTS" = true ]; then
  require_adb_env

  if confirm "This removes HR schema, Deep Data Security roles/grants, and local DB roles."; then
    echo -e "${CYAN}SQL*Plus command:${NC}"
    show_cmd sqlplus -L -s "admin/<hidden>@${ADB_SERVICE}"

    admin_sqlplus <<'SQL'
set echo off
set serveroutput on
set feedback off
set heading off
whenever sqlerror continue

DECLARE
  TYPE step_list IS TABLE OF VARCHAR2(4000);
  steps step_list := step_list(
    'DROP DATA GRANT hr.HRAPP_MANAGER_ACCESS',
    'DROP DATA GRANT hr.EMPLOYEE_CONTEXT_GRANT',
    'DROP DATA GRANT hr.HRAPP_EMPLOYEES_ACCESS',
    'DROP DATA ROLE hrapp_managers',
    'DROP DATA ROLE hrapp_employees',
    'DROP ROLE direct_logon_role',
    'DROP ROLE employee_context_admin',
    'DROP USER hr CASCADE'
  );
BEGIN
  FOR i IN 1 .. steps.COUNT LOOP
    BEGIN
      DBMS_OUTPUT.PUT_LINE('  ' || steps(i));
      EXECUTE IMMEDIATE steps(i);
      DBMS_OUTPUT.PUT_LINE('    OK');
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('    Skipped or failed: ' || SQLERRM);
    END;
  END LOOP;
END;
/

exit;
SQL
  else
    echo -e "${YELLOW}Skipped database object cleanup.${NC}"
  fi
else
  echo -e "${YELLOW}Skipping database object cleanup.${NC}"
fi

if [ "$REMOVE_MCP_RESOURCES" = true ]; then
  if ! command -v oci >/dev/null 2>&1; then
    echo -e "${RED}ERROR: OCI CLI is required for --mcp-resources cleanup.${NC}" >&2
    exit 1
  fi

  if confirm "This deletes DeepSec MCP Database Tools resources but keeps ADB-S and OCI IAM apps/groups/users."; then
    delete_mcp_toolset
    delete_mcp_server
    delete_database_tools_connection
    if [ "$DELETE_BUCKET" = true ]; then
      delete_mcp_bucket
    fi
  else
    echo -e "${YELLOW}Skipped MCP resource cleanup.${NC}"
  fi
else
  echo -e "${YELLOW}Skipping MCP resource cleanup. Use --mcp-resources to delete MCP Server Tools resources.${NC}"
fi

if [ "$CLEAN_LOCAL_CACHE" = true ]; then
  echo
  echo -e "${YELLOW}Removing local OAuth token cache ${OCI_TOKEN_DIR:-$HOME/.oci/deep-sec-mcp}${NC}"
  rm -rf "${OCI_TOKEN_DIR:-$HOME/.oci/deep-sec-mcp}"
else
  echo -e "${YELLOW}Skipping local token cache cleanup.${NC}"
fi

echo
if [ "${#CLEANUP_FAILURES[@]}" -gt 0 ]; then
  echo -e "${YELLOW}Cleanup completed with non-blocking failures:${NC}"
  for failure in "${CLEANUP_FAILURES[@]}"; do
    echo "  - ${failure}"
  done
  echo
fi
echo -e "${GREEN}Cleanup completed.${NC}"
echo
