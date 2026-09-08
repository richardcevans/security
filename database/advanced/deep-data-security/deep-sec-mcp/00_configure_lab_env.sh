#!/bin/bash
# Create the native ADB MCP environment file from an existing ADB OCI IAM lab environment.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"
GENAI_LAB_DIR="${GENAI_LAB_DIR:-${SCRIPT_DIR}/../deep-sec-gen-ai-demo}"
GENAI_BASELINE_FILE="${SCRIPT_DIR}/.deep-sec-mcp.genai-baseline.env"

usage() {
  cat <<'EOF'
Usage:
  source /path/to/adb-oci-iam/.adb-oci-iam.env
  export GENAI_LAB_DIR=/path/to/deep-sec-gen-ai-demo  # optional when adjacent
  ./00_configure_lab_env.sh

This native ADB MCP lab does not create an Autonomous Database, OCI IAM users,
groups, OAuth applications, HR objects, data roles, or data grants. Complete
the ADB OCI IAM and Deep Security GenAI Demo labs first, source the ADB OCI
IAM environment file, then run this command.

Required imported values:
  ADB_OCID, DB_NAME, OCI_DOMAIN_URL, TENANCY_OCID

Optional values:
  ADB_SERVICE, OCI_IAM_EMPLOYEE_GROUP, OCI_IAM_MANAGER_GROUP,
  OCI_PROFILE_NAME, OCI_PROFILE, OCI_CLI_PROFILE, ROOT_COMP_ID,
  OCI_COMPARTMENT, MCP_COMPARTMENT_OCID,
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

if [ ! -d "$GENAI_LAB_DIR" ]; then
  echo "ERROR: GenAI lab directory is not available: ${GENAI_LAB_DIR}" >&2
  echo "Set GENAI_LAB_DIR to the completed deep-sec-gen-ai-demo lab directory." >&2
  exit 1
fi

for script in 01_genai_chicago_smoke.sh 07_show_hr_employees_audit_trail.sh; do
  if [ ! -x "${GENAI_LAB_DIR}/${script}" ]; then
    echo "ERROR: ${GENAI_LAB_DIR}/${script} is missing or not executable." >&2
    echo "Complete and extract the deep-sec-gen-ai-demo lab before configuring MCP." >&2
    exit 1
  fi
done

if [ "${DATABASE_TOOLS_RELATED_RESOURCE_TYPE:-}" = "AUTONOMOUS_DATABASE" ]; then
  DATABASE_TOOLS_RELATED_RESOURCE_TYPE="AUTONOMOUSDATABASE"
fi

umask 077
cat > "$ENV_FILE" <<EOF
# DeepSec MCP resources. Generated from the ADB OCI IAM prerequisite lab.
# Source with: source ./.deep-sec-mcp.env
export DB_NAME="${DB_NAME}"
export ADB_OCID="${ADB_OCID}"
export ADB_SERVICE="${ADB_SERVICE:-${DB_NAME}_low}"
export OCI_DOMAIN_URL="${OCI_DOMAIN_URL}"
export TENANCY_OCID="${TENANCY_OCID}"
export ROOT_COMP_ID="${ROOT_COMP_ID:-}"
export OCI_COMPARTMENT="${OCI_COMPARTMENT:-}"
export OCI_PROFILE_NAME="${OCI_PROFILE_NAME:-}"
export OCI_PROFILE="${OCI_PROFILE:-}"
export OCI_CLI_PROFILE="${OCI_CLI_PROFILE:-}"
export OCI_IAM_EMPLOYEE_GROUP="${OCI_IAM_EMPLOYEE_GROUP:-EMPLOYEES}"
export OCI_IAM_MANAGER_GROUP="${OCI_IAM_MANAGER_GROUP:-MANAGERS}"
export OCI_IAM_EMPLOYEE_GROUP_DISPLAY_NAME="${OCI_IAM_EMPLOYEE_GROUP_DISPLAY_NAME:-${OCI_IAM_EMPLOYEE_GROUP:-EMPLOYEES}}"
export OCI_IAM_MANAGER_GROUP_DISPLAY_NAME="${OCI_IAM_MANAGER_GROUP_DISPLAY_NAME:-${OCI_IAM_MANAGER_GROUP:-MANAGERS}}"
export GENAI_LAB_DIR="${GENAI_LAB_DIR}"
export GENAI_BASELINE_FILE="${GENAI_BASELINE_FILE}"
export ADB_LAB_ENV_FILE="${ADB_LAB_ENV_FILE:-${SCRIPT_DIR}/../adb-oci-iam/.adb-oci-iam.env}"
export WALLET_DIR="${WALLET_DIR:-}"
# Native Autonomous AI Database MCP Server values.
# Preserve the literal dollar sign in the generated shell environment file.
export ADB_MCP_FEATURE_TAG="${ADB_MCP_FEATURE_TAG:-adb\\\$feature}"
export ADB_MCP_ENABLED="${ADB_MCP_ENABLED:-0}"
export ADB_MCP_REGION="${ADB_MCP_REGION:-}"
export ADB_MCP_ENDPOINT="${ADB_MCP_ENDPOINT:-}"
export ADB_MCP_HR_TOOL_NAME="${ADB_MCP_HR_TOOL_NAME:-DEEPSEC_HR_EMPLOYEE_COUNT}"
# The remaining Database Tools values describe the earlier experiment. They are
# retained only for diagnosis and cleanup; native ADB MCP does not use them.
export DATABASE_TOOLS_CONNECTION_ID="${DATABASE_TOOLS_CONNECTION_ID:-}"
export DATABASE_TOOLS_CONNECTION_STRING="${DATABASE_TOOLS_CONNECTION_STRING:-}"
export DATABASE_TOOLS_CONNECTION_NAME="${DATABASE_TOOLS_CONNECTION_NAME:-deep-sec-mcp-connection}"
export DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE="${DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE:-TOKEN}"
export DATABASE_TOOLS_RUNTIME_IDENTITY="${DATABASE_TOOLS_RUNTIME_IDENTITY:-RESOURCE_PRINCIPAL}"
export DATABASE_TOOLS_RELATED_RESOURCE_TYPE="${DATABASE_TOOLS_RELATED_RESOURCE_TYPE:-AUTONOMOUSDATABASE}"
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
export MCP_WALLET_VAULT_NAME="${MCP_WALLET_VAULT_NAME:-deep-sec-mcp-wallet-vault}"
export MCP_WALLET_KEY_NAME="${MCP_WALLET_KEY_NAME:-deep-sec-mcp-wallet-key}"
export MCP_WALLET_SECRET_NAME="${MCP_WALLET_SECRET_NAME:-deep-sec-mcp-cwallet-sso}"
export MCP_WALLET_DYNAMIC_GROUP_NAME="${MCP_WALLET_DYNAMIC_GROUP_NAME:-deep-sec-mcp-connection-rp}"
export MCP_WALLET_POLICY_NAME="${MCP_WALLET_POLICY_NAME:-deep-sec-mcp-connection-wallet-read}"
export MCP_WALLET_VAULT_ID="${MCP_WALLET_VAULT_ID:-}"
export MCP_WALLET_KEY_ID="${MCP_WALLET_KEY_ID:-}"
export MCP_WALLET_SECRET_ID="${MCP_WALLET_SECRET_ID:-}"
EOF

echo "Created ${ENV_FILE}"
echo "Next: source ./.deep-sec-mcp.env && ./01_verify_genai_baseline.sh"
