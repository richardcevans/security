#!/bin/bash
# Collect a redacted, read-only diagnostic bundle for OCI IAM direct logon.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "${SCRIPT_DIR}/lib_adb.sh"

usage() {
  cat <<'EOF'
Usage: ./diagnose_oci_iam_direct_login.sh [--user USER] [--output FILE]

Collects read-only OCI IAM direct-logon diagnostics. It never writes cloud
resources and never prints OAuth access tokens, client secrets, passwords, or
wallet key material. --user identifies the Identity Domain user to inspect;
when omitted, the script uses the subject of the current token when available.
EOF
}

target_user=''
output_file=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      target_user=$2
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      output_file=$2
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
require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: Required command not found: $1" >&2
    exit 1
  }
}
require_command oci
require_command python3
require_command sqlplus

diagnostic_dir="${SCRIPT_DIR}/.oci-iam-setup/diagnostics"
mkdir -p "$diagnostic_dir"
if [[ -z "$output_file" ]]; then
  output_file="${diagnostic_dir}/direct-login-$(date -u +%Y%m%dT%H%M%SZ).txt"
fi

token_file="${OCI_TOKEN_DIR:-$HOME/.oci/adb-oci-iam}/token"

token_subject() {
  [[ -f "$token_file" ]] || return 0
  TOKEN_FILE="$token_file" python3 - <<'PY'
import base64
import json
import os

try:
    token = open(os.environ["TOKEN_FILE"], encoding="utf-8").read().strip()
    encoded = token.split(".")[1]
    payload = json.loads(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))
    print(payload.get("user_name") or payload.get("sub") or "")
except Exception:
    pass
PY
}

if [[ -z "$target_user" ]]; then
  target_user=$(token_subject)
fi

run_section() {
  local heading=$1
  shift
  printf '\n============================================================================\n'
  printf '%s\n' "$heading"
  printf '%s\n' '----------------------------------------------------------------------------'
  if ! "$@"; then
    printf 'RESULT: command failed (continuing with remaining diagnostics).\n'
  fi
}

show_token_metadata() {
  if [[ ! -f "$token_file" ]]; then
    echo "Token file not found: ${token_file}"
    return 0
  fi

  TOKEN_FILE="$token_file" python3 - <<'PY'
import base64
import json
import os
from datetime import datetime, timezone

token = open(os.environ["TOKEN_FILE"], encoding="utf-8").read().strip()
parts = token.split(".")
if len(parts) != 3:
    raise SystemExit("Token file is not a JWT access token.")
encoded = parts[1] + "=" * (-len(parts[1]) % 4)
payload = json.loads(base64.urlsafe_b64decode(encoded).decode("utf-8"))
groups = payload.get("group") or payload.get("groups") or []
if isinstance(groups, str):
    groups = [groups]
audience = payload.get("aud")
if isinstance(audience, list):
    audience = ", ".join(str(value) for value in audience)
print("Token file   : " + os.environ["TOKEN_FILE"])
print("Token subject: " + str(payload.get("user_name") or payload.get("sub") or "(missing)"))
print("Token audience: " + str(audience or "(missing)"))
print("Token scope   : " + str(payload.get("scope") or "(missing)"))
print("Token issuer  : " + str(payload.get("iss") or "(missing)"))
print("Token groups  : " + (", ".join(str(group) for group in groups) or "(none)"))
if payload.get("exp"):
    print("Token expires : " + datetime.fromtimestamp(int(payload["exp"]), tz=timezone.utc).isoformat())
PY
}

show_wallet_settings() {
  echo "TNS_ADMIN=${TNS_ADMIN}"
  echo "ADB_SERVICE=${ADB_SERVICE}"
  echo "sqlnet.ora authentication/token settings:"
  grep -E -i '^(TOKEN_AUTH|TOKEN_LOCATION|SQLNET\.AUTHENTICATION_SERVICES|WALLET_LOCATION|SSL_SERVER_DN_MATCH)[[:space:]]*=' "${TNS_ADMIN}/sqlnet.ora" || true
  echo "Wallet required files:"
  for file in tnsnames.ora sqlnet.ora cwallet.sso ewallet.p12; do
    if [[ -f "${TNS_ADMIN}/${file}" ]]; then
      echo "  present: ${file}"
    else
      echo "  missing: ${file}"
    fi
  done
}

show_identity_user() {
  if [[ -z "$target_user" ]]; then
    echo "No target user supplied and no token subject could be determined."
    return 0
  fi
  echo "Identity Domain endpoint: ${OCI_DOMAIN_URL}"
  echo "Target user: ${target_user}"
  oci_with_profile identity-domains users list \
    --endpoint "$OCI_DOMAIN_URL" \
    --all \
    --filter "userName eq \"${target_user}\"" \
    --attributes 'id,userName,active,emails' \
    --output json
}

