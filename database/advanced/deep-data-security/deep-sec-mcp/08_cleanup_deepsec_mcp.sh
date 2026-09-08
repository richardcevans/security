#!/bin/bash
# Remove Database Tools MCP resources created by this lab.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"

DELETE_TOOLSET=false
DELETE_SERVER=false
DELETE_CONNECTION=false
DELETE_BUCKET=false
DELETE_LOCAL_ENV=false
DELETE_MATCHING_RESOURCES=false
REMOVE_ALL=false
FORCE=false
ACTION_SELECTED=false
CLEANUP_COMPLETED=()
CLEANUP_NOT_COMPLETED=()
CLEANUP_FAILURES=()

usage() {
  cat <<'EOF'
Usage:
  ./08_cleanup_deepsec_mcp.sh [options]

Options:
  --delete-toolset       Delete the built-in SQL MCP toolset.
  --delete-server        Delete the MCP server and all of its associated toolsets.
  --delete-connection    Delete the Database Tools connection.
  --delete-matching-resources
                         Delete every lab resource with the configured toolset,
                         server, and connection display names.
  --delete-bucket        Delete the MCP Object Storage bucket and its objects.
  --delete-local-env     Delete .deep-sec-mcp.env after resource cleanup.
  --remove-all           Select every cleanup action above, including all
                         matching duplicate Database Tools resources.
  -f, --force, --DELETE  Do not prompt for confirmation.
  -h, --help             Show this help.

With no resource option, this script preserves the previous behavior: it
deletes the toolset, MCP server, and Database Tools connection. It does not
delete the bucket or local environment file unless selected.

This script never deletes the ADB OCI IAM prerequisite database, IAM users,
groups, OAuth applications, HR schema, database roles, or data grants.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --delete-toolset) DELETE_TOOLSET=true; ACTION_SELECTED=true ;;
    --delete-server) DELETE_SERVER=true; ACTION_SELECTED=true ;;
    --delete-connection) DELETE_CONNECTION=true; ACTION_SELECTED=true ;;
    --delete-matching-resources) DELETE_MATCHING_RESOURCES=true; ACTION_SELECTED=true ;;
    --delete-bucket) DELETE_BUCKET=true; ACTION_SELECTED=true ;;
    --delete-local-env) DELETE_LOCAL_ENV=true; ACTION_SELECTED=true ;;
    --remove-all)
      REMOVE_ALL=true
      DELETE_TOOLSET=true
      DELETE_SERVER=true
      DELETE_CONNECTION=true
      DELETE_MATCHING_RESOURCES=true
      DELETE_BUCKET=true
      DELETE_LOCAL_ENV=true
      ACTION_SELECTED=true
      ;;
    -f|--force|--DELETE) FORCE=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

if [ "$ACTION_SELECTED" = false ]; then
  DELETE_TOOLSET=true
  DELETE_SERVER=true
  DELETE_CONNECTION=true
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .deep-sec-mcp.env is not available. Run ./00_configure_lab_env.sh first." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"
source "${SCRIPT_DIR}/lib_oci_profile.sh"

confirm() {
  local prompt="$1"
  if [ "$FORCE" = true ]; then
    return 0
  fi
  read -r -p "${prompt} Type DELETE to continue: " answer
  [ "$answer" = "DELETE" ]
}

record_completed() { CLEANUP_COMPLETED+=("$1"); }
record_not_completed() { CLEANUP_NOT_COMPLETED+=("$1"); }
record_failure() { CLEANUP_FAILURES+=("$1"); }

oci_query() {
  PYTHONWARNINGS="${PYTHONWARNINGS:+${PYTHONWARNINGS},}ignore::FutureWarning:urllib3.poolmanager" \
    oci_with_profile "$@"
}

