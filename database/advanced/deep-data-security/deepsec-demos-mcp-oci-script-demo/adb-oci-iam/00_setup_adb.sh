#!/bin/bash
# Create or reuse an Autonomous AI Database Serverless instance and wallet.
# Intended to run from OCI Cloud Shell.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.adb-oci-iam.env"
INSTANCE_FILE="${SCRIPT_DIR}/.adb-oci-iam.instance"
WORK_DIR="${SCRIPT_DIR}/.oci-iam-setup"
APP_ENV_FILE="${APP_ENV_FILE:-$(cd "${SCRIPT_DIR}/.." && pwd)/.env}"
source "${SCRIPT_DIR}/lib_lab_instance.sh"
source "${SCRIPT_DIR}/lib_oci_profile.sh"

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  echo "ERROR: This lab requires Bash 4.x or later." >&2
  exit 1
fi

usage() {
  cat <<'EOF'
Usage:
  ./00_setup_adb.sh [compartment-name|compartment-ocid|root]

Compartment selection:
  ROOT_COMP_ID       Direct compartment OCID. Highest priority.
  OCI_COMPARTMENT    Compartment name, compartment OCID, or root.
  argument           Same as OCI_COMPARTMENT.

If none is provided, the script uses the root compartment.

Existing database mode:
  EXISTING_DB_DSN     SQL*Plus/Python connect string for an existing ADB.
  WALLET_DIR          Directory containing that ADB wallet.
  ADMIN_PWD           ADMIN password for that ADB.

When EXISTING_DB_DSN is set, the script creates/reuses IAM apps and demo
users, but skips Autonomous Database create/reuse and wallet download.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

show_cmd() {
  printf '  $'
  printf ' %q' "$@"
  printf '\n'
}

require_non_production_acknowledgement() {
  echo
  echo -e "${YELLOW}Production safety acknowledgement required.${NC}"
  echo -e "${YELLOW}This lab can create or modify OCI IAM OAuth apps, groups, demo users, and group memberships.${NC}"
  echo -e "${YELLOW}Run it only in an isolated demo, sandbox, or non-production tenancy/domain.${NC}"
  echo
  echo -e "${CYAN}Target tenancy      = ${TENANCY_OCID}${NC}"
  echo -e "${CYAN}Target compartment  = ${ROOT_COMP_ID}${NC}"
  echo -e "${CYAN}Target IAM domain   = ${OCI_DOMAIN_URL}${NC}"
  echo -e "${CYAN}IAM groups          = ${OCI_IAM_EMPLOYEE_GROUP}, ${OCI_IAM_MANAGER_GROUP}${NC}"
  if [ "$CREATE_DEMO_USERS" = "1" ]; then
    echo -e "${CYAN}Demo users          = ${MARVIN_USERNAME}, ${EMMA_USERNAME}${NC}"
  else
    echo -e "${CYAN}Demo users          = skipped because CREATE_DEMO_USERS=0${NC}"
  fi
  echo
  printf 'Type NON-PRODUCTION to confirm this is not a production environment: '

  local answer
  if ! IFS= read -r answer; then
    echo
    echo -e "${RED}ERROR: Could not read acknowledgement. Aborting before OCI IAM changes.${NC}" >&2
    exit 1
  fi

  if [ "$answer" != "NON-PRODUCTION" ]; then
    echo -e "${RED}ERROR: Acknowledgement not provided. Aborting before OCI IAM changes.${NC}" >&2
    exit 1
  fi
}

ADB_OCI_IAM_LAB_INSTANCE_ID=$(make_lab_instance_id "dbsec-lab-machine" "$INSTANCE_FILE" "ADB_OCI_IAM_LAB_INSTANCE_ID")
export ADB_OCI_IAM_LAB_INSTANCE_ID
ADB_OCI_IAM_LAB_INSTANCE_SHORT=$(short_lab_instance_id "$ADB_OCI_IAM_LAB_INSTANCE_ID" 6)
export ADB_OCI_IAM_LAB_INSTANCE_SHORT

export DB_NAME="${DB_NAME:-deepsec1${ADB_OCI_IAM_LAB_INSTANCE_SHORT}}"
export DB_NAME_REUSE_PREFIX="${DB_NAME_REUSE_PREFIX:-deepsec1}"
export DB_DISPLAY_NAME="${DB_DISPLAY_NAME:-${DB_NAME}}"
if [ "$DB_NAME" != "deepsec1" ] && [ "$DB_DISPLAY_NAME" = "deepsec1" ]; then
  DB_DISPLAY_NAME="$DB_NAME"
fi
export DB_DISPLAY_NAME
export DB_VERSION="${DB_VERSION:-26ai}"
export ADB_IS_FREE_TIER="${ADB_IS_FREE_TIER:-true}"
ADB_IS_FREE_TIER=$(printf '%s' "$ADB_IS_FREE_TIER" | tr '[:upper:]' '[:lower:]')
if [ "$ADB_IS_FREE_TIER" != "true" ] && [ "$ADB_IS_FREE_TIER" != "false" ]; then
  echo -e "${RED}ERROR: ADB_IS_FREE_TIER must be true or false.${NC}" >&2
  exit 1
fi
export ADB_IS_FREE_TIER
export ADB_LICENSE_MODEL="${ADB_LICENSE_MODEL:-BRING_YOUR_OWN_LICENSE}"
ADB_LICENSE_MODEL=$(printf '%s' "$ADB_LICENSE_MODEL" | tr '[:lower:]' '[:upper:]')
if [ "$ADB_LICENSE_MODEL" != "BRING_YOUR_OWN_LICENSE" ] && [ "$ADB_LICENSE_MODEL" != "LICENSE_INCLUDED" ]; then
  echo -e "${RED}ERROR: ADB_LICENSE_MODEL must be BRING_YOUR_OWN_LICENSE or LICENSE_INCLUDED.${NC}" >&2
  exit 1
fi
export ADB_LICENSE_MODEL
export ADB_MAINTENANCE_SCHEDULE_TYPE="${ADB_MAINTENANCE_SCHEDULE_TYPE:-}"
if [ -n "$ADB_MAINTENANCE_SCHEDULE_TYPE" ]; then
  ADB_MAINTENANCE_SCHEDULE_TYPE=$(printf '%s' "$ADB_MAINTENANCE_SCHEDULE_TYPE" | tr '[:lower:]' '[:upper:]')
  if [ "$ADB_MAINTENANCE_SCHEDULE_TYPE" != "EARLY" ] && [ "$ADB_MAINTENANCE_SCHEDULE_TYPE" != "REGULAR" ]; then
    echo -e "${RED}ERROR: ADB_MAINTENANCE_SCHEDULE_TYPE must be EARLY or REGULAR.${NC}" >&2
    exit 1
  fi
  export ADB_MAINTENANCE_SCHEDULE_TYPE
fi
export ADMIN_PWD="${ADMIN_PWD:-Oracle123+Oracle123+}"
export WALLET_PWD="${WALLET_PWD:-Oracle123+}"
export WALLET_DIR="${WALLET_DIR:-$HOME/adb_wallet/${DB_NAME}}"
export ADB_SERVICE="${ADB_SERVICE:-${DB_NAME}_low}"
export EXISTING_DB_DSN="${EXISTING_DB_DSN:-}"
export EXISTING_ADB_OCID="${EXISTING_ADB_OCID:-}"
if [ -n "$EXISTING_DB_DSN" ]; then
  export ADB_CREATE_MODE="existing"
else
  export ADB_CREATE_MODE="${ADB_CREATE_MODE:-create}"
fi
if [ "$ADB_CREATE_MODE" != "create" ] && [ "$ADB_CREATE_MODE" != "existing" ]; then
  echo -e "${RED}ERROR: ADB_CREATE_MODE must be create or existing.${NC}" >&2
  exit 1
fi
if [ "$ADB_CREATE_MODE" = "existing" ] && [ -z "$EXISTING_DB_DSN" ]; then
  echo -e "${RED}ERROR: ADB_CREATE_MODE=existing requires EXISTING_DB_DSN.${NC}" >&2
  exit 1
fi
if [ "$ADB_CREATE_MODE" = "existing" ]; then
  ADB_SERVICE="$EXISTING_DB_DSN"
  export ADB_SERVICE
fi
export APP_DB_USER="${APP_DB_USER:-db_usr}"
export APP_DB_PASSWORD="${APP_DB_PASSWORD:-Oracle123+App123+}"
export OCI_IAM_EMPLOYEE_GROUP="${OCI_IAM_EMPLOYEE_GROUP:-EMPLOYEES}"
export OCI_IAM_MANAGER_GROUP="${OCI_IAM_MANAGER_GROUP:-MANAGERS}"
export OCI_USERNAME_DOMAIN="${OCI_USERNAME_DOMAIN:-}"
export MARVIN_USERNAME="${MARVIN_USERNAME:-marvin}"
export EMMA_USERNAME="${EMMA_USERNAME:-emma}"
export CREATE_DEMO_USERS="${CREATE_DEMO_USERS:-1}"
export TENANCY_OCID="${TENANCY_OCID:-${OCI_TENANCY:-}}"
export OCI_COMPARTMENT="${1:-${OCI_COMPARTMENT:-root}}"
export OCI_DOMAIN_NAME="${OCI_DOMAIN_NAME:-Default}"
legacy_oci_db_app_name="${DB_NAME} ADB OCI IAM DB Resource"
legacy_oci_client_app_name="${DB_NAME} ADB OCI IAM Public Client"
if [ -z "${OCI_DB_APP_NAME:-}" ] || [ "$OCI_DB_APP_NAME" = "$legacy_oci_db_app_name" ] || [ "$OCI_DB_APP_NAME" = "ADB OCI IAM DB Resource" ]; then
  OCI_DB_APP_NAME="${DB_NAME} ADB OCI IAM DB Resource - ${ADB_OCI_IAM_LAB_INSTANCE_ID}"
fi
if [ -z "${OCI_CLIENT_APP_NAME:-}" ] || [ "$OCI_CLIENT_APP_NAME" = "$legacy_oci_client_app_name" ] || [ "$OCI_CLIENT_APP_NAME" = "ADB OCI IAM Public Client" ]; then
  OCI_CLIENT_APP_NAME="${DB_NAME} Confidential Login Client - ${ADB_OCI_IAM_LAB_INSTANCE_ID}"
fi
if [ -z "${OCI_MIDTIER_APP_NAME:-}" ] || [ "$OCI_MIDTIER_APP_NAME" = "ADB OCI IAM Midtier App" ]; then
  OCI_MIDTIER_APP_NAME="${DB_NAME} HR Midtier App - ${ADB_OCI_IAM_LAB_INSTANCE_ID}"
fi
export OCI_DB_APP_NAME
export OCI_CLIENT_APP_NAME
export OCI_MIDTIER_APP_NAME
if [ -z "${OCI_DB_AUDIENCE:-}" ] || [ "$OCI_DB_AUDIENCE" = "OracleDB" ] || [ "$OCI_DB_AUDIENCE" = "${DB_NAME}OracleDB" ]; then
  OCI_DB_AUDIENCE="${DB_NAME}OracleDB${ADB_OCI_IAM_LAB_INSTANCE_SHORT}"
fi
if [ -z "${OCI_DB_SCOPE_VALUE:-}" ] || [ "$OCI_DB_SCOPE_VALUE" = "DB_ACCESS_SCOPE" ] || [ "$OCI_DB_SCOPE_VALUE" = "${DB_NAME}_DB_ACCESS_SCOPE" ]; then
  OCI_DB_SCOPE_VALUE="${DB_NAME}_DB_ACCESS_SCOPE_${ADB_OCI_IAM_LAB_INSTANCE_SHORT}"
fi
export OCI_DB_AUDIENCE
export OCI_DB_SCOPE_VALUE
export OCI_DB_SCOPE="${OCI_DB_AUDIENCE}${OCI_DB_SCOPE_VALUE}"
if [ -z "${OCI_MIDTIER_AUDIENCE:-}" ]; then
  OCI_MIDTIER_AUDIENCE="${DB_NAME}HR${ADB_OCI_IAM_LAB_INSTANCE_SHORT}"
fi
if [ -z "${OCI_MIDTIER_SCOPE_VALUE:-}" ] || [ "$OCI_MIDTIER_SCOPE_VALUE" = "APP_ACCESS_SCOPE" ]; then
  OCI_MIDTIER_SCOPE_VALUE="${DB_NAME}_AGENT_ACCESS_${ADB_OCI_IAM_LAB_INSTANCE_SHORT}"
fi
export OCI_MIDTIER_AUDIENCE
export OCI_MIDTIER_SCOPE_VALUE
export OCI_MIDTIER_SCOPE="${OCI_MIDTIER_AUDIENCE}${OCI_MIDTIER_SCOPE_VALUE}"
export OCI_MIDTIER_APP_ROLE_NAME="${OCI_MIDTIER_APP_ROLE_NAME:-Agent Access}"
export OCI_SCOPE="${OCI_SCOPE:-${OCI_MIDTIER_SCOPE}}"
DEFAULT_REDIRECT_URIS="http://localhost:8888/callback,http://localhost:8889/callback,http://localhost:8890/callback,http://127.0.0.1:8888/callback,http://127.0.0.1:8889/callback,http://127.0.0.1:8890/callback"
export OCI_REDIRECT_URI="${OCI_REDIRECT_URI:-http://localhost:8888/callback}"
export OCI_REDIRECT_URIS="${OCI_REDIRECT_URIS:-$DEFAULT_REDIRECT_URIS}"
export OCI_IAM_OCITAGS_JSON="${OCI_IAM_OCITAGS_JSON:-}"

if [ "$OCI_SCOPE" = "OracleDBDB_ACCESS_SCOPE" ] || [ "$OCI_SCOPE" = "${DB_NAME}OracleDB${DB_NAME}_DB_ACCESS_SCOPE" ] || [ "$OCI_SCOPE" = "$OCI_DB_SCOPE" ]; then
  OCI_SCOPE="${OCI_MIDTIER_SCOPE}"
  export OCI_SCOPE
fi

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 0: Create OCI IAM Apps, Autonomous AI Database, and Wallet       ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

if ! command -v oci >/dev/null 2>&1; then
  echo -e "${RED}ERROR: OCI CLI is not available. Run this from OCI Cloud Shell or install OCI CLI.${NC}"
  exit 1
fi

oci_global_args=()
[ -n "${OCI_CONFIG_FILE:-${OCI_CLI_CONFIG_FILE:-}}" ] && oci_global_args+=(--config-file "${OCI_CONFIG_FILE:-${OCI_CLI_CONFIG_FILE:-}}")
[ -n "${OCI_PROFILE_NAME:-${OCI_PROFILE:-${OCI_CLI_PROFILE:-}}}" ] && oci_global_args+=(--profile "${OCI_PROFILE_NAME:-${OCI_PROFILE:-${OCI_CLI_PROFILE:-}}}")
[ -n "${OCI_CLI_AUTH:-}" ] && oci_global_args+=(--auth "${OCI_CLI_AUTH}")
oci_iam_ocitags_args=()
[ -n "$OCI_IAM_OCITAGS_JSON" ] && oci_iam_ocitags_args+=(--ext-oci-tags "$OCI_IAM_OCITAGS_JSON")
oci_identity_domain_resource_args=()

if ! oci iam region list "${oci_global_args[@]}" >/dev/null 2>&1; then
  echo -e "${RED}ERROR: OCI CLI cannot call OCI with profile ${OCI_PROFILE_NAME:-${OCI_PROFILE:-${OCI_CLI_PROFILE:-DEFAULT}}}. In Cloud Shell, refresh the session or check your tenancy.${NC}"
  exit 1
fi

mkdir -p "$WORK_DIR"

read_oci_config_value() {
  local key="$1"
  local profile="${OCI_PROFILE_NAME:-${OCI_PROFILE:-${OCI_CLI_PROFILE:-DEFAULT}}}"
  local config_file="${OCI_CONFIG_FILE:-${OCI_CLI_CONFIG_FILE:-$HOME/.oci/config}}"

  if [ ! -f "$config_file" ]; then
    return 0
  fi

  awk -F= -v section="[$profile]" -v key="$key" '
    $0 == section { in_section = 1; next }
    /^\[/ { in_section = 0 }
    in_section && $1 == key {
      value = $2
      sub(/^[ \t]+/, "", value)
      sub(/[ \t]+$/, "", value)
      print value
      exit
    }
  ' "$config_file"
}

normalize_redirect_uri() {
  local first_uri
  if [[ "$OCI_REDIRECT_URI" == *":8080/"* ]] || [[ "$OCI_REDIRECT_URIS" != *"localhost:8888/callback"* ]]; then
    echo -e "${YELLOW}Replacing stale OAuth redirect settings with lab defaults.${NC}"
    OCI_REDIRECT_URIS="$DEFAULT_REDIRECT_URIS"
    export OCI_REDIRECT_URIS
  fi

  first_uri="${OCI_REDIRECT_URIS%%,*}"
  if [ -n "$OCI_REDIRECT_URIS" ] && [[ ",${OCI_REDIRECT_URIS}," != *",${OCI_REDIRECT_URI},"* ]]; then
    echo -e "${YELLOW}Ignoring stale OCI_REDIRECT_URI=${OCI_REDIRECT_URI}${NC}"
    echo -e "${YELLOW}Using OCI_REDIRECT_URI=${first_uri}${NC}"
    OCI_REDIRECT_URI="$first_uri"
    export OCI_REDIRECT_URI
  fi
}

discover_domain_url() {
  if [ -n "${OCI_DOMAIN_URL:-}" ]; then
    printf '%s' "$OCI_DOMAIN_URL"
    return
  fi

  local url
  url=$(oci iam domain list \
    --compartment-id "$TENANCY_OCID" \
    --all \
    "${oci_global_args[@]}" \
    --query "data[?lifecycleState==\`ACTIVE\` && displayName==\`${OCI_DOMAIN_NAME}\`].url | [0]" \
    --raw-output 2>/dev/null || true)

  if [ -z "$url" ] || [ "$url" = "null" ] || [ "$url" = "None" ]; then
    url=$(oci iam domain list \
      --compartment-id "$TENANCY_OCID" \
      --all \
      "${oci_global_args[@]}" \
      --query 'data[?lifecycleState==`ACTIVE`].url | [0]' \
      --raw-output 2>/dev/null || true)
  fi

  if [ -z "$url" ] || [ "$url" = "null" ] || [ "$url" = "None" ]; then
    echo -e "${RED}ERROR: Could not discover an active OCI IAM domain URL.${NC}" >&2
    echo -e "${YELLOW}Export OCI_DOMAIN_URL from Console -> Identity & Security -> Domains -> Domains -> pick the one labeled Current domain.${NC}" >&2
    exit 1
  fi

  printf '%s' "$url"
}

discover_domain_ocid() {
  if [ -n "${OCI_DOMAIN_OCID:-}" ]; then
    printf '%s' "$OCI_DOMAIN_OCID"
    return
  fi

  local response
  response=$(oci iam domain list \
    --compartment-id "$TENANCY_OCID" \
    --all \
    "${oci_global_args[@]}" \
    --output json 2>/dev/null || true)

  DOMAIN_LIST_RESPONSE="$response" DOMAIN_URL="$OCI_DOMAIN_URL" DOMAIN_NAME="$OCI_DOMAIN_NAME" python3 - <<'PY'
import json
import os

try:
    domains = json.loads(os.environ.get("DOMAIN_LIST_RESPONSE", "{}")).get("data", [])
except (json.JSONDecodeError, AttributeError):
    raise SystemExit(0)

domain_url = os.environ.get("DOMAIN_URL", "")
domain_name = os.environ.get("DOMAIN_NAME", "")

for item in domains:
    if item.get("url") == domain_url and item.get("id"):
        print(item["id"])
        raise SystemExit(0)

for item in domains:
    if item.get("display-name") == domain_name and item.get("id"):
        print(item["id"])
        raise SystemExit(0)
PY
}

domain_cmd() {
  oci identity-domains "$@" --endpoint "$OCI_DOMAIN_URL" "${oci_global_args[@]}"
}

raw_request() {
  oci raw-request "$@" "${oci_global_args[@]}"
}

identity_domain_schemas_json() {
  OCI_IAM_OCITAGS_JSON="$OCI_IAM_OCITAGS_JSON" python3 - "$@" <<'PY'
import json
import os
import sys

schemas = list(sys.argv[1:])
if os.environ.get("OCI_IAM_OCITAGS_JSON"):
    schemas.append("urn:ietf:params:scim:schemas:oracle:idcs:extension:OCITags")
print(json.dumps(schemas))
PY
}

oci_tags_schema_fragment() {
  if [ -n "$OCI_IAM_OCITAGS_JSON" ]; then
    printf ',\n    "urn:ietf:params:scim:schemas:oracle:idcs:extension:OCITags"'
  fi
}

oci_tags_body_fragment() {
  if [ -n "$OCI_IAM_OCITAGS_JSON" ]; then
    printf ',\n  "urn:ietf:params:scim:schemas:oracle:idcs:extension:OCITags": %s' "$OCI_IAM_OCITAGS_JSON"
  fi
}

oci_context_body_fragment() {
  printf ',\n  "tenancyOcid": "%s",\n  "compartmentOcid": "%s"' "$TENANCY_OCID" "$ROOT_COMP_ID"
  if [ -n "${OCI_DOMAIN_OCID:-}" ]; then
    printf ',\n  "domainOcid": "%s"' "$OCI_DOMAIN_OCID"
  fi
}

require_created_id() {
  local id_value="$1"
  local resource_label="$2"

  if [ -z "$id_value" ] || [ "$id_value" = "null" ] || [ "$id_value" = "None" ] || [[ "$id_value" == *$'\n'* ]]; then
    echo -e "${RED}ERROR: OCI IAM did not return an id for ${resource_label}.${NC}" >&2
    if [ -n "$id_value" ]; then
      echo -e "${YELLOW}  Received:${NC}" >&2
      printf '%s\n' "$id_value" >&2
    fi
    if [ -z "$OCI_IAM_OCITAGS_JSON" ]; then
      echo -e "${YELLOW}  If this tenancy enforces mandatory tags, export OCI_IAM_OCITAGS_JSON before rerunning.${NC}" >&2
      echo -e "${YELLOW}  Example:${NC}" >&2
      echo "  export OCI_IAM_OCITAGS_JSON='{\"definedTags\":[{\"namespace\":\"dbspmo\",\"key\":\"UsageType\",\"value\":\"<allowed-value>\"}]}'" >&2
    fi
    exit 1
  fi
}

first_query() {
  local command="$1"
  local q1="$2"
  local q2="$3"
  local value
  value=$(eval "$command --query '$q1' --raw-output" 2>/dev/null || true)
  if [ -z "$value" ] || [ "$value" = "null" ] || [ "$value" = "None" ]; then
    value=$(eval "$command --query '$q2' --raw-output" 2>/dev/null || true)
  fi
  [ "$value" = "null" ] || [ "$value" = "None" ] && value=""
  printf '%s' "$value"
}

find_domain_app_id() {
  local name="$1"
  local app_id
  app_id=$(first_query \
    "domain_cmd apps list --all --attribute-sets all --filter 'displayName eq \"${name}\"'" \
    'data.Resources[0].id' \
    'data.resources[0].id')
  if [ -z "$app_id" ] && [[ "$name" == *" ADB OCI IAM "* ]]; then
    app_id=$(first_query \
      "domain_cmd apps list --all --attribute-sets all --filter 'displayName sw \"${name}\"'" \
      'data.Resources[0].id' \
      'data.resources[0].id')
  fi
  printf '%s' "$app_id"
}

find_latest_adb_by_prefix() {
  local prefix="$1"
  local response
  response=$(oci db autonomous-database list \
    --compartment-id "$ROOT_COMP_ID" \
    --lifecycle-state AVAILABLE \
    --all \
    "${oci_global_args[@]}" \
    --output json 2>/dev/null || true)
  ADB_LIST_RESPONSE="$response" ADB_NAME_PREFIX="$prefix" python3 - <<'PY'
import json
import os

try:
    resources = json.loads(os.environ.get("ADB_LIST_RESPONSE", "{}")).get("data", [])
except (json.JSONDecodeError, AttributeError):
    raise SystemExit(0)

prefix = os.environ["ADB_NAME_PREFIX"]
matches = [item for item in resources if str(item.get("db-name", "")).startswith(prefix)]
matches.sort(key=lambda item: str(item.get("time-created", "")), reverse=True)
if matches:
    print(matches[0].get("db-name", ""))
PY
}

discover_home_region() {
  local region

  region="${OCI_REGION:-${OCI_CLI_REGION:-${OCI_REGION_NAME:-}}}"
  if [ -n "$region" ]; then
    printf '%s' "$region"
    return
  fi

  region=$(read_oci_config_value region)
  if [ -n "$region" ]; then
    printf '%s' "$region"
    return
  fi

  region=$(oci iam region-subscription list \
    --tenancy-id "$TENANCY_OCID" \
    "${oci_global_args[@]}" \
    --query 'data[?"is-home-region"==`true`]."region-name" | [0]' \
    --raw-output 2>/dev/null || true)
  [ "$region" = "null" ] || [ "$region" = "None" ] && region=""
  printf '%s' "$region"
}

discover_genai_chat_model_id() {
  local response

  if [ -n "${MODEL_ID:-}" ]; then
    printf '%s' "$MODEL_ID"
    return
  fi

  if [ -z "${OCI_GENAI_REGION:-}" ]; then
    return
  fi

  response=$(oci generative-ai model-collection list-models \
    --compartment-id "$ROOT_COMP_ID" \
    --capability CHAT \
    --all \
    --region "$OCI_GENAI_REGION" \
    "${oci_global_args[@]}" \
    --output json 2>/dev/null || true)

  GENAI_MODEL_RESPONSE="$response" python3 - <<'PY'
import json
import os

try:
    data = json.loads(os.environ.get("GENAI_MODEL_RESPONSE", "{}")).get("data", {})
except (json.JSONDecodeError, AttributeError):
    raise SystemExit(0)

items = data.get("items") or data.get("Items") or []
preferred = [
    "meta.llama-4-scout-17b-16e-instruct",
    "meta.llama-4-maverick-17b-128e-instruct-fp8",
    "cohere.command-r-plus-08-2024",
    "cohere.command-r-08-2024",
    "cohere.command-a-03-2025",
    "google.gemini-2.5-flash",
]

models = []
for item in items:
    name = item.get("display-name") or item.get("displayName") or item.get("name")
    state = str(item.get("lifecycle-state") or item.get("lifecycleState") or "").upper()
    if name and state in ("", "ACTIVE"):
        models.append(name)

for name in preferred:
    if name in models:
        print(name)
        raise SystemExit(0)

for name in models:
    lowered = name.lower()
    if any(skip in lowered for skip in ("embed", "rerank", "guard", "voice", "tts", "protect")):
        continue
    print(name)
    break
PY
}

discover_genai_model_provider() {
  local model_name="$1"
  case "$model_name" in
    cohere.*) printf 'cohere' ;;
    meta.*) printf 'meta' ;;
    google.*) printf 'google' ;;
    xai.*) printf 'xai' ;;
    openai.*) printf 'openai' ;;
    *) printf '%s' "${MODEL_PROVIDER:-}" ;;
  esac
}