show_identity_groups() {
  echo "Target user: ${target_user:-'(not known)'}"
  for group_name in "${OCI_IAM_EMPLOYEE_GROUP:-EMPLOYEES}" "${OCI_IAM_MANAGER_GROUP:-MANAGERS}"; do
    local group_response group_id
    echo
    echo "Group: ${group_name}"
    if command -v timeout >/dev/null 2>&1; then
      group_response=$(timeout 30s oci "${OCI_PROFILE_ARGS[@]}" identity-domains groups list \
        --endpoint "$OCI_DOMAIN_URL" \
        --limit 10 \
        --filter "displayName eq \"${group_name}\"" \
        --attributes 'id,displayName' \
        --output json) || {
          echo "Unable to resolve ${group_name} within 30 seconds."
          continue
        }
    else
      group_response=$(oci_with_profile identity-domains groups list \
        --endpoint "$OCI_DOMAIN_URL" \
        --limit 10 \
        --filter "displayName eq \"${group_name}\"" \
        --attributes 'id,displayName' \
        --output json) || {
          echo "Unable to resolve ${group_name}."
          continue
        }
    fi

    printf '%s\n' "$group_response"
    group_id=$(GROUP_RESPONSE="$group_response" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["GROUP_RESPONSE"]).get("data") or {}
groups = data.get("Resources") or data.get("resources") or []
if groups:
    print(groups[0].get("id") or "")
PY
)
    if [[ -z "$group_id" ]]; then
      echo "No matching group found."
      continue
    fi

    echo "Membership record:"
    if command -v timeout >/dev/null 2>&1; then
      timeout 30s oci "${OCI_PROFILE_ARGS[@]}" identity-domains group get \
        --endpoint "$OCI_DOMAIN_URL" \
        --group-id "$group_id" \
        --attributes 'id,displayName,members' \
        --output json || echo "Unable to retrieve ${group_name} membership within 30 seconds."
    else
      oci_with_profile identity-domains group get \
        --endpoint "$OCI_DOMAIN_URL" \
        --group-id "$group_id" \
        --attributes 'id,displayName,members' \
        --output json || echo "Unable to retrieve ${group_name} membership."
    fi
  done
}

show_identity_app() {
  local label=$1
  local app_id=$2
  echo "${label}: ${app_id:-'(not set)'}"
  [[ -n "$app_id" ]] || return 0
  oci_with_profile identity-domains app get \
    --endpoint "$OCI_DOMAIN_URL" \
    --app-id "$app_id" \
    --attribute-sets all \
    --query 'data.{id:id,displayName:"display-name",active:active,clientType:"client-type",isOAuthClient:"is-o-auth-client",isOAuthResource:"is-o-auth-resource",audience:audience,scopes:scopes,allowedScopes:"allowed-scopes",allowedGrants:"allowed-grants",allowedOperations:"allowed-operations"}' \
    --output json
}

show_database_configuration() {
  admin_sqlplus <<'SQL'
set echo on
set pagesize 100
set linesize 220
set tab off
set trimspool on
col name format a38
col value format a140
SELECT name, value
FROM v$parameter
WHERE name IN ('identity_provider_type', 'identity_provider_oauth_config')
ORDER BY name;

col credential_name format a35
col username format a50
SELECT credential_name, username
FROM dba_credentials
WHERE credential_name = 'OCI_IAM_DOMAIN_DB_CRED$';

col data_role format a28
col mapped_to format a70
SELECT data_role, mapped_to
FROM dba_data_roles
WHERE data_role IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS')
ORDER BY data_role;

col grantee format a30
col granted_role format a30
SELECT grantee, granted_role
FROM dba_data_role_grants
WHERE grantee IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS')
   OR granted_role IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS')
ORDER BY grantee, granted_role;

col privilege format a30
SELECT grantee, privilege
FROM dba_sys_privs
WHERE grantee = 'DIRECT_LOGON_ROLE'
ORDER BY privilege;
SQL
}

{
  echo "OCI IAM direct-logon diagnostic bundle"
  echo "Generated UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "OCI CLI profile: ${OCI_PROFILE_SELECTED:-DEFAULT}"
  echo "OCI config file: ${OCI_CONFIG_FILE:-${OCI_CLI_CONFIG_FILE:-default}}"
  echo "This report excludes access tokens, client secrets, passwords, and wallet key material."
} | tee "$output_file"

exec > >(tee -a "$output_file") 2>&1

run_section '1. Current OAuth token metadata (redacted)' show_token_metadata
run_section '2. Local SQL*Plus and wallet configuration' show_wallet_settings
run_section '3. Identity Domain user' show_identity_user
run_section '4. Identity Domain groups and membership records' show_identity_groups
run_section '5. Database resource OAuth application' show_identity_app 'Database resource app' "${OCI_DB_APP_ID:-}"
run_section '6. Browser OAuth client application' show_identity_app 'Browser client app' "${OCI_CLIENT_APP_ID:-}"
run_section '7. ADB identity provider, credential identifier, and Data Roles' show_database_configuration

printf '\n============================================================================\n'
printf 'Diagnostic report written to: %s\n' "$output_file"