run_cleanup_cmd() {
  local description="$1"
  shift
  local command_output status oci_status detail message error_code next_step

  echo -ne "${description}... "
  if command_output=$("$@" 2>&1); then
    echo "OK"
    record_completed "$description"
    return 0
  fi

  status=$?
  oci_status=$(printf '%s\n' "$command_output" | sed -nE 's/^[[:space:]]*"status": ([0-9]+),?$/\1/p' | head -n 1)
  detail=$(printf '%s\n' "$command_output" | sed -nE 's/^[[:space:]]*"detail": "(.*)",?$/\1/p' | head -n 1)
  message=$(printf '%s\n' "$command_output" | sed -nE 's/^[[:space:]]*"message": "(.*)",?$/\1/p' | head -n 1)
  error_code=$(printf '%s\n' "$command_output" | sed -nE 's/^[[:space:]]*"code": "?([^",]+)"?,?$/\1/p' | head -n 1)
  detail="${detail:-${message:-${error_code:-}}}"
  detail="${detail:-Command failed without a detailed error message.}"

  if [ "$oci_status" = "404" ]; then
    echo "already absent (OCI status 404)"
    record_not_completed "$description — already absent"
    return 0
  fi

  if [[ "$description" == *"MCP toolset"* ]] && [ "$oci_status" = "409" ]; then
    next_step="The toolset is still attached to an MCP server. Delete the MCP server first; this script now uses that order for matching-resource cleanup."
  elif [[ "$detail" == *"referenced by at least one database tools mcp server"* ]]; then
    next_step="Delete the MCP server first (and its toolset first, if present), then retry the connection deletion."
  else
    case "$oci_status" in
      400) next_step="Verify the resource state and cleanup order, then retry." ;;
      401) next_step="Refresh your OCI credentials, then retry." ;;
      403) next_step="Obtain the required Database Tools or Object Storage permission, then retry." ;;
      *) next_step="Verify the OCI CLI configuration and resource identifier, then retry." ;;
    esac
  fi
  if [ -n "$oci_status" ]; then
    echo "ERROR (OCI status ${oci_status})"
  else
    echo "ERROR (command exit ${status})"
  fi
  echo "  Cause: ${detail}"
  echo "  Next: ${next_step}"
  record_not_completed "$description — ${detail}"
  record_failure "$description failed${oci_status:+ (OCI status ${oci_status})}"
  return 1
}

clear_env_key() {
  local key="$1"
  [ -f "$ENV_FILE" ] || return 0
  perl -pi -e "s|^export ${key}=.*|export ${key}=\"\"|" "$ENV_FILE"
}

delete_resource() {
  local description="$1"
  local id="$2"
  local env_key="$3"
  local resource_name="${description#Deleted }"
  shift 3
  if [ -z "$id" ] || [ "$id" = "null" ]; then
    echo "Skipping ${resource_name}; identifier is not set."
    record_not_completed "${resource_name} — identifier is not set"
    return 0
  fi
  if run_cleanup_cmd "$description" oci_query "$@" --force; then
    clear_env_key "$env_key"
    return 0
  fi
  return 1
}

list_matching_resource_ids() {
  local resource_name="$1"
  shift
  local command_output parsed_ids status oci_status detail

  if command_output=$(oci_query "$@" --all --output json 2>&1); then
    if ! parsed_ids=$(printf '%s' "$command_output" | python3 -c '
import json
import sys

try:
    payload = json.load(sys.stdin)
    data = payload.get("data") or []
    # OCI list APIs are inconsistent: some return data as a list while
    # Database Tools list APIs return data.items. Normalize both forms.
    if isinstance(data, dict):
        data = data.get("items") or []
    if not isinstance(data, list):
        raise ValueError("data is neither a list nor an object with items")
except (json.JSONDecodeError, AttributeError, ValueError) as error:
    print("ERROR: Could not read the OCI list response: {}".format(error), file=sys.stderr)
    raise SystemExit(1)
for item in data:
    if not isinstance(item, dict):
        continue
    resource_id = item.get("id")
    if resource_id:
        print(resource_id)
' 2>&1); then
      echo "ERROR: Could not list matching ${resource_name}." >&2
      echo "  Cause: ${parsed_ids}" >&2
      echo "  Next: Verify the OCI CLI response format and retry." >&2
      return 1
    fi
    printf '%s' "$parsed_ids"
    return 0
  fi

  status=$?
  oci_status=$(printf '%s\n' "$command_output" | sed -nE 's/^[[:space:]]*"status": ([0-9]+),?$/\1/p' | head -n 1)
  detail=$(printf '%s\n' "$command_output" | sed -nE 's/^[[:space:]]*"detail": "(.*)",?$/\1/p' | head -n 1)
  detail="${detail:-Could not list matching resources.}"
  echo "ERROR: Could not list matching ${resource_name}${oci_status:+ (OCI status ${oci_status})}." >&2
  echo "  Cause: ${detail}" >&2
  echo "  Next: Verify OCI credentials and Database Tools list permission, then retry." >&2
  return "$status"
}

delete_matching_resources() {
  local resource_name="$1"
  local delete_description="$2"
  local delete_id_option="$3"
  shift 3
  local list_output resource_id
  local -a resource_ids
  local -a delete_command

  case "$delete_id_option" in
    --mcp-toolset-id) delete_command=(dbtools mcp-toolset delete --wait-for-state SUCCEEDED --max-wait-seconds 120 --wait-interval-seconds 5) ;;
    --mcp-server-id) delete_command=(dbtools mcp-server cascading-delete --wait-for-state SUCCEEDED --max-wait-seconds 120 --wait-interval-seconds 5) ;;
    --connection-id) delete_command=(dbtools connection delete --wait-for-state SUCCEEDED --max-wait-seconds 120 --wait-interval-seconds 5) ;;
    *)
      echo "ERROR: Unsupported matching-resource delete operation: ${delete_id_option}." >&2
      record_failure "Matching ${resource_name} cleanup is not configured"
      return 2
      ;;
  esac

  if ! list_output=$(list_matching_resource_ids "$resource_name" "$@"); then
    record_not_completed "Matching ${resource_name} — could not list"
    record_failure "Listing matching ${resource_name} failed"
    return 1
  fi
  mapfile -t resource_ids <<< "$list_output"
  if [ -z "${resource_ids[0]:-}" ]; then
    echo "No matching ${resource_name} found."
    record_not_completed "Matching ${resource_name} — already absent"
    return 0
  fi

  for resource_id in "${resource_ids[@]}"; do
    if ! run_cleanup_cmd "$delete_description (${resource_id})" \
      oci_query "${delete_command[@]}" "$delete_id_option" "$resource_id" --force; then
      return 1
    fi
  done
}