find_domain_group_id() {
  local name="$1"
  first_query \
    "domain_cmd groups list --all --filter 'displayName eq \"${name}\"'" \
    'data.Resources[0].id' \
    'data.resources[0].id'
}

find_domain_user_id() {
  local name="$1"
  first_query \
    "domain_cmd users list --all --filter 'userName eq \"${name}\"'" \
    'data.Resources[0].id' \
    'data.resources[0].id'
}

get_domain_app_field() {
  local app_id="$1"
  local field="$2"
  local response
  response=$(domain_cmd app get --app-id "$app_id" --attribute-sets all 2>/dev/null || true)
  [ -z "$response" ] && return

  APP_RESPONSE="$response" python3 - "$field" <<'PY'
import json
import os
import sys

field = sys.argv[1]
try:
    raw = json.loads(os.environ.get("APP_RESPONSE", "{}"))
except Exception:
    sys.exit(0)

data = raw.get("data") or {}
aliases = {
    "client_id": [
        "clientId",
        "client_id",
        "clientID",
        "oauthClientId",
        "oAuthClientId",
        "appId",
        "app_id",
        "name",
        "id",
    ],
    "client_secret": [
        "clientSecret",
        "client_secret",
        "oauthClientSecret",
        "oAuthClientSecret",
    ],
}

for key in aliases.get(field, [field]):
    value = data.get(key)
    if value:
        print(value)
        break
PY
}

