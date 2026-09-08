#!/bin/bash
# Discover OCI values used by DeepSec MCP setup and write them to .deep-sec-mcp.env.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo -e "${RED}ERROR: .deep-sec-mcp.env not found. Run ./00_configure_lab_env.sh first.${NC}" >&2
  exit 1
fi
source "${SCRIPT_DIR}/lib_oci_profile.sh"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: $1 is required but is not available in PATH.${NC}" >&2
    exit 1
  fi
}

oci_query() {
  PYTHONWARNINGS="${PYTHONWARNINGS:+${PYTHONWARNINGS},}ignore::FutureWarning:urllib3.poolmanager" \
    oci_with_profile "$@"
}

append_or_replace_env() {
  local key="$1"
  local value="$2"
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    return 0
  fi

  if grep -q "^export ${key}=" "$ENV_FILE"; then
    perl -pi -e "s|^export ${key}=.*|export ${key}=\\\"${value}\\\"|" "$ENV_FILE"
  else
    printf 'export %s="%s"\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

clear_env_key() {
  local key="$1"
  if grep -q "^export ${key}=" "$ENV_FILE"; then
    perl -ni -e "print unless /^export ${key}=/" "$ENV_FILE"
  fi
}

show_found() {
  echo -e "${GREEN}found ${1}=${2}${NC}"
  append_or_replace_env "$1" "$2"
}

show_missing() {
  echo -e "${YELLOW}needs input: ${1}${NC}"
}

normalize_discovered_value() {
  local value="${1:-}"
  if [ "$value" = "null" ] || [ "$value" = "None" ]; then
    value=""
  fi
  printf '%s' "$value"
}

lookup_compartment_by_name() {
  oci_query iam compartment list \
    --include-root \
    --compartment-id-in-subtree true \
    --access-level ACCESSIBLE \
    --lifecycle-state ACTIVE \
    --all \
    --query "data[?name=='${MCP_COMPARTMENT_NAME}'].id | [0]" \
    --raw-output 2>/dev/null || true
}

lookup_domain_by_name() {
  oci_query iam domain list \
    --compartment-id "$TENANCY_OCID" \
    --lifecycle-state ACTIVE \
    --all \
    --query "data[?\"display-name\"=='${MCP_IDENTITY_DOMAIN_NAME}' || name=='${MCP_IDENTITY_DOMAIN_NAME}'].id | [0]" \
    --raw-output 2>/dev/null || true
}

lookup_domain_by_url() {
  local domains
  domains=$(oci_query iam domain list \
    --compartment-id "$TENANCY_OCID" \
    --lifecycle-state ACTIVE \
    --all \
    --output json || true)
  [ -z "$domains" ] && return

  printf '%s' "$domains" | python3 -c '
import json
import sys
from urllib.parse import urlparse

def host(value):
    try:
        return (urlparse(value).hostname or "").lower()
    except ValueError:
        return ""

target = host(sys.argv[1])
try:
    data = json.load(sys.stdin).get("data") or []
except (json.JSONDecodeError, AttributeError):
    raise SystemExit(0)

matches = [
    item.get("id", "")
    for item in data
    if target and target in {host(item.get("url", "")), host(item.get("home-region-url", ""))}
]
if len(matches) == 1:
    print(matches[0])
' "$OCI_DOMAIN_URL"
}

lookup_single_domain() {
  local count
  count=$(oci_query iam domain list \
    --compartment-id "$TENANCY_OCID" \
    --lifecycle-state ACTIVE \
    --all \
    --query 'length(data)' \
    --raw-output 2>/dev/null || true)

  if [ "$count" = "1" ]; then
    oci_query iam domain list \
      --compartment-id "$TENANCY_OCID" \
      --lifecycle-state ACTIVE \
      --all \
      --query 'data[0].id' \
      --raw-output 2>/dev/null || true
  fi
}

lookup_connection_id() {
  local connection_id
  connection_id=$(oci_query dbtools connection list \
    --compartment-id "$MCP_COMPARTMENT_OCID" \
    --type ORACLE_DATABASE \
    --all \
    --query "data[?\"display-name\"=='${DATABASE_TOOLS_CONNECTION_NAME}' && \"lifecycle-state\"=='ACTIVE' && \"authentication-type\"=='${DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE}' && \"runtime-identity\"=='${DATABASE_TOOLS_RUNTIME_IDENTITY}'].id | [0]" \
    --raw-output 2>/dev/null || true)
  if [ -z "$connection_id" ] || [ "$connection_id" = "null" ]; then
    connection_id=$(oci_query dbtools connection list \
      --compartment-id "$MCP_COMPARTMENT_OCID" \
      --type ORACLE_DATABASE \
      --all \
      --query "data[?\"related-resource-identifier\"=='${ADB_OCID}' && \"lifecycle-state\"=='ACTIVE' && \"authentication-type\"=='${DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE}' && \"runtime-identity\"=='${DATABASE_TOOLS_RUNTIME_IDENTITY}'].id | [0]" \
      --raw-output 2>/dev/null || true)
  fi
  printf '%s' "$connection_id"
}

get_connection_state() {
  local connection_id="$1"
  [ -z "$connection_id" ] && return

  oci_query dbtools connection get \
    --connection-id "$connection_id" \
    --query 'data."lifecycle-state"' \
    --raw-output 2>/dev/null || true
}

get_connection_authentication_type() {
  local connection_id="$1"
  [ -z "$connection_id" ] && return

  oci_query dbtools connection get \
    --connection-id "$connection_id" \
    --query 'data."authentication-type"' \
    --raw-output 2>/dev/null || true
}

get_connection_runtime_identity() {
  local connection_id="$1"
  [ -z "$connection_id" ] && return

  oci_query dbtools connection get \
    --connection-id "$connection_id" \
    --query 'data."runtime-identity"' \
    --raw-output 2>/dev/null || true
}

lookup_mcp_server_id() {
  local server_id
  server_id=$(oci_query dbtools mcp-server list \
    --compartment-id "$MCP_COMPARTMENT_OCID" \
    --all \
    --query "data[?\"display-name\"=='${MCP_SERVER_NAME}'].id | [0]" \
    --raw-output 2>/dev/null || true)
  if { [ -z "$server_id" ] || [ "$server_id" = "null" ]; } && [ -n "${DATABASE_TOOLS_CONNECTION_ID:-}" ]; then
    server_id=$(oci_query dbtools mcp-server list --compartment-id "$MCP_COMPARTMENT_OCID" --all \
      --query "data[?\"database-tools-connection-id\"=='${DATABASE_TOOLS_CONNECTION_ID}'].id | [0]" --raw-output 2>/dev/null || true)
  fi
  printf '%s' "$server_id"
}

lookup_toolset_id() {
  local toolset_id
  toolset_id=$(oci_query dbtools mcp-toolset list \
    --compartment-id "$MCP_COMPARTMENT_OCID" \
    --type BUILT_IN_SQL_TOOLS \
    --all \
    --query "data[?\"display-name\"=='${MCP_BUILT_IN_SQL_TOOLSET_NAME}'].id | [0]" \
    --raw-output 2>/dev/null || true)
  if { [ -z "$toolset_id" ] || [ "$toolset_id" = "null" ]; } && [ -n "${MCP_SERVER_ID:-}" ]; then
    toolset_id=$(oci_query dbtools mcp-toolset list --compartment-id "$MCP_COMPARTMENT_OCID" --type BUILT_IN_SQL_TOOLS --all \
      --query "data[?\"mcp-server-id\"=='${MCP_SERVER_ID}'].id | [0]" --raw-output 2>/dev/null || true)
  fi
  printf '%s' "$toolset_id"
}

lookup_adb_connection_string() {
  [ -z "${ADB_OCID:-}" ] && return
  local response
  response=$(oci_query db autonomous-database get --autonomous-database-id "$ADB_OCID" 2>/dev/null || true)
  [ -z "$response" ] && return

  ADB_RESPONSE="$response" ADB_SERVICE_ALIAS="${ADB_SERVICE:-}" python3 - <<'PY'
import json
import os

try:
    raw = json.loads(os.environ.get("ADB_RESPONSE", "{}"))
except Exception:
    raise SystemExit(0)

data = raw.get("data") or {}
conn = data.get("connection-strings") or data.get("connectionStrings") or {}
all_conn = conn.get("all-connection-strings") or conn.get("allConnectionStrings") or {}
service_alias = os.environ.get("ADB_SERVICE_ALIAS", "").lower()
service_type = service_alias.rsplit("_", 1)[-1].upper() if "_" in service_alias else "LOW"

for key in (service_type, service_type.lower(), "LOW", "low"):
    value = all_conn.get(key)
    if value:
        print(value)
        raise SystemExit(0)

profiles = conn.get("profiles") or []
for profile in profiles:
    if not isinstance(profile, dict):
        continue
    name = str(profile.get("display-name") or profile.get("displayName") or profile.get("value") or "").lower()
    value = profile.get("value") or profile.get("connection-string") or profile.get("connectionString")
    if value and (not service_alias or service_alias in name or "low" in name):
        print(value)
        break
PY
}

extract_tns_descriptor() {
  [ -z "${WALLET_DIR:-}" ] && return
  [ -z "${ADB_SERVICE:-}" ] && return
  [ ! -f "${WALLET_DIR}/tnsnames.ora" ] && return

  TNS_FILE="${WALLET_DIR}/tnsnames.ora" SERVICE_ALIAS="${ADB_SERVICE}" python3 - <<'PY'
import os
import re

path = os.environ["TNS_FILE"]
alias = os.environ["SERVICE_ALIAS"].lower()

try:
    lines = open(path, encoding="utf-8").read().splitlines()
except OSError:
    raise SystemExit(0)

capturing = False
parts = []
balance = 0

for line in lines:
    if not capturing:
        match = re.match(r"\s*([A-Za-z0-9_.-]+)\s*=\s*(.*)$", line)
        if not match or match.group(1).lower() != alias:
            continue
        capturing = True
        text = match.group(2).strip()
    else:
        text = line.strip()

    if text:
        parts.append(text)
        balance += text.count("(") - text.count(")")

    if capturing and parts and balance <= 0:
        break

descriptor = " ".join(parts).strip()
if descriptor:
    print(re.sub(r"\s+", "", descriptor))
PY
}

require_cmd oci
require_cmd perl
require_cmd python3

DATABASE_TOOLS_CONNECTION_NAME="${DATABASE_TOOLS_CONNECTION_NAME:-deep-sec-mcp-connection}"
DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE="${DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE:-TOKEN}"
DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE=$(printf '%s' "$DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE" | tr '[:lower:]' '[:upper:]')
if [ "$DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE" = "TOKEN" ]; then
  DATABASE_TOOLS_RUNTIME_IDENTITY="${DATABASE_TOOLS_RUNTIME_IDENTITY:-RESOURCE_PRINCIPAL}"
  MCP_RUNTIME_IDENTITY="${MCP_RUNTIME_IDENTITY:-AUTHENTICATED_PRINCIPAL}"
else
  DATABASE_TOOLS_RUNTIME_IDENTITY="${DATABASE_TOOLS_RUNTIME_IDENTITY:-AUTHENTICATED_PRINCIPAL}"
  MCP_RUNTIME_IDENTITY="${MCP_RUNTIME_IDENTITY:-RESOURCE_PRINCIPAL}"
fi
MCP_SERVER_NAME="${MCP_SERVER_NAME:-deep-sec-mcp}"
MCP_BUILT_IN_SQL_TOOLSET_NAME="${MCP_BUILT_IN_SQL_TOOLSET_NAME:-deep-sec-mcp-built-in-sql-tools}"

if [ "$DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE" = "TOKEN" ]; then
  if [ "$MCP_RUNTIME_IDENTITY" != "AUTHENTICATED_PRINCIPAL" ]; then
    MCP_RUNTIME_IDENTITY="AUTHENTICATED_PRINCIPAL"
    show_found MCP_RUNTIME_IDENTITY "$MCP_RUNTIME_IDENTITY"
  fi

  if [ "$DATABASE_TOOLS_RUNTIME_IDENTITY" != "RESOURCE_PRINCIPAL" ]; then
    DATABASE_TOOLS_RUNTIME_IDENTITY="RESOURCE_PRINCIPAL"
    show_found DATABASE_TOOLS_RUNTIME_IDENTITY "$DATABASE_TOOLS_RUNTIME_IDENTITY"
  fi
fi

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Discover DeepSec MCP OCI Inputs                                       ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

if [ -z "${NAMESPACE:-}" ]; then
  NAMESPACE=$(oci_query os ns get --raw-output --query data || true)
fi
NAMESPACE=$(normalize_discovered_value "${NAMESPACE:-}")
if [ -n "${NAMESPACE:-}" ] && [ "$NAMESPACE" != "null" ]; then
  show_found NAMESPACE "$NAMESPACE"
else
  show_missing NAMESPACE
fi

if [ -z "${TENANCY_OCID:-}" ]; then
  TENANCY_OCID=$(oci_query iam compartment list \
    --include-root \
    --all \
    --query "data[?contains(id, 'ocid1.tenancy')].id | [0]" \
    --raw-output 2>/dev/null || true)
fi
TENANCY_OCID=$(normalize_discovered_value "${TENANCY_OCID:-}")
if [ -n "${TENANCY_OCID:-}" ] && [ "$TENANCY_OCID" != "null" ]; then
  show_found TENANCY_OCID "$TENANCY_OCID"
else
  show_missing TENANCY_OCID
fi

if [ -z "${MCP_COMPARTMENT_OCID:-}" ] && [ -n "${ADB_OCID:-}" ]; then
  MCP_COMPARTMENT_OCID=$(oci_query db autonomous-database get \
    --autonomous-database-id "$ADB_OCID" \
    --query 'data."compartment-id"' \
    --raw-output 2>/dev/null || true)
fi
MCP_COMPARTMENT_OCID="${MCP_COMPARTMENT_OCID:-${ROOT_COMP_ID:-}}"
MCP_COMPARTMENT_OCID=$(normalize_discovered_value "${MCP_COMPARTMENT_OCID:-}")

if [ -z "${MCP_COMPARTMENT_OCID:-}" ] && [ -n "${MCP_COMPARTMENT_NAME:-}" ]; then
  MCP_COMPARTMENT_OCID=$(lookup_compartment_by_name)
fi

if [ -n "${MCP_COMPARTMENT_OCID:-}" ] && [ "$MCP_COMPARTMENT_OCID" != "null" ]; then
  show_found MCP_COMPARTMENT_OCID "$MCP_COMPARTMENT_OCID"
else
  show_missing MCP_COMPARTMENT_OCID
  echo "  Set MCP_COMPARTMENT_NAME for discovery or MCP_COMPARTMENT_OCID directly."
fi

if [ -z "${MCP_IDENTITY_DOMAIN_OCID:-}" ] && [ -n "${TENANCY_OCID:-}" ] && [ "$TENANCY_OCID" != "null" ]; then
  if [ -n "${MCP_IDENTITY_DOMAIN_NAME:-}" ]; then
    MCP_IDENTITY_DOMAIN_OCID=$(lookup_domain_by_name)
  fi

  if [ -z "${MCP_IDENTITY_DOMAIN_OCID:-}" ] && [ -n "${OCI_DOMAIN_URL:-}" ]; then
    MCP_IDENTITY_DOMAIN_OCID=$(lookup_domain_by_url)
  fi

  if [ -z "${MCP_IDENTITY_DOMAIN_OCID:-}" ]; then
    MCP_IDENTITY_DOMAIN_OCID=$(lookup_single_domain)
  fi
fi
MCP_IDENTITY_DOMAIN_OCID=$(normalize_discovered_value "${MCP_IDENTITY_DOMAIN_OCID:-}")

if [ -n "${MCP_IDENTITY_DOMAIN_OCID:-}" ] && [ "$MCP_IDENTITY_DOMAIN_OCID" != "null" ]; then
  show_found MCP_IDENTITY_DOMAIN_OCID "$MCP_IDENTITY_DOMAIN_OCID"
else
  show_missing MCP_IDENTITY_DOMAIN_OCID
  echo "  Set MCP_IDENTITY_DOMAIN_NAME, OCI_DOMAIN_URL, or MCP_IDENTITY_DOMAIN_OCID."
fi

if [ -n "${DATABASE_TOOLS_CONNECTION_ID:-}" ]; then
  DATABASE_TOOLS_CONNECTION_STATE=$(normalize_discovered_value "$(get_connection_state "$DATABASE_TOOLS_CONNECTION_ID")")
  if [ "$DATABASE_TOOLS_CONNECTION_STATE" != "ACTIVE" ]; then
    echo -e "${YELLOW}ignoring DATABASE_TOOLS_CONNECTION_ID=${DATABASE_TOOLS_CONNECTION_ID}; lifecycle state is ${DATABASE_TOOLS_CONNECTION_STATE:-unknown}${NC}"
    clear_env_key DATABASE_TOOLS_CONNECTION_ID
    DATABASE_TOOLS_CONNECTION_ID=""
  else
    DATABASE_TOOLS_CONNECTION_AUTH=$(normalize_discovered_value "$(get_connection_authentication_type "$DATABASE_TOOLS_CONNECTION_ID")")
    DATABASE_TOOLS_CONNECTION_RUNTIME=$(normalize_discovered_value "$(get_connection_runtime_identity "$DATABASE_TOOLS_CONNECTION_ID")")
    if [ "$DATABASE_TOOLS_CONNECTION_AUTH" != "$DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE" ] || [ "$DATABASE_TOOLS_CONNECTION_RUNTIME" != "$DATABASE_TOOLS_RUNTIME_IDENTITY" ]; then
      echo -e "${YELLOW}ignoring DATABASE_TOOLS_CONNECTION_ID=${DATABASE_TOOLS_CONNECTION_ID}; auth/runtime is ${DATABASE_TOOLS_CONNECTION_AUTH:-unknown}/${DATABASE_TOOLS_CONNECTION_RUNTIME:-unknown}${NC}"
      clear_env_key DATABASE_TOOLS_CONNECTION_ID
      DATABASE_TOOLS_CONNECTION_ID=""
    fi
  fi
fi

if [ -z "${DATABASE_TOOLS_CONNECTION_ID:-}" ] && [ -n "${MCP_COMPARTMENT_OCID:-}" ] && [ "$MCP_COMPARTMENT_OCID" != "null" ]; then
  DATABASE_TOOLS_CONNECTION_ID=$(lookup_connection_id)
fi
if [ -n "${DATABASE_TOOLS_CONNECTION_ID:-}" ] && [ "$DATABASE_TOOLS_CONNECTION_ID" != "null" ]; then
  show_found DATABASE_TOOLS_CONNECTION_ID "$DATABASE_TOOLS_CONNECTION_ID"
else
  echo -e "${YELLOW}not found: DATABASE_TOOLS_CONNECTION_ID for display name ${DATABASE_TOOLS_CONNECTION_NAME}${NC}"
fi

if [ -z "${MCP_SERVER_ID:-}" ] && [ -n "${MCP_COMPARTMENT_OCID:-}" ] && [ "$MCP_COMPARTMENT_OCID" != "null" ]; then
  MCP_SERVER_ID=$(lookup_mcp_server_id)
fi
if [ -n "${MCP_SERVER_ID:-}" ] && [ "$MCP_SERVER_ID" != "null" ]; then
  show_found MCP_SERVER_ID "$MCP_SERVER_ID"
else
  echo -e "${YELLOW}not found: MCP_SERVER_ID for display name ${MCP_SERVER_NAME}${NC}"
fi

if [ -z "${MCP_BUILT_IN_SQL_TOOLSET_ID:-}" ] && [ -n "${MCP_COMPARTMENT_OCID:-}" ] && [ "$MCP_COMPARTMENT_OCID" != "null" ]; then
  MCP_BUILT_IN_SQL_TOOLSET_ID=$(lookup_toolset_id)
fi
if [ -n "${MCP_BUILT_IN_SQL_TOOLSET_ID:-}" ] && [ "$MCP_BUILT_IN_SQL_TOOLSET_ID" != "null" ]; then
  show_found MCP_BUILT_IN_SQL_TOOLSET_ID "$MCP_BUILT_IN_SQL_TOOLSET_ID"
else
  echo -e "${YELLOW}not found: MCP_BUILT_IN_SQL_TOOLSET_ID for display name ${MCP_BUILT_IN_SQL_TOOLSET_NAME}${NC}"
fi

if [ -z "${MCP_BUCKET_NAME:-}" ]; then
  MCP_BUCKET_NAME="deep-sec-mcp-${USER:-user}-mcp"
  show_found MCP_BUCKET_NAME "$MCP_BUCKET_NAME"
else
  show_found MCP_BUCKET_NAME "$MCP_BUCKET_NAME"
fi

echo
if [ -z "${DATABASE_TOOLS_CONNECTION_STRING:-}" ]; then
  DATABASE_TOOLS_CONNECTION_STRING=$(lookup_adb_connection_string)
fi
if [ -z "${DATABASE_TOOLS_CONNECTION_STRING:-}" ]; then
  DATABASE_TOOLS_CONNECTION_STRING=$(extract_tns_descriptor)
fi
DATABASE_TOOLS_CONNECTION_STRING=$(normalize_discovered_value "${DATABASE_TOOLS_CONNECTION_STRING:-}")
if [ -n "${DATABASE_TOOLS_CONNECTION_STRING:-}" ]; then
  show_found DATABASE_TOOLS_CONNECTION_STRING "$DATABASE_TOOLS_CONNECTION_STRING"
else
  show_missing DATABASE_TOOLS_CONNECTION_STRING
  echo "  OCI does not always expose one canonical connect string for every database shape."
  echo "  Set the Easy Connect string for the service you want Database Tools to use."
fi

echo
echo -e "${GREEN}Discovery completed. Review .deep-sec-mcp.env, then run:${NC}"
echo "  source ./.deep-sec-mcp.env"
echo "  ./create_mcp_server_tools.sh"
echo
