#!/bin/bash
# Attach an ADB auto-login wallet to the existing DeepSec MCP Database Tools connection.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"
ACCEPT=false

usage() {
  cat <<'EOF'
Usage: ./09_configure_dbtools_mtls_wallet.sh [--accept]

Creates or reuses a Vault, key, cwallet.sso secret, dynamic group, and policy.
It attaches the SSO wallet to the existing Database Tools connection, then
runs the connection validation. It prints the plan before asking for CREATE.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --accept) ACCEPT=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ -f "$ENV_FILE" ] || { echo 'ERROR: .deep-sec-mcp.env not found.' >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
ADB_LAB_ENV_FILE="${ADB_LAB_ENV_FILE:-${SCRIPT_DIR}/../adb-oci-iam/.adb-oci-iam.env}"
MCP_WALLET_VAULT_NAME="${MCP_WALLET_VAULT_NAME:-deep-sec-mcp-wallet-vault}"
MCP_WALLET_KEY_NAME="${MCP_WALLET_KEY_NAME:-deep-sec-mcp-wallet-key}"
MCP_WALLET_SECRET_NAME="${MCP_WALLET_SECRET_NAME:-deep-sec-mcp-cwallet-sso}"
MCP_WALLET_DYNAMIC_GROUP_NAME="${MCP_WALLET_DYNAMIC_GROUP_NAME:-deep-sec-mcp-connection-rp}"
MCP_WALLET_POLICY_NAME="${MCP_WALLET_POLICY_NAME:-deep-sec-mcp-connection-wallet-read}"
if [ -z "${WALLET_DIR:-}" ] && [ -f "${ADB_LAB_ENV_FILE:-}" ]; then
  # shellcheck disable=SC1090
  source "$ADB_LAB_ENV_FILE"
fi
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib_oci_profile.sh"

oci_query() { oci_with_profile "$@"; }
need() { [ -n "${!1:-}" ] || { echo "ERROR: $1 is required." >&2; exit 1; }; }
clean() { case "${1:-}" in null|None) printf '' ;; *) printf '%s' "${1:-}" ;; esac; }
save_env() {
  local key="$1" value="$2"
  if grep -q "^export ${key}=" "$ENV_FILE"; then
    perl -pi -e "s|^export ${key}=.*|export ${key}=\\\"${value}\\\"|" "$ENV_FILE"
  else
    printf 'export %s="%s"\n' "$key" "$value" >> "$ENV_FILE"
  fi
}
lookup() {
  local command="$1"
  clean "$(eval "$command" 2>/dev/null || true)"
}

for command in oci base64 python3 perl; do
  command -v "$command" >/dev/null || { echo "ERROR: $command is required." >&2; exit 1; }
done
for name in TENANCY_OCID MCP_COMPARTMENT_OCID DATABASE_TOOLS_CONNECTION_ID; do need "$name"; done

WALLET_FILE="${WALLET_DIR:-}/cwallet.sso"
[ -r "$WALLET_FILE" ] || {
  echo "ERROR: cwallet.sso is not readable at $WALLET_FILE." >&2
  echo 'Set WALLET_DIR or ADB_LAB_ENV_FILE.' >&2
  exit 1
}

keystores=$(lookup "oci_query dbtools connection get --connection-id '$DATABASE_TOOLS_CONNECTION_ID' --query 'data.\"key-stores\"' --output json")

vault_id=$(clean "${MCP_WALLET_VAULT_ID:-}")
if [ -z "$vault_id" ]; then
  vault_id=$(lookup "oci_query kms management vault list --compartment-id '$MCP_COMPARTMENT_OCID' --all --query \"data[?\\\"display-name\\\"=='$MCP_WALLET_VAULT_NAME' && \\\"lifecycle-state\\\"=='ACTIVE'].id | [0]\" --raw-output")
fi
vault_endpoint=""
if [ -n "$vault_id" ]; then
  vault_endpoint=$(oci_query kms management vault get --vault-id "$vault_id" --query 'data."management-endpoint"' --raw-output)
fi
key_id=$(clean "${MCP_WALLET_KEY_ID:-}")
if [ -z "$key_id" ] && [ -n "$vault_endpoint" ]; then
  key_id=$(lookup "oci_query kms management key list --compartment-id '$MCP_COMPARTMENT_OCID' --endpoint '$vault_endpoint' --all --query \"data[?\\\"display-name\\\"=='$MCP_WALLET_KEY_NAME' && \\\"lifecycle-state\\\"=='ENABLED'].id | [0]\" --raw-output")
fi
secret_id=$(clean "${MCP_WALLET_SECRET_ID:-}")
if [ -z "$secret_id" ]; then
  secret_id=$(lookup "oci_query vault secret list --compartment-id '$MCP_COMPARTMENT_OCID' --all --query \"data[?\\\"secret-name\\\"=='$MCP_WALLET_SECRET_NAME' && \\\"lifecycle-state\\\"=='ACTIVE'].id | [0]\" --raw-output")