generate_secret() {
  python3 - <<'PY'
import secrets
import string

alphabet = string.ascii_letters + string.digits
print("".join(secrets.choice(alphabet) for _ in range(48)))
PY
}

regenerate_app_client_secret() {
  local app_id="$1"
  local body="${WORK_DIR}/regenerate-client-secret-${app_id}.json"
  local response

  cat > "$body" <<EOF
{
  "schemas": [
    "urn:ietf:params:scim:schemas:oracle:idcs:AppClientSecretRegenerator"
  ],
  "appId": "${app_id}"
}
EOF

  response=$(raw_request \
    --http-method POST \
    --target-uri "${OCI_DOMAIN_URL}/admin/v1/AppClientSecretRegenerator?attributeSets=all" \
    --request-headers '{"Content-Type":"application/scim+json"}' \
    --request-body "file://${body}" 2>/dev/null || true)

  RAW_RESPONSE="$response" python3 - <<'PY'
import json
import os
import sys

try:
    raw = json.loads(os.environ.get("RAW_RESPONSE", "{}"))
except Exception:
    sys.exit(0)

data = raw.get("data") or raw
secret = data.get("clientSecret") or data.get("client_secret")
if secret:
    print(secret)
PY
}

redirect_uris_json() {
  REDIRECT_URIS="$OCI_REDIRECT_URIS" python3 - <<'PY'
import json
import os

uris = [uri.strip() for uri in os.environ["REDIRECT_URIS"].split(",") if uri.strip()]
print(json.dumps(uris))
PY
}

allowed_scopes_json() {
  python3 - "$@" <<'PY'
import json
import sys

print(json.dumps([{"fqs": value} for value in sys.argv[1:] if value]))
PY
}

create_or_reuse_db_resource_app() {
  local app_id
  local generated_secret
  local schemas_json
  app_id=$(find_domain_app_id "$OCI_DB_APP_NAME")
  if [ -n "$app_id" ]; then
    echo -e "${CYAN}  Reusing DB resource app ${OCI_DB_APP_NAME}: ${app_id}${NC}" >&2
  else
    generated_secret=$(generate_secret)
    schemas_json=$(identity_domain_schemas_json "urn:ietf:params:scim:schemas:oracle:idcs:App")
    echo -e "${CYAN}  Creating DB resource app ${OCI_DB_APP_NAME}:${NC}" >&2
    show_cmd oci identity-domains app create \
      --endpoint "$OCI_DOMAIN_URL" \
      --display-name "$OCI_DB_APP_NAME" \
      --audience "$OCI_DB_AUDIENCE" \
      --scopes "[{\"value\":\"${OCI_DB_SCOPE_VALUE}\"}]" >&2
    app_id=$(domain_cmd app create \
      --schemas "$schemas_json" \
      --based-on-template '{"value":"CustomWebAppTemplateId","wellKnownId":"CustomWebAppTemplateId"}' \
      --display-name "$OCI_DB_APP_NAME" \
      --description "Database resource app for the ADB OCI IAM Deep Data Security lab" \
      --active true \
      --is-o-auth-client true \
      --is-o-auth-resource true \
      --client-type confidential \
      --client-secret "$generated_secret" \
      --audience "$OCI_DB_AUDIENCE" \
      --scopes "[{\"value\":\"${OCI_DB_SCOPE_VALUE}\",\"displayName\":\"DB Access\",\"description\":\"Access the ADB lab database\",\"requiresConsent\":false}]" \
      --allowed-grants '["client_credentials"]' \
      --bypass-consent true \
      "${oci_identity_domain_resource_args[@]}" \
      "${oci_iam_ocitags_args[@]}" \
      --attribute-sets all \
      --query 'data.id' \
      --raw-output)
    require_created_id "$app_id" "DB resource app ${OCI_DB_APP_NAME}"
    OCI_DB_CLIENT_SECRET="$generated_secret"
    echo -e "${CYAN}  Created DB resource app: ${app_id}${NC}" >&2
  fi
  printf '%s' "$app_id"
}

create_or_reuse_midtier_app() {
  local app_id
  local generated_secret
  local allowed_scopes
  local schemas_json
  allowed_scopes=$(allowed_scopes_json "$OCI_DB_SCOPE" "$OCI_MIDTIER_SCOPE")
  app_id=$(find_domain_app_id "$OCI_MIDTIER_APP_NAME")
  if [ -n "$app_id" ]; then
    echo -e "${CYAN}  Reusing HR midtier app ${OCI_MIDTIER_APP_NAME}: ${app_id}${NC}" >&2
  else
    generated_secret=$(generate_secret)
    schemas_json=$(identity_domain_schemas_json "urn:ietf:params:scim:schemas:oracle:idcs:App")
    echo -e "${CYAN}  Creating HR midtier app ${OCI_MIDTIER_APP_NAME}:${NC}" >&2
    show_cmd oci identity-domains app create \
      --endpoint "$OCI_DOMAIN_URL" \
      --display-name "$OCI_MIDTIER_APP_NAME" \
      --client-type confidential \
      --audience "$OCI_MIDTIER_AUDIENCE" \
      --scopes "[{\"value\":\"${OCI_MIDTIER_SCOPE_VALUE}\"}]" \
      --allowed-scopes "$allowed_scopes" >&2
    app_id=$(domain_cmd app create \
      --schemas "$schemas_json" \
      --based-on-template '{"value":"CustomWebAppTemplateId","wellKnownId":"CustomWebAppTemplateId"}' \
      --display-name "$OCI_MIDTIER_APP_NAME" \
      --description "Oracle SQL MCP midtier app for ADB Deep Data Security and token introspection" \
      --active true \
      --allow-access-control true \
      --is-o-auth-client true \
      --is-o-auth-resource true \
      --client-type confidential \
      --client-secret "$generated_secret" \
      --audience "$OCI_MIDTIER_AUDIENCE" \
      --scopes "[{\"value\":\"${OCI_MIDTIER_SCOPE_VALUE}\",\"displayName\":\"Agent Access\",\"description\":\"Access the Oracle SQL MCP service\",\"requiresConsent\":false}]" \
      --allowed-grants '["client_credentials"]' \
      --allowed-operations '["introspect"]' \
      --allowed-scopes "$allowed_scopes" \
      --bypass-consent true \
      "${oci_identity_domain_resource_args[@]}" \
      "${oci_iam_ocitags_args[@]}" \
      --attribute-sets all \
      --query 'data.id' \
      --raw-output)
    require_created_id "$app_id" "HR midtier app ${OCI_MIDTIER_APP_NAME}"
    OCI_MIDTIER_CLIENT_SECRET="$generated_secret"
    echo -e "${CYAN}  Created HR midtier app: ${app_id}${NC}" >&2
  fi
  printf '%s' "$app_id"
}

