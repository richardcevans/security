#!/bin/bash
# Create the MCP-only environment file from an existing ADB OCI IAM lab environment.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"

usage() {
  cat <<'EOF'
Usage:
  source /path/to/adb-oci-iam/.adb-oci-iam.env
  ./00_configure_lab_env.sh

This MCP-only lab does not create an Autonomous Database, OCI IAM users,
groups, OAuth applications, HR objects, data roles, or data grants. Complete
the ADB OCI IAM lab first, source its environment file, then run this command.

Required imported values:
  ADB_OCID, DB_NAME, OCI_DOMAIN_URL, TENANCY_OCID

Optional values:
  ADB_SERVICE, OCI_IAM_EMPLOYEE_GROUP, OCI_IAM_MANAGER_GROUP,
  OCI_PROFILE, OCI_CLI_PROFILE, MCP_COMPARTMENT_OCID,
  MCP_IDENTITY_DOMAIN_OCID
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

for key in ADB_OCID DB_NAME OCI_DOMAIN_URL TENANCY_OCID; do
  if [ -z "${!key:-}" ]; then
    echo "ERROR: ${key} is not set. Source .adb-oci-iam.env before running this script." >&2
    exit 1
  fi
done

umask 077
cat > "$ENV_FILE" <<EOF
# DeepSec MCP resources. Generated from the ADB OCI IAM prerequisite lab.
# Source with: source ./.deep-sec-mcp.env
export DB_NAME="${DB_NAME}"
export ADB_OCID="${ADB_OCID}"
export ADB_SERVICE="${ADB_SERVICE:-${DB_NAME}_low}"
export OCI_DOMAIN_URL="${OCI_DOMAIN_URL}"
export TENANCY_OCID="${TENANCY_OCID}"
export OCI_PROFILE="${OCI_PROFILE:-}"
export OCI_CLI_PROFILE="${OCI_CLI_PROFILE:-}"
export OCI_IAM_EMPLOYEE_GROUP="${OCI_IAM_EMPLOYEE_GROUP:-EMPLOYEES}"
export OCI_IAM_MANAGER_GROUP="${OCI_IAM_MANAGER_GROUP:-MANAGERS}"
export OCI_IAM_EMPLOYEE_GROUP_DISPLAY_NAME="${OCI_IAM_EMPLOYEE_GROUP_DISPLAY_NAME:-${OCI_IAM_EMPLOYEE_GROUP:-EMPLOYEES}}"
export OCI_IAM_MANAGER_GROUP_DISPLAY_NAME="${OCI_IAM_MANAGER_GROUP_DISPLAY_NAME:-${OCI_IAM_MANAGER_GROUP:-MANAGERS}}"
export DATABASE_TOOLS_CONNECTION_ID="${DATABASE_TOOLS_CONNECTION_ID:-}"
export DATABASE_TOOLS_CONNECTION_STRING="${DATABASE_TOOLS_CONNECTION_STRING:-}"
export DATABASE_TOOLS_CONNECTION_NAME="${DATABASE_TOOLS_CONNECTION_NAME:-deep-sec-mcp-connection}"
export DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE="${DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE:-TOKEN}"
export DATABASE_TOOLS_RUNTIME_IDENTITY="${DATABASE_TOOLS_RUNTIME_IDENTITY:-RESOURCE_PRINCIPAL}"
export DATABASE_TOOLS_RELATED_RESOURCE_TYPE="${DATABASE_TOOLS_RELATED_RESOURCE_TYPE:-AUTONOMOUS_DATABASE}"
export DATABASE_TOOLS_RELATED_RESOURCE_OCID="${DATABASE_TOOLS_RELATED_RESOURCE_OCID:-${ADB_OCID}}"
export MCP_SERVER_ID="${MCP_SERVER_ID:-}"
export MCP_SERVER_NAME="${MCP_SERVER_NAME:-deep-sec-mcp}"
export MCP_SERVER_ENDPOINT="${MCP_SERVER_ENDPOINT:-}"
export MCP_RUNTIME_IDENTITY="${MCP_RUNTIME_IDENTITY:-AUTHENTICATED_PRINCIPAL}"
export MCP_CREATE_BUILT_IN_SQL_TOOLSET="${MCP_CREATE_BUILT_IN_SQL_TOOLSET:-1}"
export MCP_BUILT_IN_SQL_TOOLSET_NAME="${MCP_BUILT_IN_SQL_TOOLSET_NAME:-deep-sec-mcp-built-in-sql-tools}"
export MCP_BUILT_IN_SQL_TOOLSET_VERSION="${MCP_BUILT_IN_SQL_TOOLSET_VERSION:-1}"
export MCP_BUILT_IN_SQL_TOOLSET_ID="${MCP_BUILT_IN_SQL_TOOLSET_ID:-}"
export MCP_BUCKET_NAME="${MCP_BUCKET_NAME:-}"
export MCP_COMPARTMENT_OCID="${MCP_COMPARTMENT_OCID:-}"
export MCP_COMPARTMENT_NAME="${MCP_COMPARTMENT_NAME:-}"
export MCP_IDENTITY_DOMAIN_OCID="${MCP_IDENTITY_DOMAIN_OCID:-}"
export MCP_IDENTITY_DOMAIN_NAME="${MCP_IDENTITY_DOMAIN_NAME:-}"
EOF

echo "Created ${ENV_FILE}"
echo "Next: source ./.deep-sec-mcp.env && ./discover_mcp_inputs.sh"
