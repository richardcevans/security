#!/bin/bash
# Remove only the Database Tools MCP resources created by this lab.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"
REMOVE_BUCKET=false
FORCE=false

usage() {
  cat <<'EOF'
Usage: ./08_cleanup_deepsec_mcp.sh [--delete-bucket] [--force]

Deletes the MCP toolset, MCP server, and Database Tools connection created by
this lab. --delete-bucket also removes the MCP Object Storage bucket.

This script never deletes the ADB OCI IAM prerequisite database, IAM users,
groups, OAuth applications, HR schema, database roles, or data grants.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --delete-bucket) REMOVE_BUCKET=true ;;
    -f|--force|--DELETE) FORCE=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .deep-sec-mcp.env not found. Run ./00_configure_lab_env.sh first." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"
source "${SCRIPT_DIR}/../lib_oci_profile.sh"

if [ "$FORCE" != true ]; then
  read -r -p "Delete DeepSec MCP resources only? Type DELETE to continue: " answer
  [ "$answer" = "DELETE" ] || exit 0
fi

oci_query() {
  PYTHONWARNINGS="${PYTHONWARNINGS:+${PYTHONWARNINGS},}ignore::FutureWarning:urllib3.poolmanager" \
    oci_with_profile "$@"
}

clear_env_key() {
  local key="$1"
  perl -pi -e "s|^export ${key}=.*|export ${key}=\"\"|" "$ENV_FILE"
}

delete_if_set() {
  local label="$1"
  local id="$2"
  shift 2
  [ -n "$id" ] || return 0
  echo "Deleting ${label}: ${id}"
  oci_query "$@" --force || echo "WARNING: could not delete ${label}; it may already be absent."
}

delete_if_set "MCP toolset" "${MCP_BUILT_IN_SQL_TOOLSET_ID:-}" \
  dbtools mcp-toolset delete --mcp-toolset-id "${MCP_BUILT_IN_SQL_TOOLSET_ID:-}"
clear_env_key MCP_BUILT_IN_SQL_TOOLSET_ID

delete_if_set "MCP server" "${MCP_SERVER_ID:-}" \
  dbtools mcp-server delete --mcp-server-id "${MCP_SERVER_ID:-}"
clear_env_key MCP_SERVER_ID
clear_env_key MCP_SERVER_ENDPOINT

delete_if_set "Database Tools connection" "${DATABASE_TOOLS_CONNECTION_ID:-}" \
  dbtools connection delete --connection-id "${DATABASE_TOOLS_CONNECTION_ID:-}"
clear_env_key DATABASE_TOOLS_CONNECTION_ID

if [ "$REMOVE_BUCKET" = true ] && [ -n "${MCP_BUCKET_NAME:-}" ]; then
  namespace=$(oci_query os ns get --query data --raw-output)
  echo "Deleting MCP bucket: ${MCP_BUCKET_NAME}"
  oci_query os object bulk-delete --bucket-name "$MCP_BUCKET_NAME" --namespace "$namespace" --force || true
  oci_query os bucket delete --bucket-name "$MCP_BUCKET_NAME" --namespace "$namespace" --empty --force || true
  clear_env_key MCP_BUCKET_NAME
fi

echo "DeepSec MCP cleanup complete. ADB OCI IAM prerequisite resources were not changed."