configure_db_resource_app() {
  local app_id="$1"
  local secret="${2:-}"

  domain_cmd app patch \
    --app-id "$app_id" \
    --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
    --operations "[{\"op\":\"replace\",\"path\":\"isOAuthClient\",\"value\":true},{\"op\":\"replace\",\"path\":\"isOAuthResource\",\"value\":true},{\"op\":\"replace\",\"path\":\"clientType\",\"value\":\"confidential\"},{\"op\":\"replace\",\"path\":\"audience\",\"value\":\"${OCI_DB_AUDIENCE}\"},{\"op\":\"replace\",\"path\":\"scopes\",\"value\":[{\"value\":\"${OCI_DB_SCOPE_VALUE}\",\"displayName\":\"DB Access\",\"description\":\"Access the ADB lab database\",\"requiresConsent\":false}]},{\"op\":\"replace\",\"path\":\"allowedGrants\",\"value\":[\"client_credentials\"]},{\"op\":\"replace\",\"path\":\"bypassConsent\",\"value\":true}]" \
    >/dev/null

  if [ -n "$secret" ]; then
    domain_cmd app patch \
      --app-id "$app_id" \
      --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
      --operations "[{\"op\":\"replace\",\"path\":\"clientSecret\",\"value\":\"${secret}\"}]" \
      >/dev/null
  fi
}

configure_midtier_app() {
  local app_id="$1"
  local secret="${2:-}"
  local allowed_scopes
  allowed_scopes=$(allowed_scopes_json "$OCI_DB_SCOPE" "$OCI_MIDTIER_SCOPE")

  domain_cmd app patch \
    --app-id "$app_id" \
    --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
    --operations "[{\"op\":\"replace\",\"path\":\"allowAccessControl\",\"value\":true},{\"op\":\"replace\",\"path\":\"isOAuthClient\",\"value\":true},{\"op\":\"replace\",\"path\":\"isOAuthResource\",\"value\":true},{\"op\":\"replace\",\"path\":\"clientType\",\"value\":\"confidential\"},{\"op\":\"replace\",\"path\":\"audience\",\"value\":\"${OCI_MIDTIER_AUDIENCE}\"},{\"op\":\"replace\",\"path\":\"scopes\",\"value\":[{\"value\":\"${OCI_MIDTIER_SCOPE_VALUE}\",\"displayName\":\"Agent Access\",\"description\":\"Access the Oracle SQL MCP service\",\"requiresConsent\":false}]},{\"op\":\"replace\",\"path\":\"allowedGrants\",\"value\":[\"client_credentials\"]},{\"op\":\"replace\",\"path\":\"allowedOperations\",\"value\":[\"introspect\"]},{\"op\":\"replace\",\"path\":\"allowedScopes\",\"value\":${allowed_scopes}},{\"op\":\"replace\",\"path\":\"bypassConsent\",\"value\":true}]" \
    >/dev/null

  if [ -n "$secret" ]; then
    domain_cmd app patch \
      --app-id "$app_id" \
      --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
      --operations "[{\"op\":\"replace\",\"path\":\"clientSecret\",\"value\":\"${secret}\"}]" \
      >/dev/null
  fi
}

configure_login_client_app() {
  local app_id="$1"
  local secret="${2:-}"
  local redirect_json
  local allowed_scopes
  redirect_json=$(redirect_uris_json)
  allowed_scopes=$(allowed_scopes_json "$OCI_SCOPE")

  domain_cmd app patch \
    --app-id "$app_id" \
    --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
    --operations "[{\"op\":\"replace\",\"path\":\"isOAuthClient\",\"value\":true},{\"op\":\"replace\",\"path\":\"isOAuthResource\",\"value\":false},{\"op\":\"replace\",\"path\":\"clientType\",\"value\":\"confidential\"},{\"op\":\"replace\",\"path\":\"allowedGrants\",\"value\":[\"authorization_code\"]},{\"op\":\"replace\",\"path\":\"redirectUris\",\"value\":${redirect_json}},{\"op\":\"replace\",\"path\":\"allowedScopes\",\"value\":${allowed_scopes}},{\"op\":\"replace\",\"path\":\"allUrlSchemesAllowed\",\"value\":true}]" \
    >/dev/null

  if [ -n "$secret" ]; then
    domain_cmd app patch \
      --app-id "$app_id" \
      --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
      --operations "[{\"op\":\"replace\",\"path\":\"clientSecret\",\"value\":\"${secret}\"}]" \
      >/dev/null
  fi
}

create_or_reuse_login_client_app() {
  local app_id
  local generated_secret
  local redirect_json
  local allowed_scopes
  local schemas_json
  redirect_json=$(redirect_uris_json)
  allowed_scopes=$(allowed_scopes_json "$OCI_SCOPE")
  app_id=$(find_domain_app_id "$OCI_CLIENT_APP_NAME")
  if [ -n "$app_id" ]; then
    echo -e "${CYAN}  Reusing confidential login client app ${OCI_CLIENT_APP_NAME}: ${app_id}${NC}" >&2
  else
    generated_secret=$(generate_secret)
    schemas_json=$(identity_domain_schemas_json "urn:ietf:params:scim:schemas:oracle:idcs:App")
    echo -e "${CYAN}  Creating confidential login client app ${OCI_CLIENT_APP_NAME}:${NC}" >&2
    show_cmd oci identity-domains app create \
      --endpoint "$OCI_DOMAIN_URL" \
      --display-name "$OCI_CLIENT_APP_NAME" \
      --client-type confidential \
      --allowed-grants '["authorization_code"]' \
      --allowed-scopes "$allowed_scopes" >&2
    app_id=$(domain_cmd app create \
      --schemas "$schemas_json" \
      --based-on-template '{"value":"CustomWebAppTemplateId","wellKnownId":"CustomWebAppTemplateId"}' \
      --display-name "$OCI_CLIENT_APP_NAME" \
      --description "Confidential interactive login client for the HR agent" \
      --active true \
      --is-o-auth-client true \
      --is-o-auth-resource false \
      --client-type confidential \
      --client-secret "$generated_secret" \
      --allowed-grants '["authorization_code"]' \
      --allowed-scopes "$allowed_scopes" \
      --redirect-uris "$redirect_json" \
      --all-url-schemes-allowed true \
      "${oci_identity_domain_resource_args[@]}" \
      "${oci_iam_ocitags_args[@]}" \
      --attribute-sets all \
      --query 'data.id' \
      --raw-output)
    require_created_id "$app_id" "confidential login client app ${OCI_CLIENT_APP_NAME}"
    OCI_CLIENT_SECRET="$generated_secret"
    echo -e "${CYAN}  Created confidential login client app: ${app_id}${NC}" >&2
  fi

  printf '%s' "$app_id"
}

find_domain_app_role_id() {
  local app_id="$1"
  local role_name="$2"
  first_query \
    "domain_cmd app-roles list --all --filter 'app.value eq \"${app_id}\" and displayName eq \"${role_name}\"'" \
    'data.Resources[0].id' \
    'data.resources[0].id'
}

create_or_reuse_midtier_app_role() {
  local app_id="$1"
  local role_id

  role_id=$(find_domain_app_role_id "$app_id" "$OCI_MIDTIER_APP_ROLE_NAME")
  if [ -n "$role_id" ]; then
    echo -e "${CYAN}  Reusing midtier app role ${OCI_MIDTIER_APP_ROLE_NAME}: ${role_id}${NC}" >&2
  else
    echo -e "${CYAN}  Creating midtier app role ${OCI_MIDTIER_APP_ROLE_NAME}:${NC}" >&2
    if ! role_id=$(domain_cmd app-role create \
      --schemas '["urn:ietf:params:scim:schemas:oracle:idcs:AppRole"]' \
      --app "{\"value\":\"${app_id}\"}" \
      --display-name "$OCI_MIDTIER_APP_ROLE_NAME" \
      --available-to-groups true \
      --available-to-users true \
      --available-to-clients false \
      "${oci_identity_domain_resource_args[@]}" \
      --query 'data.id' \
      --raw-output 2>&1); then
      echo -e "${RED}ERROR: Could not create midtier app role ${OCI_MIDTIER_APP_ROLE_NAME}.${NC}" >&2
      echo "$role_id" >&2
      exit 1
    fi
    require_created_id "$role_id" "midtier app role ${OCI_MIDTIER_APP_ROLE_NAME}"
    echo -e "${CYAN}  Created midtier app role: ${role_id}${NC}" >&2
  fi

  printf '%s' "$role_id"
}

grant_midtier_app_role_to_group() {
  local app_id="$1"
  local role_id="$2"
  local group_id="$3"
  local group_name="$4"
  local body="${WORK_DIR}/grant-${app_id}-${group_id}-${role_id}.json"
  local output
  local tag_schema_fragment
  local tag_body_fragment
  local context_body_fragment
  tag_schema_fragment=$(oci_tags_schema_fragment)
  tag_body_fragment=$(oci_tags_body_fragment)
  context_body_fragment=$(oci_context_body_fragment)

  cat > "$body" <<EOF
{
  "schemas": [
    "urn:ietf:params:scim:schemas:oracle:idcs:Grant"${tag_schema_fragment}
  ],
  "grantMechanism": "ADMINISTRATOR_TO_GROUP",
  "grantee": {
    "type": "Group",
    "value": "${group_id}"
  },
  "app": {
    "value": "${app_id}"
  },
  "entitlement": {
    "attributeName": "appRoles",
    "attributeValue": "${role_id}"
  }
  ${context_body_fragment}
  ${tag_body_fragment}
}
EOF

  if output=$(raw_request \
    --http-method POST \
    --target-uri "${OCI_DOMAIN_URL}/admin/v1/IdcsAppRoleGrants?attributeSets=all" \
    --request-headers '{"Content-Type":"application/scim+json"}' \
    --request-body "file://${body}" 2>&1); then
    echo -e "${CYAN}  Granted ${OCI_MIDTIER_APP_ROLE_NAME} on midtier app to ${group_name}${NC}"
  else
    if printf '%s' "$output" | grep -Eiq '409|already|duplicate|uniqueness'; then
      echo -e "${CYAN}  ${group_name} already has ${OCI_MIDTIER_APP_ROLE_NAME} on midtier app${NC}"
    else
      echo -e "${RED}ERROR: Could not grant ${OCI_MIDTIER_APP_ROLE_NAME} on midtier app to ${group_name}.${NC}"
      echo "$output"
      exit 1
    fi
  fi
}