delete_all_matching_mcp_resources() {
  if [ -z "${MCP_COMPARTMENT_OCID:-}" ] || [ "$MCP_COMPARTMENT_OCID" = "null" ]; then
    echo "ERROR: MCP_COMPARTMENT_OCID is not set; matching resources were not deleted."
    echo "  Next: Run ./discover_mcp_inputs.sh, then retry --delete-matching-resources."
    record_not_completed "Matching MCP resources — MCP_COMPARTMENT_OCID is not set"
    record_failure "Matching MCP resource cleanup could not start"
    return 1
  fi

  echo "Removing every matching lab resource in compartment ${MCP_COMPARTMENT_OCID}..."
  delete_matching_resources "MCP servers named ${MCP_SERVER_NAME}" \
    "Deleted matching MCP server" --mcp-server-id \
    dbtools mcp-server list --compartment-id "$MCP_COMPARTMENT_OCID" \
    --display-name "${MCP_SERVER_NAME}" || return 1
  # A toolset can be attached to a server and then returns OCI 409 if deleted
  # first. Cascading server deletion removes attached toolsets; this follow-up
  # deletes any matching unattached duplicates.
  delete_matching_resources "built-in SQL MCP toolsets named ${MCP_BUILT_IN_SQL_TOOLSET_NAME}" \
    "Deleted matching built-in SQL MCP toolset" --mcp-toolset-id \
    dbtools mcp-toolset list --compartment-id "$MCP_COMPARTMENT_OCID" \
    --display-name "${MCP_BUILT_IN_SQL_TOOLSET_NAME}" || return 1
  delete_matching_resources "Database Tools connections named ${DATABASE_TOOLS_CONNECTION_NAME}" \
    "Deleted matching Database Tools connection" --connection-id \
    dbtools connection list --compartment-id "$MCP_COMPARTMENT_OCID" \
    --display-name "${DATABASE_TOOLS_CONNECTION_NAME}" --type ORACLE_DATABASE || return 1

  clear_env_key MCP_BUILT_IN_SQL_TOOLSET_ID
  clear_env_key MCP_SERVER_ID
  clear_env_key MCP_SERVER_ENDPOINT
  clear_env_key DATABASE_TOOLS_CONNECTION_ID
}

echo
echo "============================================================================"
echo "      Clean Up DeepSec MCP Resources"
echo "============================================================================"
echo "DELETE_TOOLSET    = ${DELETE_TOOLSET}"
echo "DELETE_SERVER     = ${DELETE_SERVER}"
echo "DELETE_CONNECTION = ${DELETE_CONNECTION}"
echo "DELETE_BUCKET     = ${DELETE_BUCKET}"
echo "DELETE_LOCAL_ENV  = ${DELETE_LOCAL_ENV}"
echo "DELETE_MATCHING_RESOURCES = ${DELETE_MATCHING_RESOURCES}"
echo