fi
wallet_update_needed=true
if [ -n "$keystores" ] && [ "$keystores" != '[]' ]; then
  if KEYSTORES="$keystores" SECRET_ID="$secret_id" python3 - <<'PY'
import json
import os
import sys

key_stores = json.loads(os.environ['KEYSTORES'])
secret_id = os.environ['SECRET_ID']
matches = any(
    item.get('key-store-type') == 'SSO'
    and (item.get('key-store-content') or {}).get('secret-id') == secret_id
    for item in key_stores
)
sys.exit(0 if matches else 1)
PY
  then
    wallet_update_needed=false
  else
    echo 'ERROR: Connection already has a different key-store configuration; refusing to replace it.' >&2
    exit 1
  fi
fi
dg_id=$(lookup "oci_query iam dynamic-group list --compartment-id '$TENANCY_OCID' --name '$MCP_WALLET_DYNAMIC_GROUP_NAME' --lifecycle-state ACTIVE --all --query 'data[0].id' --raw-output")
policy_id=$(lookup "oci_query iam policy list --compartment-id '$TENANCY_OCID' --name '$MCP_WALLET_POLICY_NAME' --lifecycle-state ACTIVE --all --query 'data[0].id' --raw-output")

rule="ALL {resource.type = 'databasetoolsconnection', resource.id = '$DATABASE_TOOLS_CONNECTION_ID'}"
policy_statements=$(MCP_GROUP="$MCP_WALLET_DYNAMIC_GROUP_NAME" MCP_COMPARTMENT="$MCP_COMPARTMENT_OCID" python3 - <<'PY'
import json
import os

group = os.environ['MCP_GROUP']
compartment = os.environ['MCP_COMPARTMENT']
print(json.dumps([
    f"Allow dynamic-group {group} to read autonomous-database-family in compartment id {compartment}",
    f"Allow dynamic-group {group} to read database-tools-family in compartment id {compartment}",
    f"Allow dynamic-group {group} to use database-tools-connections in compartment id {compartment}",
    f"Allow dynamic-group {group} to use database-connections in compartment id {compartment}",
    f"Allow dynamic-group {group} to read secret-family in compartment id {compartment}",
]))
PY
)
merged_policy_statements="$policy_statements"
policy_needs_update=false

if [ -n "$dg_id" ]; then
  actual_rule=$(oci_query iam dynamic-group get --dynamic-group-id "$dg_id" --query 'data."matching-rule"' --raw-output)
  [ "$actual_rule" = "$rule" ] || { echo "ERROR: Existing dynamic group rule differs: $actual_rule" >&2; exit 1; }
fi
if [ -n "$policy_id" ]; then
  policy_text=$(oci_query iam policy get --policy-id "$policy_id" --query 'data.statements' --output json)
  merged_policy_statements=$(POLICY_TEXT="$policy_text" REQUIRED_STATEMENTS="$policy_statements" python3 - <<'PY'
import json
import os

existing = json.loads(os.environ['POLICY_TEXT'])
required = json.loads(os.environ['REQUIRED_STATEMENTS'])
normal = lambda value: ' '.join(value.lower().split())
merged = list(existing)
known = {normal(value) for value in existing}
for value in required:
    if normal(value) not in known:
        merged.append(value)
print(json.dumps(merged))
PY
)
  policy_needs_update=$(POLICY_TEXT="$policy_text" REQUIRED_STATEMENTS="$policy_statements" python3 - <<'PY'
import json
import os

existing = json.loads(os.environ['POLICY_TEXT'])
required = json.loads(os.environ['REQUIRED_STATEMENTS'])
normal = lambda value: ' '.join(value.lower().split())
known = {normal(value) for value in existing}
print('true' if any(normal(value) not in known for value in required) else 'false')
PY
)
fi
policy_status=create
if [ -n "$policy_id" ]; then
  policy_status=reuse
fi
if [ "$policy_needs_update" = true ]; then
  policy_status=update
fi
vault_status=create; [ -n "$vault_id" ] && vault_status=reuse
key_status=create; [ -n "$key_id" ] && key_status=reuse
secret_status=create; [ -n "$secret_id" ] && secret_status=reuse
dg_status=create; [ -n "$dg_id" ] && dg_status=reuse