create_or_reuse_domain_group() {
  local name="$1"
  local group_id
  local schemas_json

  group_id=$(find_domain_group_id "$name")
  if [ -n "$group_id" ]; then
    echo -e "${CYAN}  Reusing domain group ${name}: ${group_id}${NC}" >&2
  else
    schemas_json=$(identity_domain_schemas_json "urn:ietf:params:scim:schemas:core:2.0:Group")
    echo -e "${CYAN}  Creating domain group ${name}:${NC}" >&2
    group_id=$(domain_cmd group create \
      --schemas "$schemas_json" \
      --display-name "$name" \
      "${oci_identity_domain_resource_args[@]}" \
      "${oci_iam_ocitags_args[@]}" \
      --query 'data.id' \
      --raw-output)
    require_created_id "$group_id" "domain group ${name}"
    echo -e "${CYAN}  Created domain group ${name}: ${group_id}${NC}" >&2
  fi

  printf '%s' "$group_id"
}

create_or_reuse_domain_user() {
  local username="$1"
  local given="$2"
  local family="$3"
  local email="$username"
  local user_id
  local schemas_json

  if [[ "$email" != *@* ]]; then
    if [ -n "$OCI_USERNAME_DOMAIN" ]; then
      email="${username}@${OCI_USERNAME_DOMAIN}"
    else
      email="${username}@example.com"
    fi
  fi

  user_id=$(find_domain_user_id "$username")
  if [ -n "$user_id" ]; then
    echo -e "${CYAN}  Reusing domain user ${username}: ${user_id}${NC}" >&2
  else
    schemas_json=$(identity_domain_schemas_json "urn:ietf:params:scim:schemas:core:2.0:User")
    echo -e "${CYAN}  Creating domain user ${username}:${NC}" >&2
    if ! user_id=$(domain_cmd user create \
      --schemas "$schemas_json" \
      --user-name "$username" \
      --name "{\"givenName\":\"${given}\",\"familyName\":\"${family}\"}" \
      --emails "[{\"value\":\"${email}\",\"primary\":true,\"type\":\"work\"}]" \
      --active true \
      "${oci_identity_domain_resource_args[@]}" \
      "${oci_iam_ocitags_args[@]}" \
      --query 'data.id' \
      --raw-output 2>/dev/null); then
      echo -e "${RED}ERROR: Could not create OCI IAM domain user ${username}.${NC}" >&2
      echo -e "${YELLOW}  Check that the username and generated email are valid: ${email}${NC}" >&2
      exit 1
    fi

    if [ -z "$user_id" ] || [ "$user_id" = "null" ] || [ "$user_id" = "None" ]; then
      echo -e "${RED}ERROR: OCI IAM did not return an id for created user ${username}.${NC}" >&2
      exit 1
    fi

    echo -e "${CYAN}  Created domain user ${username}: ${user_id}${NC}" >&2
    echo -e "${YELLOW}  Set or reset this user's password/federated login before verification.${NC}" >&2
  fi

  printf '%s' "$user_id"
}

add_domain_user_to_group() {
  local user_id="$1"
  local group_id="$2"
  local username="$3"
  local group="$4"

  if domain_cmd group patch \
    --group-id "$group_id" \
    --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
    --operations "[{\"op\":\"add\",\"path\":\"members\",\"value\":[{\"value\":\"${user_id}\",\"type\":\"User\"}]}]" \
    >/dev/null 2>&1; then
    echo -e "${CYAN}  Ensured ${username} is in ${group}${NC}"
  else
    echo -e "${RED}ERROR: Could not add ${username} to ${group}.${NC}"
    echo -e "${YELLOW}  User id: ${user_id}${NC}"
    echo -e "${YELLOW}  Group id: ${group_id}${NC}"
    exit 1
  fi
}

create_group_claim() {
  local body="${WORK_DIR}/custom-claim-group.json"
  local tag_schema_fragment
  local tag_body_fragment
  local context_body_fragment
  tag_schema_fragment=$(oci_tags_schema_fragment)
  tag_body_fragment=$(oci_tags_body_fragment)
  context_body_fragment=$(oci_context_body_fragment)

  cat > "$body" <<JSON
{
  "schemas": [
    "urn:ietf:params:scim:schemas:oracle:idcs:CustomClaim"${tag_schema_fragment}
  ],
  "name": "group",
  "value": "\$user.groups.*.display",
  "expression": true,
  "mode": "always",
  "tokenType": "AT",
  "allScopes": true
  ${context_body_fragment}
  ${tag_body_fragment}
}
JSON

  raw_request \
    --http-method POST \
    --target-uri "${OCI_DOMAIN_URL}/admin/v1/CustomClaims" \
    --request-headers '{"Content-Type":"application/scim+json"}' \
    --request-body "file://${body}" \
    >/dev/null 2>&1 || {
      echo -e "${YELLOW}  Could not create the group custom claim automatically.${NC}"
      echo -e "${YELLOW}  If data roles do not activate, create a custom access-token claim named group with value '\$user.groups.*.display'.${NC}"
    }
}

setup_oauth_apps() {
  normalize_redirect_uri
  OCI_DOMAIN_URL=$(discover_domain_url)
  export OCI_DOMAIN_URL

  echo
  echo -e "${YELLOW}Step 1: Creating or reusing OCI IAM OAuth applications...${NC}"
  echo -e "${CYAN}  OCI_DOMAIN_URL    = ${OCI_DOMAIN_URL}${NC}"
  echo -e "${CYAN}  OCI_DB_APP_NAME   = ${OCI_DB_APP_NAME}${NC}"
  echo -e "${CYAN}  OCI_MIDTIER_APP   = ${OCI_MIDTIER_APP_NAME}${NC}"
  echo -e "${CYAN}  OCI_LOGIN_CLIENT  = ${OCI_CLIENT_APP_NAME}${NC}"
  echo -e "${CYAN}  OCI_DB_SCOPE      = ${OCI_DB_SCOPE}${NC}"
  echo -e "${CYAN}  OCI_AGENT_SCOPE   = ${OCI_SCOPE}${NC}"
  echo -e "${CYAN}  OCI_REDIRECT_URIS = ${OCI_REDIRECT_URIS}${NC}"

  OCI_DB_APP_ID=$(create_or_reuse_db_resource_app)
  configure_db_resource_app "$OCI_DB_APP_ID"
  OCI_DB_CLIENT_ID=$(get_domain_app_field "$OCI_DB_APP_ID" client_id)
  if [ -z "${OCI_DB_CLIENT_SECRET:-}" ]; then
    OCI_DB_CLIENT_SECRET=$(get_domain_app_field "$OCI_DB_APP_ID" client_secret)
  fi
  if [ -z "${OCI_DB_CLIENT_SECRET:-}" ]; then
    echo -e "${CYAN}  Resetting DB resource app secret for database-side OAuth validation...${NC}"
    OCI_DB_CLIENT_SECRET=$(regenerate_app_client_secret "$OCI_DB_APP_ID")
  fi
  if [ -z "${OCI_DB_CLIENT_SECRET:-}" ]; then
    echo -e "${YELLOW}  Could not read regenerated secret; setting a new secret directly...${NC}"
    OCI_DB_CLIENT_SECRET=$(generate_secret)
    if [ -z "$OCI_DB_CLIENT_SECRET" ]; then
      echo -e "${RED}ERROR: Could not generate a DB resource app client secret.${NC}"
      exit 1
    fi
    configure_db_resource_app "$OCI_DB_APP_ID" "$OCI_DB_CLIENT_SECRET"
  fi

  OCI_MIDTIER_APP_ID=$(create_or_reuse_midtier_app)
  configure_midtier_app "$OCI_MIDTIER_APP_ID"
  OCI_MIDTIER_CLIENT_ID=$(get_domain_app_field "$OCI_MIDTIER_APP_ID" client_id)
  if [ -z "${OCI_MIDTIER_CLIENT_SECRET:-}" ]; then
    OCI_MIDTIER_CLIENT_SECRET=$(get_domain_app_field "$OCI_MIDTIER_APP_ID" client_secret)
  fi
  if [ -z "${OCI_MIDTIER_CLIENT_SECRET:-}" ]; then
    echo -e "${CYAN}  Resetting HR midtier app secret for application database access...${NC}"
    OCI_MIDTIER_CLIENT_SECRET=$(regenerate_app_client_secret "$OCI_MIDTIER_APP_ID")
  fi
  if [ -z "${OCI_MIDTIER_CLIENT_SECRET:-}" ]; then
    echo -e "${YELLOW}  Could not read regenerated secret; setting a new HR midtier secret directly...${NC}"
    OCI_MIDTIER_CLIENT_SECRET=$(generate_secret)
    if [ -z "$OCI_MIDTIER_CLIENT_SECRET" ]; then
      echo -e "${RED}ERROR: Could not generate an HR midtier app client secret.${NC}"
      exit 1
    fi
    configure_midtier_app "$OCI_MIDTIER_APP_ID" "$OCI_MIDTIER_CLIENT_SECRET"
  fi
  OCI_MIDTIER_APP_ROLE_ID=$(create_or_reuse_midtier_app_role "$OCI_MIDTIER_APP_ID")
  grant_midtier_app_role_to_group "$OCI_MIDTIER_APP_ID" "$OCI_MIDTIER_APP_ROLE_ID" "$EMPLOYEES_OCID" "$OCI_IAM_EMPLOYEE_GROUP"
  grant_midtier_app_role_to_group "$OCI_MIDTIER_APP_ID" "$OCI_MIDTIER_APP_ROLE_ID" "$MANAGERS_OCID" "$OCI_IAM_MANAGER_GROUP"

  OCI_CLIENT_APP_ID=$(create_or_reuse_login_client_app)
  configure_login_client_app "$OCI_CLIENT_APP_ID"
  OCI_CLIENT_ID=$(get_domain_app_field "$OCI_CLIENT_APP_ID" client_id)
  if [ -z "${OCI_CLIENT_SECRET:-}" ]; then
    OCI_CLIENT_SECRET=$(get_domain_app_field "$OCI_CLIENT_APP_ID" client_secret)
  fi
  if [ -z "${OCI_CLIENT_SECRET:-}" ]; then
    echo -e "${CYAN}  Resetting confidential login client secret...${NC}"
    OCI_CLIENT_SECRET=$(regenerate_app_client_secret "$OCI_CLIENT_APP_ID")
  fi
  if [ -z "${OCI_CLIENT_SECRET:-}" ]; then
    echo -e "${YELLOW}  Could not read regenerated secret; setting a new login client secret directly...${NC}"
    OCI_CLIENT_SECRET=$(generate_secret)
    if [ -z "$OCI_CLIENT_SECRET" ]; then
      echo -e "${RED}ERROR: Could not generate a confidential login client secret.${NC}"
      exit 1
    fi
    configure_login_client_app "$OCI_CLIENT_APP_ID" "$OCI_CLIENT_SECRET"
  fi

  if [ -z "$OCI_DB_CLIENT_ID" ]; then
    echo -e "${RED}ERROR: Could not determine OAuth client id for DB resource app ${OCI_DB_APP_ID}.${NC}"
    echo -e "${YELLOW}Inspect it with:${NC}"
    echo "  oci identity-domains app get --endpoint '${OCI_DOMAIN_URL}' --app-id '${OCI_DB_APP_ID}' --attribute-sets all"
    exit 1
  fi
  if [ -z "$OCI_DB_CLIENT_SECRET" ]; then
    echo -e "${RED}ERROR: Could not determine or reset the DB resource app client secret for ${OCI_DB_APP_ID}.${NC}"
    exit 1
  fi
  if [ -z "$OCI_MIDTIER_CLIENT_ID" ]; then
    echo -e "${RED}ERROR: Could not determine OAuth client id for HR midtier app ${OCI_MIDTIER_APP_ID}.${NC}"
    echo -e "${YELLOW}Inspect it with:${NC}"
    echo "  oci identity-domains app get --endpoint '${OCI_DOMAIN_URL}' --app-id '${OCI_MIDTIER_APP_ID}' --attribute-sets all"
    exit 1
  fi
  if [ -z "$OCI_MIDTIER_CLIENT_SECRET" ]; then
    echo -e "${RED}ERROR: Could not determine or reset the HR midtier app client secret for ${OCI_MIDTIER_APP_ID}.${NC}"
    exit 1
  fi
  if [ -z "$OCI_CLIENT_ID" ]; then
    echo -e "${RED}ERROR: Could not determine OAuth client id for app ${OCI_CLIENT_APP_ID}.${NC}"
    echo -e "${YELLOW}Inspect it with:${NC}"
    echo "  oci identity-domains app get --endpoint '${OCI_DOMAIN_URL}' --app-id '${OCI_CLIENT_APP_ID}' --attribute-sets all"
    exit 1
  fi
  if [ -z "$OCI_CLIENT_SECRET" ]; then
    echo -e "${RED}ERROR: Could not determine or reset the confidential login client secret for ${OCI_CLIENT_APP_ID}.${NC}"
    exit 1
  fi

  echo
  echo -e "${YELLOW}Step 2: Creating access-token group claim...${NC}"
  create_group_claim
}