if ! confirm "Delete the selected DeepSec MCP resources?"; then
  echo "No resources were deleted."
  exit 0
fi

if [ "$DELETE_MATCHING_RESOURCES" = true ]; then
  delete_all_matching_mcp_resources || true
  DELETE_TOOLSET=false
  DELETE_SERVER=false
  DELETE_CONNECTION=false
fi

if [ "$DELETE_TOOLSET" = true ]; then
  delete_resource "Deleted built-in SQL MCP toolset" "${MCP_BUILT_IN_SQL_TOOLSET_ID:-}" MCP_BUILT_IN_SQL_TOOLSET_ID \
    dbtools mcp-toolset delete --mcp-toolset-id "${MCP_BUILT_IN_SQL_TOOLSET_ID:-}" \
    --wait-for-state SUCCEEDED --max-wait-seconds 120 --wait-interval-seconds 5 || true
fi

if [ "$DELETE_SERVER" = true ]; then
  if delete_resource "Deleted MCP server" "${MCP_SERVER_ID:-}" MCP_SERVER_ID \
    dbtools mcp-server cascading-delete --mcp-server-id "${MCP_SERVER_ID:-}" \
    --wait-for-state SUCCEEDED --max-wait-seconds 120 --wait-interval-seconds 5; then
    clear_env_key MCP_SERVER_ENDPOINT
    clear_env_key MCP_BUILT_IN_SQL_TOOLSET_ID
  fi
fi

if [ "$DELETE_CONNECTION" = true ]; then
  delete_resource "Deleted Database Tools connection" "${DATABASE_TOOLS_CONNECTION_ID:-}" DATABASE_TOOLS_CONNECTION_ID \
    dbtools connection delete --connection-id "${DATABASE_TOOLS_CONNECTION_ID:-}" \
    --wait-for-state SUCCEEDED --max-wait-seconds 120 --wait-interval-seconds 5 || true
fi

if [ "$DELETE_BUCKET" = true ]; then
  if [ -z "${MCP_BUCKET_NAME:-}" ]; then
    echo "Skipping MCP Object Storage bucket; bucket name is not set."
    record_not_completed "Deleted MCP Object Storage bucket — bucket name is not set"
  elif namespace=$(oci_query os ns get --query data --raw-output 2>/dev/null); then
    if run_cleanup_cmd "Deleted MCP Object Storage bucket ${MCP_BUCKET_NAME}" \
      oci_query os bucket delete --bucket-name "$MCP_BUCKET_NAME" --namespace "$namespace" --empty --force; then
      clear_env_key MCP_BUCKET_NAME
    fi
  else
    echo "ERROR: Could not determine the Object Storage namespace."
    echo "  Next: Verify OCI credentials and Object Storage permission, then retry."
    record_not_completed "Deleted MCP Object Storage bucket ${MCP_BUCKET_NAME} — namespace unavailable"
    record_failure "Object Storage namespace lookup failed"
  fi
fi

if [ "$DELETE_LOCAL_ENV" = true ]; then
  if [ "${#CLEANUP_FAILURES[@]}" -gt 0 ]; then
    echo "Preserving local MCP environment file because one or more OCI resources still require attention."
    record_not_completed "Removed local MCP environment file — preserved for retry"
  else
    run_cleanup_cmd "Removed local MCP environment file" rm -f "$ENV_FILE" || true
  fi
fi

echo
echo "Cleanup summary"
if [ "${#CLEANUP_COMPLETED[@]}" -gt 0 ]; then
  echo "  Completed:"
  for item in "${CLEANUP_COMPLETED[@]}"; do echo "    - ${item}"; done
fi
if [ "${#CLEANUP_NOT_COMPLETED[@]}" -gt 0 ]; then
  echo "  Not completed:"
  for item in "${CLEANUP_NOT_COMPLETED[@]}"; do echo "    - ${item}"; done
fi
if [ "${#CLEANUP_FAILURES[@]}" -gt 0 ]; then
  echo "  Errors requiring attention:"
  for item in "${CLEANUP_FAILURES[@]}"; do echo "    - ${item}"; done
fi
echo "ADB OCI IAM prerequisite resources were not changed."