echo
echo '============================================================================'
echo '  Configure mTLS Wallet for DeepSec MCP Database Tools'
echo '============================================================================'
echo
echo "Connection = $DATABASE_TOOLS_CONNECTION_ID"
echo "Wallet     = $WALLET_FILE (content is not displayed)"
echo 'Planned OCI changes:'
printf '  Vault         %s (%s)\n' "$MCP_WALLET_VAULT_NAME" "$vault_status"
printf '  Key           %s (%s)\n' "$MCP_WALLET_KEY_NAME" "$key_status"
printf '  Secret        %s (%s)\n' "$MCP_WALLET_SECRET_NAME" "$secret_status"
printf '  Dynamic group %s (%s)\n' "$MCP_WALLET_DYNAMIC_GROUP_NAME" "$dg_status"
printf '  Policy        %s (%s)\n' "$MCP_WALLET_POLICY_NAME" "$policy_status"
echo "  Dynamic-group rule: $rule"
echo '  Required policy statements:'
printf '%s\n' "$policy_statements" | python3 -c 'import json,sys; [print("    " + x) for x in json.load(sys.stdin)]'
echo "  Connection update : $([ \"$wallet_update_needed\" = true ] && echo 'attach the SSO wallet secret' || echo 'already attached')"
echo
if [ "$ACCEPT" != true ]; then
  read -r -p 'Type CREATE to continue: ' answer
  [ "$answer" = CREATE ] || { echo 'No resources were changed.'; exit 0; }
fi

if [ -z "$vault_id" ]; then
  echo "Creating Vault: $MCP_WALLET_VAULT_NAME"
  vault_id=$(oci_query kms management vault create --compartment-id "$MCP_COMPARTMENT_OCID" --display-name "$MCP_WALLET_VAULT_NAME" --vault-type DEFAULT --wait-for-state ACTIVE --query 'data.id' --raw-output)
fi
save_env MCP_WALLET_VAULT_ID "$vault_id"
vault_endpoint=$(oci_query kms management vault get --vault-id "$vault_id" --query 'data."management-endpoint"' --raw-output)

if [ -z "$key_id" ]; then
  echo "Creating Vault key: $MCP_WALLET_KEY_NAME"
  key_id=$(oci_query kms management key create --compartment-id "$MCP_COMPARTMENT_OCID" --display-name "$MCP_WALLET_KEY_NAME" --key-shape '{"algorithm":"AES","length":32}' --endpoint "$vault_endpoint" --wait-for-state ENABLED --query 'data.id' --raw-output)
fi
save_env MCP_WALLET_KEY_ID "$key_id"

if [ -z "$secret_id" ]; then
  echo "Creating cwallet.sso secret: $MCP_WALLET_SECRET_NAME"
  wallet_b64=$(base64 -w 0 "$WALLET_FILE")
  secret_id=$(oci_query vault secret create-base64 --compartment-id "$MCP_COMPARTMENT_OCID" --vault-id "$vault_id" --key-id "$key_id" --secret-name "$MCP_WALLET_SECRET_NAME" --description 'Auto-login ADB wallet for the DeepSec MCP Database Tools connection.' --secret-content-name cwallet.sso --secret-content-content "$wallet_b64" --wait-for-state ACTIVE --query 'data.id' --raw-output)
  unset wallet_b64
fi
save_env MCP_WALLET_SECRET_ID "$secret_id"

if [ -z "$dg_id" ]; then
  echo "Creating dynamic group: $MCP_WALLET_DYNAMIC_GROUP_NAME"
  dg_id=$(oci_query iam dynamic-group create --compartment-id "$TENANCY_OCID" --name "$MCP_WALLET_DYNAMIC_GROUP_NAME" --description 'Resource principal for the DeepSec MCP Database Tools connection.' --matching-rule "$rule" --wait-for-state ACTIVE --query 'data.id' --raw-output)
fi
if [ -z "$policy_id" ]; then
  echo "Creating policy: $MCP_WALLET_POLICY_NAME"
  policy_id=$(oci_query iam policy create --compartment-id "$TENANCY_OCID" --name "$MCP_WALLET_POLICY_NAME" --description 'Allow the DeepSec MCP Database Tools connection to use its wallet and request database tokens.' --statements "$policy_statements" --wait-for-state ACTIVE --query 'data.id' --raw-output)
elif [ "$policy_needs_update" = true ]; then
  echo "Updating policy: $MCP_WALLET_POLICY_NAME (adding missing Database Tools token permissions)"
  oci_query iam policy update --policy-id "$policy_id" --statements "$merged_policy_statements" --force --wait-for-state ACTIVE >/dev/null
fi

keystores_json=$(SECRET_ID="$secret_id" python3 - <<'PY'
import json, os
print(json.dumps([{'keyStoreType': 'SSO', 'keyStoreContent': {'valueType': 'SECRETID', 'secretId': os.environ['SECRET_ID']}}]))
PY
)
if [ "$wallet_update_needed" = true ]; then
  echo 'Updating Database Tools connection with its SSO wallet secret (waits up to 60 seconds)'
  oci_query dbtools connection update-oracle-database --connection-id "$DATABASE_TOOLS_CONNECTION_ID" --key-stores "$keystores_json" --force --wait-for-state SUCCEEDED --max-wait-seconds 60 --wait-interval-seconds 5 >/dev/null
fi
echo
echo 'Wallet configuration complete. Validating the Database Tools connection:'
oci_query dbtools connection validate-oracle-database --connection-id "$DATABASE_TOOLS_CONNECTION_ID" --output json