if [ -z "$TENANCY_OCID" ]; then
  TENANCY_OCID="$(read_oci_config_value tenancy)"
fi

if [ -z "${ROOT_COMP_ID:-}" ]; then
  if [ -z "$TENANCY_OCID" ]; then
    echo -e "${RED}ERROR: Could not determine the tenancy OCID needed to resolve compartments.${NC}"
    echo -e "${YELLOW}Set one of these values, then rerun:${NC}"
    echo "  export TENANCY_OCID=ocid1.tenancy.oc1..aaaa..."
    echo "  export OCI_TENANCY=ocid1.tenancy.oc1..aaaa..."
    echo "  export ROOT_COMP_ID=ocid1.compartment.oc1..aaaa..."
    exit 1
  fi

  oci_compartment_lc=$(printf '%s' "$OCI_COMPARTMENT" | tr '[:upper:]' '[:lower:]')
  if [ "$oci_compartment_lc" = "root" ]; then
    ROOT_COMP_ID="$TENANCY_OCID"
  elif [[ "$OCI_COMPARTMENT" == ocid1.compartment.* ]]; then
    ROOT_COMP_ID="$OCI_COMPARTMENT"
  else
    ROOT_COMP_ID=$(oci iam compartment list \
      --compartment-id "$TENANCY_OCID" \
      --compartment-id-in-subtree true \
      --access-level ACCESSIBLE \
      --lifecycle-state ACTIVE \
      --all \
      --raw-output \
      "${oci_global_args[@]}" \
      --query "data[?name=='${OCI_COMPARTMENT}'].id | [0]")

    if [ -z "$ROOT_COMP_ID" ] || [ "$ROOT_COMP_ID" = "null" ]; then
      echo -e "${RED}ERROR: Could not find an accessible active compartment named ${OCI_COMPARTMENT}.${NC}"
      echo -e "${YELLOW}Use one of these options:${NC}"
      echo "  ./00_setup_adb.sh root"
      echo "  ./00_setup_adb.sh <compartment-name>"
      echo "  export OCI_COMPARTMENT=<compartment-name>"
      echo "  export ROOT_COMP_ID=ocid1.compartment.oc1..aaaa..."
      exit 1
    fi
  fi
fi
export ROOT_COMP_ID

OCI_REGION_SELECTED=$(discover_home_region)
if [ -z "$OCI_REGION_SELECTED" ]; then
  echo -e "${RED}ERROR: Could not determine an OCI region from the environment, OCI config profile, or tenancy home region.${NC}" >&2
  echo -e "${YELLOW}Set OCI_REGION, OCI_CLI_REGION, or a region value in your OCI CLI config, then rerun.${NC}" >&2
  exit 1
fi
export OCI_REGION_SELECTED
export OCI_GENAI_REGION="${OCI_GENAI_REGION:-$OCI_REGION_SELECTED}"
export OCI_GENAI_SERVICE_ENDPOINT="${OCI_GENAI_SERVICE_ENDPOINT:-https://inference.generativeai.${OCI_GENAI_REGION}.oci.oraclecloud.com}"
export COMPARTMENT_ID="${COMPARTMENT_ID:-$ROOT_COMP_ID}"
MODEL_ID=$(discover_genai_chat_model_id)
export MODEL_ID
MODEL_PROVIDER="${MODEL_PROVIDER:-$(discover_genai_model_provider "$MODEL_ID")}"
export MODEL_PROVIDER

OCI_DOMAIN_URL=$(discover_domain_url)
export OCI_DOMAIN_URL
OCI_DOMAIN_OCID=$(discover_domain_ocid)
export OCI_DOMAIN_OCID
oci_identity_domain_resource_args=()
[ -n "$TENANCY_OCID" ] && oci_identity_domain_resource_args+=(--tenancy-ocid "$TENANCY_OCID")
[ -n "$ROOT_COMP_ID" ] && oci_identity_domain_resource_args+=(--compartment-ocid "$ROOT_COMP_ID")
[ -n "$OCI_DOMAIN_OCID" ] && oci_identity_domain_resource_args+=(--domain-ocid "$OCI_DOMAIN_OCID")

reused_db_name=""
if [ "$ADB_CREATE_MODE" = "create" ]; then
  reused_db_name=$(find_latest_adb_by_prefix "$DB_NAME_REUSE_PREFIX")
fi
if [ "$ADB_CREATE_MODE" = "create" ] && [ -n "$reused_db_name" ] && [ "$reused_db_name" != "$DB_NAME" ]; then
  echo -e "${YELLOW}Reusing newest available ADB matching ${DB_NAME_REUSE_PREFIX}*: ${reused_db_name}${NC}"
  DB_NAME="$reused_db_name"
  DB_DISPLAY_NAME="$reused_db_name"
  ADB_SERVICE="${DB_NAME}_low"
  WALLET_DIR="$HOME/adb_wallet/${DB_NAME}"
  OCI_DB_APP_NAME="${DB_NAME} ADB OCI IAM DB Resource - ${ADB_OCI_IAM_LAB_INSTANCE_ID}"
  OCI_CLIENT_APP_NAME="${DB_NAME} Confidential Login Client - ${ADB_OCI_IAM_LAB_INSTANCE_ID}"
  OCI_MIDTIER_APP_NAME="${DB_NAME} HR Midtier App - ${ADB_OCI_IAM_LAB_INSTANCE_ID}"
  OCI_DB_AUDIENCE="${DB_NAME}OracleDB${ADB_OCI_IAM_LAB_INSTANCE_SHORT}"
  OCI_DB_SCOPE_VALUE="${DB_NAME}_DB_ACCESS_SCOPE_${ADB_OCI_IAM_LAB_INSTANCE_SHORT}"
  OCI_DB_SCOPE="${OCI_DB_AUDIENCE}${OCI_DB_SCOPE_VALUE}"
  OCI_MIDTIER_AUDIENCE="${DB_NAME}HR${ADB_OCI_IAM_LAB_INSTANCE_SHORT}"
  OCI_MIDTIER_SCOPE_VALUE="${DB_NAME}_AGENT_ACCESS_${ADB_OCI_IAM_LAB_INSTANCE_SHORT}"
  OCI_MIDTIER_SCOPE="${OCI_MIDTIER_AUDIENCE}${OCI_MIDTIER_SCOPE_VALUE}"
  if [ "$OCI_SCOPE" = "OracleDBDB_ACCESS_SCOPE" ] || [[ "$OCI_SCOPE" == *"DB_ACCESS_SCOPE"* ]]; then
    OCI_SCOPE="$OCI_MIDTIER_SCOPE"
  fi
  export DB_NAME DB_DISPLAY_NAME ADB_SERVICE WALLET_DIR OCI_DB_APP_NAME OCI_CLIENT_APP_NAME OCI_MIDTIER_APP_NAME
  export OCI_DB_AUDIENCE OCI_DB_SCOPE_VALUE OCI_DB_SCOPE OCI_MIDTIER_AUDIENCE OCI_MIDTIER_SCOPE_VALUE OCI_MIDTIER_SCOPE OCI_SCOPE
fi
require_non_production_acknowledgement

echo
echo -e "${YELLOW}Step 0: Creating or reusing OCI IAM domain groups...${NC}"
EMPLOYEES_OCID=$(create_or_reuse_domain_group "$OCI_IAM_EMPLOYEE_GROUP")
MANAGERS_OCID=$(create_or_reuse_domain_group "$OCI_IAM_MANAGER_GROUP")

setup_oauth_apps

echo -e "${CYAN}Configuration:${NC}"
echo -e "${CYAN}  OCI_COMPARTMENT = ${OCI_COMPARTMENT}${NC}"
echo -e "${CYAN}  ROOT_COMP_ID    = ${ROOT_COMP_ID}${NC}"
echo -e "${CYAN}  DB_NAME         = ${DB_NAME}${NC}"
echo -e "${CYAN}  LAB_INSTANCE_ID = ${ADB_OCI_IAM_LAB_INSTANCE_ID}${NC}"
echo -e "${CYAN}  DB_DISPLAY_NAME = ${DB_DISPLAY_NAME}${NC}"
echo -e "${CYAN}  DB_VERSION      = ${DB_VERSION}${NC}"
echo -e "${CYAN}  ADB mode        = ${ADB_CREATE_MODE}${NC}"
echo -e "${CYAN}  IS_FREE_TIER    = ${ADB_IS_FREE_TIER}${NC}"
if [ "$ADB_IS_FREE_TIER" = "false" ]; then
  echo -e "${CYAN}  LICENSE_MODEL   = ${ADB_LICENSE_MODEL}${NC}"
fi
if [ -n "$ADB_MAINTENANCE_SCHEDULE_TYPE" ]; then
  echo -e "${CYAN}  MAINTENANCE     = ${ADB_MAINTENANCE_SCHEDULE_TYPE}${NC}"
fi
echo -e "${CYAN}  ADB_SERVICE     = ${ADB_SERVICE}${NC}"
echo -e "${CYAN}  WALLET_DIR      = ${WALLET_DIR}${NC}"
echo -e "${CYAN}  IAM groups      = ${OCI_IAM_EMPLOYEE_GROUP}, ${OCI_IAM_MANAGER_GROUP}${NC}"
echo -e "${CYAN}  Login client    = ${OCI_CLIENT_ID}${NC}"
echo -e "${CYAN}  HR midtier app  = ${OCI_MIDTIER_CLIENT_ID}${NC}"
echo -e "${CYAN}  GenAI endpoint  = ${OCI_GENAI_SERVICE_ENDPOINT}${NC}"
if [ -n "$MODEL_ID" ]; then
  echo -e "${CYAN}  GenAI model     = ${MODEL_ID}${NC}"
  [ -n "$MODEL_PROVIDER" ] && echo -e "${CYAN}  GenAI provider  = ${MODEL_PROVIDER}${NC}"
else
  echo -e "${YELLOW}  GenAI model     = not discovered; set MODEL_ID if this tenancy has OCI Generative AI access.${NC}"
fi
echo -e "${CYAN}  Deep Data Security end-user context grants require Autonomous AI Database 26ai.${NC}"
echo

if [ "$ADB_CREATE_MODE" = "existing" ]; then
  echo -e "${YELLOW}Step 3: Using provided Autonomous Database connection...${NC}"
  ADB_OCID="${EXISTING_ADB_OCID:-external}"
  export ADB_OCID
  echo -e "${CYAN}  Skipping ADB create/reuse in this OCI tenancy.${NC}"
  echo -e "${CYAN}  DB_DSN / ADB_SERVICE = ${ADB_SERVICE}${NC}"

  echo
  echo -e "${YELLOW}Step 4: Using provided wallet directory...${NC}"
  if [ ! -d "$WALLET_DIR" ]; then
    echo -e "${RED}ERROR: WALLET_DIR does not exist: ${WALLET_DIR}${NC}" >&2
    echo -e "${YELLOW}Download and unzip the existing ADB wallet, then set WALLET_DIR to that directory.${NC}" >&2
    exit 1
  fi
  missing_wallet_files=false
  for wallet_file in tnsnames.ora sqlnet.ora cwallet.sso ewallet.p12; do
    if [ ! -f "${WALLET_DIR}/${wallet_file}" ]; then
      echo -e "${RED}ERROR: Missing wallet file ${WALLET_DIR}/${wallet_file}.${NC}" >&2
      missing_wallet_files=true
    fi
  done
  if [ "$missing_wallet_files" = true ]; then
    echo -e "${YELLOW}Download and unzip the existing ADB wallet, then set WALLET_DIR to that directory.${NC}" >&2
    exit 1
  fi
else
echo -e "${YELLOW}Step 3: Creating or reusing Autonomous AI Database...${NC}"
echo -e "${CYAN}  Checking for existing ADB:${NC}"
show_cmd oci db autonomous-database list \
  --compartment-id "$ROOT_COMP_ID" \
  --lifecycle-state AVAILABLE \
  --all \
  --raw-output \
  "${oci_global_args[@]}" \
  --query "data[?\"db-name\"=='${DB_NAME}'].id | [0]"
ADB_OCID=$(oci db autonomous-database list \
  --compartment-id "$ROOT_COMP_ID" \
  --lifecycle-state AVAILABLE \
  --all \
  --raw-output \
  "${oci_global_args[@]}" \
  --query "data[?\"db-name\"=='${DB_NAME}'].id | [0]")
ADB_DB_VERSION=$(oci db autonomous-database list \
  --compartment-id "$ROOT_COMP_ID" \
  --lifecycle-state AVAILABLE \
  --all \
  --raw-output \
  "${oci_global_args[@]}" \
  --query "data[?\"db-name\"=='${DB_NAME}'].\"db-version\" | [0]")
ADB_ANY_STATE=$(oci db autonomous-database list \
  --compartment-id "$ROOT_COMP_ID" \
  --all \
  --raw-output \
  "${oci_global_args[@]}" \
  --query "data[?\"db-name\"=='${DB_NAME}'].\"lifecycle-state\" | [0]")
adb_maintenance_args=()
if [ -n "$ADB_MAINTENANCE_SCHEDULE_TYPE" ]; then
  adb_maintenance_args=(--maintenance-schedule-type "$ADB_MAINTENANCE_SCHEDULE_TYPE")
fi
adb_license_args=()
if [ "$ADB_IS_FREE_TIER" = "false" ]; then
  adb_license_args=(--license-model "$ADB_LICENSE_MODEL")
fi
adb_compute_args=()
if [ "$ADB_IS_FREE_TIER" = "false" ]; then
  # ECPU is the current compute model for new paid Autonomous AI Databases.
  # Two ECPUs is the minimum outside an elastic resource pool.
  adb_compute_args=(--compute-model ECPU --compute-count 2)
fi

if [ -z "$ADB_OCID" ] || [ "$ADB_OCID" = "null" ]; then
  if [ -n "$ADB_ANY_STATE" ] && [ "$ADB_ANY_STATE" != "null" ]; then
    echo -e "${YELLOW}  Found ${DB_NAME} in lifecycle state ${ADB_ANY_STATE}; it is not reusable for this lab.${NC}"
  fi
  echo -e "${CYAN}  Creating ADB:${NC}"
  show_cmd oci db autonomous-database create \
    --compartment-id "$ROOT_COMP_ID" \
    --db-name "$DB_NAME" \
    --display-name "$DB_DISPLAY_NAME" \
    --db-version "$DB_VERSION" \
    --is-free-tier "$ADB_IS_FREE_TIER" \
    "${adb_license_args[@]}" \
    "${adb_maintenance_args[@]}" \
    "${oci_global_args[@]}" \
    --admin-password '<hidden>' \
    "${adb_compute_args[@]}" \
    --data-storage-size-in-tbs 1 \
    --wait-for-state AVAILABLE
  oci db autonomous-database create \
    --compartment-id "$ROOT_COMP_ID" \
    --db-name "$DB_NAME" \
    --display-name "$DB_DISPLAY_NAME" \
    --db-version "$DB_VERSION" \
    --is-free-tier "$ADB_IS_FREE_TIER" \
    "${adb_license_args[@]}" \
    "${adb_maintenance_args[@]}" \
    "${oci_global_args[@]}" \
    --admin-password "$ADMIN_PWD" \
    "${adb_compute_args[@]}" \
    --data-storage-size-in-tbs 1 \
    --wait-for-state AVAILABLE \
    >/dev/null

  ADB_OCID=$(oci db autonomous-database list \
    --compartment-id "$ROOT_COMP_ID" \
    --lifecycle-state AVAILABLE \
    --all \
    --raw-output \
    "${oci_global_args[@]}" \
    --query "data[?\"db-name\"=='${DB_NAME}'].id | [0]")
  ADB_DB_VERSION=$(oci db autonomous-database list \
    --compartment-id "$ROOT_COMP_ID" \
    --lifecycle-state AVAILABLE \
    --all \
    --raw-output \
    "${oci_global_args[@]}" \
    --query "data[?\"db-name\"=='${DB_NAME}'].\"db-version\" | [0]")
  echo -e "${CYAN}  Created ADB: ${ADB_OCID}${NC}"
  echo -e "${CYAN}  Created ADB version: ${ADB_DB_VERSION}${NC}"
else
  if [ "$ADB_DB_VERSION" != "$DB_VERSION" ]; then
    echo -e "${RED}ERROR: Found existing ADB ${DB_NAME}, but it is ${ADB_DB_VERSION}, not ${DB_VERSION}.${NC}"
    echo -e "${YELLOW}This lab requires Autonomous AI Database ${DB_VERSION} for Deep Data Security end-user context privileges.${NC}"
    echo -e "${YELLOW}Use a different DB_NAME or delete/recreate the existing database as ${DB_VERSION}.${NC}"
    exit 1
  fi
  echo -e "${CYAN}  Reusing ADB: ${ADB_OCID}${NC}"
  echo -e "${CYAN}  Existing ADB version: ${ADB_DB_VERSION}${NC}"
fi

echo
echo -e "${YELLOW}Step 4: Downloading wallet...${NC}"
mkdir -p "$WALLET_DIR"
show_cmd oci db autonomous-database generate-wallet \
  --autonomous-database-id "$ADB_OCID" \
  --password '<hidden>' \
  "${oci_global_args[@]}" \
  --file "${WALLET_DIR}/${DB_NAME}_wallet.zip"
oci db autonomous-database generate-wallet \
  --autonomous-database-id "$ADB_OCID" \
  --password "$WALLET_PWD" \
  "${oci_global_args[@]}" \
  --file "${WALLET_DIR}/${DB_NAME}_wallet.zip" \
  >/dev/null

(
  cd "$WALLET_DIR"
  unzip -oq "${DB_NAME}_wallet.zip"
)
fi

if [ -f "${WALLET_DIR}/sqlnet.ora" ]; then
  echo -e "${CYAN}  Rewriting sqlnet.ora wallet directory to ${WALLET_DIR}:${NC}"
  show_cmd sed -i.bak-wallet-dir -E "s#DIRECTORY=\"\\?/network/admin\"#DIRECTORY=\"${WALLET_DIR}\"#g" "${WALLET_DIR}/sqlnet.ora"
  sed -i.bak-wallet-dir -E "s#DIRECTORY=\"\\?/network/admin\"#DIRECTORY=\"${WALLET_DIR}\"#g" "${WALLET_DIR}/sqlnet.ora"
fi

echo
echo -e "${YELLOW}Step 5: Creating or reusing OCI IAM domain groups and demo users...${NC}"
echo -e "${CYAN}  Domain groups already prepared: ${OCI_IAM_EMPLOYEE_GROUP}, ${OCI_IAM_MANAGER_GROUP}${NC}"

MARVIN_ID=""
EMMA_ID=""
if [ "$CREATE_DEMO_USERS" = "1" ]; then
  MARVIN_ID=$(create_or_reuse_domain_user "$MARVIN_USERNAME" "Marvin" "Morgan")
  EMMA_ID=$(create_or_reuse_domain_user "$EMMA_USERNAME" "Emma" "Baker")
  add_domain_user_to_group "$MARVIN_ID" "$EMPLOYEES_OCID" "$MARVIN_USERNAME" "$OCI_IAM_EMPLOYEE_GROUP"
  add_domain_user_to_group "$MARVIN_ID" "$MANAGERS_OCID" "$MARVIN_USERNAME" "$OCI_IAM_MANAGER_GROUP"
  add_domain_user_to_group "$EMMA_ID" "$EMPLOYEES_OCID" "$EMMA_USERNAME" "$OCI_IAM_EMPLOYEE_GROUP"
else
  echo -e "${YELLOW}  CREATE_DEMO_USERS=0, so Marvin and Emma users were not created.${NC}"
  echo -e "${YELLOW}  Ensure ${MARVIN_USERNAME} has ${OCI_IAM_EMPLOYEE_GROUP}, ${OCI_IAM_MANAGER_GROUP}.${NC}"
  echo -e "${YELLOW}  Ensure ${EMMA_USERNAME} has ${OCI_IAM_EMPLOYEE_GROUP}.${NC}"
fi

cat > "$ENV_FILE" <<EOF
export OCI_COMPARTMENT='${OCI_COMPARTMENT}'
export OCI_PROFILE_NAME='${OCI_PROFILE_SELECTED}'
export ROOT_COMP_ID='${ROOT_COMP_ID}'
export COMPARTMENT_ID='${COMPARTMENT_ID}'
export OCI_REGION_SELECTED='${OCI_REGION_SELECTED}'
export OCI_GENAI_REGION='${OCI_GENAI_REGION}'
export OCI_GENAI_SERVICE_ENDPOINT='${OCI_GENAI_SERVICE_ENDPOINT}'
export MODEL_ID='${MODEL_ID}'
export MODEL_PROVIDER='${MODEL_PROVIDER}'
export DB_NAME='${DB_NAME}'
export DB_DISPLAY_NAME='${DB_DISPLAY_NAME}'
export DB_VERSION='${DB_VERSION}'
export ADB_CREATE_MODE='${ADB_CREATE_MODE}'
export EXISTING_DB_DSN='${EXISTING_DB_DSN}'
export EXISTING_ADB_OCID='${EXISTING_ADB_OCID}'
export ADB_IS_FREE_TIER='${ADB_IS_FREE_TIER}'
export ADB_LICENSE_MODEL='${ADB_LICENSE_MODEL}'
export ADB_MAINTENANCE_SCHEDULE_TYPE='${ADB_MAINTENANCE_SCHEDULE_TYPE}'
export ADB_OCID='${ADB_OCID}'
export ADB_SERVICE='${ADB_SERVICE}'
export ADMIN_PWD='${ADMIN_PWD}'
export WALLET_PWD='${WALLET_PWD}'
export WALLET_DIR='${WALLET_DIR}'
export TNS_ADMIN='${WALLET_DIR}'
export OCI_TOKEN_DIR='${OCI_TOKEN_DIR:-$HOME/.oci/adb-oci-iam}'
export APP_DB_USER='${APP_DB_USER}'
export APP_DB_PASSWORD='${APP_DB_PASSWORD}'
export DB_USER='${APP_DB_USER}'
export DB_PASSWORD='${APP_DB_PASSWORD}'
export DB_DSN='${ADB_SERVICE}'
export SSL_CONFIG_DIR='${WALLET_DIR}'
export DEFAULT_SCHEMA='HR'
export APP_CLIENT_ID='${OCI_CLIENT_ID}'
export APP_CLIENT_SECRET='${OCI_CLIENT_SECRET}'
export APP_SCOPE='${OCI_SCOPE}'
export REDIRECT_URI='${OCI_REDIRECT_URI}'
export DB_CLIENT_ID='${OCI_MIDTIER_CLIENT_ID}'
export DB_CLIENT_SECRET='${OCI_MIDTIER_CLIENT_SECRET}'
export DB_SCOPE='${OCI_DB_SCOPE}'
export MCP_RESOURCE_SERVER_URL='${MCP_RESOURCE_SERVER_URL:-http://127.0.0.1:8000/mcp}'
export MCP_AUTHORIZATION_SERVER_URL='${OCI_DOMAIN_URL}'
export MCP_TOKEN_ISSUER='${MCP_TOKEN_ISSUER:-https://identity.oraclecloud.com/}'
export MCP_AUTH_AUDIENCE='${OCI_MIDTIER_AUDIENCE}'
export MCP_REQUIRED_SCOPES='${OCI_MIDTIER_SCOPE_VALUE}'
export MCP_INTROSPECTION_URL='${OCI_DOMAIN_URL}/oauth2/v1/introspect'
export MCP_INTROSPECTION_CLIENT_ID='${OCI_MIDTIER_CLIENT_ID}'
export MCP_INTROSPECTION_CLIENT_SECRET='${OCI_MIDTIER_CLIENT_SECRET}'
export OCI_CONFIG_FILE='${OCI_CONFIG_FILE:-$HOME/.oci/config}'
export OCI_PROFILE='${OCI_PROFILE_SELECTED}'
export OCI_CLI_PROFILE='${OCI_PROFILE_SELECTED}'
export OCI_CLI_AUTH='${OCI_CLI_AUTH:-}'
export OCI_AUTH_TYPE='${OCI_AUTH_TYPE:-${OCI_CLI_AUTH:-}}'
export GENAI_AUTH_TYPE='${GENAI_AUTH_TYPE:-auto}'
export OCI_GENAI_ENDPOINT='${OCI_GENAI_SERVICE_ENDPOINT}'
export TENANCY_OCID='${TENANCY_OCID}'
export OCI_DOMAIN_URL='${OCI_DOMAIN_URL}'
export OCI_DB_APP_ID='${OCI_DB_APP_ID}'
export OCI_DB_CLIENT_ID='${OCI_DB_CLIENT_ID}'
export OCI_DB_CLIENT_SECRET='${OCI_DB_CLIENT_SECRET}'
export OCI_DB_SCOPE='${OCI_DB_SCOPE}'
export OCI_MIDTIER_APP_ID='${OCI_MIDTIER_APP_ID}'
export OCI_MIDTIER_CLIENT_ID='${OCI_MIDTIER_CLIENT_ID}'
export OCI_MIDTIER_CLIENT_SECRET='${OCI_MIDTIER_CLIENT_SECRET}'
export OCI_MIDTIER_AUDIENCE='${OCI_MIDTIER_AUDIENCE}'
export OCI_MIDTIER_SCOPE_VALUE='${OCI_MIDTIER_SCOPE_VALUE}'
export OCI_MIDTIER_SCOPE='${OCI_MIDTIER_SCOPE}'
export OCI_MIDTIER_APP_ROLE_NAME='${OCI_MIDTIER_APP_ROLE_NAME}'
export OCI_MIDTIER_APP_ROLE_ID='${OCI_MIDTIER_APP_ROLE_ID}'
export OCI_CLIENT_APP_ID='${OCI_CLIENT_APP_ID}'
export OCI_CLIENT_ID='${OCI_CLIENT_ID}'
export OCI_CLIENT_SECRET='${OCI_CLIENT_SECRET}'
export OCI_AUDIENCE='${OCI_DB_AUDIENCE}'
export OCI_SCOPE='${OCI_SCOPE}'
export OCI_REDIRECT_URI='${OCI_REDIRECT_URI}'
export OCI_REDIRECT_URIS='${OCI_REDIRECT_URIS}'
export HR_OCI_DOMAIN_URL='${OCI_DOMAIN_URL}'
export HR_DB_APP_ID='${OCI_DB_APP_ID}'
export HR_DB_CLIENT_ID='${OCI_MIDTIER_CLIENT_ID}'
export HR_DB_CLIENT_SECRET='${OCI_MIDTIER_CLIENT_SECRET}'
export HR_DB_SCOPE='${OCI_DB_SCOPE}'
export HR_MIDTIER_APP_ID='${OCI_MIDTIER_APP_ID}'
export HR_MIDTIER_CLIENT_ID='${OCI_MIDTIER_CLIENT_ID}'
export HR_MIDTIER_CLIENT_SECRET='${OCI_MIDTIER_CLIENT_SECRET}'
export HR_MIDTIER_SCOPE='${OCI_MIDTIER_SCOPE}'
export HR_LOGIN_APP_ID='${OCI_CLIENT_APP_ID}'
export HR_LOGIN_CLIENT_ID='${OCI_CLIENT_ID}'
export HR_LOGIN_CLIENT_SECRET='${OCI_CLIENT_SECRET}'
export HR_APP_CLIENT_ID='${OCI_CLIENT_ID}'
export HR_APP_CLIENT_SECRET='${OCI_CLIENT_SECRET}'
export HR_APP_SCOPE='${OCI_SCOPE}'
export HR_REDIRECT_URI='${OCI_REDIRECT_URI}'
export ADB_OCI_IAM_LAB_INSTANCE_ID='${ADB_OCI_IAM_LAB_INSTANCE_ID}'
export OCI_DB_APP_NAME='${OCI_DB_APP_NAME}'
export OCI_CLIENT_APP_NAME='${OCI_CLIENT_APP_NAME}'
export OCI_MIDTIER_APP_NAME='${OCI_MIDTIER_APP_NAME}'
export OCI_IAM_EMPLOYEE_GROUP='${OCI_IAM_EMPLOYEE_GROUP}'
export OCI_IAM_MANAGER_GROUP='${OCI_IAM_MANAGER_GROUP}'
export EMPLOYEES_OCID='${EMPLOYEES_OCID}'
export MANAGERS_OCID='${MANAGERS_OCID}'
export OCI_USERNAME_DOMAIN='${OCI_USERNAME_DOMAIN}'
export MARVIN_USERNAME='${MARVIN_USERNAME}'
export EMMA_USERNAME='${EMMA_USERNAME}'
export MARVIN_ID='${MARVIN_ID}'
export EMMA_ID='${EMMA_ID}'
export CREATE_DEMO_USERS='${CREATE_DEMO_USERS}'
EOF
chmod 600 "$ENV_FILE"

cat > "$APP_ENV_FILE" <<EOF
# Generated by adb-oci-iam/00_setup_adb.sh.
# Keep this file local; it contains OAuth client secrets for the demo apps.

# OCI Generative AI configuration can be overridden here if needed.
OCI_CONFIG_FILE=${OCI_CONFIG_FILE:-~/.oci/config}
OCI_PROFILE=${OCI_PROFILE_SELECTED}
OCI_CLI_PROFILE=${OCI_PROFILE_SELECTED}
OCI_CLI_AUTH=${OCI_CLI_AUTH:-}
OCI_AUTH_TYPE=${OCI_AUTH_TYPE:-${OCI_CLI_AUTH:-}}
GENAI_AUTH_TYPE=${GENAI_AUTH_TYPE:-auto}
COMPARTMENT_ID=${COMPARTMENT_ID}
OCI_GENAI_REGION=${OCI_GENAI_REGION}
OCI_GENAI_SERVICE_ENDPOINT=${OCI_GENAI_SERVICE_ENDPOINT}
OCI_GENAI_ENDPOINT=${OCI_GENAI_SERVICE_ENDPOINT}
MODEL_ID=${MODEL_ID}
MODEL_PROVIDER=${MODEL_PROVIDER}

# Oracle Database connection used by the MCP server.
DB_USER=${APP_DB_USER}
DB_PASSWORD=${APP_DB_PASSWORD}
DB_DSN=${ADB_SERVICE}
SSL_CONFIG_DIR=${WALLET_DIR}
WALLET_PWD=${WALLET_PWD}
DEFAULT_SCHEMA=HR

# OCI IAM OAuth clients. The midtier client is both the database client and
# the MCP resource server's introspection client; setup enables `introspect`.
OCI_DOMAIN_URL=${OCI_DOMAIN_URL}
APP_CLIENT_ID=${OCI_CLIENT_ID}
APP_CLIENT_SECRET=${OCI_CLIENT_SECRET}
APP_SCOPE=${OCI_SCOPE}
REDIRECT_URI=${OCI_REDIRECT_URI}
DB_CLIENT_ID=${OCI_MIDTIER_CLIENT_ID}
DB_CLIENT_SECRET=${OCI_MIDTIER_CLIENT_SECRET}
DB_SCOPE=${OCI_DB_SCOPE}

# MCP HTTP resource-server validation.
MCP_RESOURCE_SERVER_URL=${MCP_RESOURCE_SERVER_URL:-http://127.0.0.1:8000/mcp}
MCP_AUTHORIZATION_SERVER_URL=${OCI_DOMAIN_URL}
MCP_TOKEN_ISSUER=${MCP_TOKEN_ISSUER:-https://identity.oraclecloud.com/}
MCP_AUTH_AUDIENCE=${OCI_MIDTIER_AUDIENCE}
MCP_REQUIRED_SCOPES=${OCI_MIDTIER_SCOPE_VALUE}
MCP_INTROSPECTION_URL=${OCI_DOMAIN_URL}/oauth2/v1/introspect
MCP_INTROSPECTION_CLIENT_ID=${OCI_MIDTIER_CLIENT_ID}
MCP_INTROSPECTION_CLIENT_SECRET=${OCI_MIDTIER_CLIENT_SECRET}
EOF
chmod 600 "$APP_ENV_FILE"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 0 Completed: OCI IAM Apps, ADB, and Wallet Ready                 ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}Environment file: ${ENV_FILE}${NC}"
echo -e "${CYAN}Application .env:  ${APP_ENV_FILE}${NC}"
echo "Load it before continuing:"
echo "  source ./.adb-oci-iam.env"
echo
