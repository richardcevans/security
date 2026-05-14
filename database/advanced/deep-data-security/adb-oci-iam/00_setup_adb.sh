#!/bin/bash
# Create or reuse an Autonomous Database Serverless instance and wallet.
# Intended to run from OCI Cloud Shell.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.adb-oci-iam.env"

usage() {
  cat <<'EOF'
Usage:
  ./00_setup_adb.sh [compartment-name|compartment-ocid|root]

Compartment selection:
  ROOT_COMP_ID       Direct compartment OCID. Highest priority.
  OCI_COMPARTMENT    Compartment name, compartment OCID, or root.
  argument           Same as OCI_COMPARTMENT.

If none is provided, the script uses the root compartment.
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

export DB_NAME="${DB_NAME:-deepsec1}"
export DB_DISPLAY_NAME="${DB_DISPLAY_NAME:-${DB_NAME}}"
export ADMIN_PWD="${ADMIN_PWD:-Oracle123+Oracle123+}"
export WALLET_PWD="${WALLET_PWD:-Oracle123+}"
export WALLET_DIR="${WALLET_DIR:-$HOME/adb_wallet/${DB_NAME}}"
export ADB_SERVICE="${ADB_SERVICE:-${DB_NAME}_low}"
export OCI_IAM_SCHEMA_GROUP="${OCI_IAM_SCHEMA_GROUP:-ALL_DB_USERS}"
export OCI_IAM_EMPLOYEE_GROUP="${OCI_IAM_EMPLOYEE_GROUP:-EMPLOYEES}"
export OCI_IAM_MANAGER_GROUP="${OCI_IAM_MANAGER_GROUP:-MANAGERS}"
export TENANCY_OCID="${TENANCY_OCID:-${OCI_TENANCY:-}}"
export OCI_COMPARTMENT="${1:-${OCI_COMPARTMENT:-root}}"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 0: Create ADB-S Instance and Wallet                              ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

if ! command -v oci >/dev/null 2>&1; then
  echo -e "${RED}ERROR: OCI CLI is not available. Run this from OCI Cloud Shell or install OCI CLI.${NC}"
  exit 1
fi

if ! oci iam region list >/dev/null 2>&1; then
  echo -e "${RED}ERROR: OCI CLI cannot call OCI. In Cloud Shell, refresh the session or check your tenancy.${NC}"
  exit 1
fi

read_oci_config_value() {
  local key="$1"
  local profile="${OCI_CLI_PROFILE:-DEFAULT}"
  local config_file="${OCI_CLI_CONFIG_FILE:-$HOME/.oci/config}"

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

  if [ "${OCI_COMPARTMENT,,}" = "root" ]; then
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

echo -e "${CYAN}Configuration:${NC}"
echo -e "${CYAN}  OCI_COMPARTMENT = ${OCI_COMPARTMENT}${NC}"
echo -e "${CYAN}  ROOT_COMP_ID    = ${ROOT_COMP_ID}${NC}"
echo -e "${CYAN}  DB_NAME         = ${DB_NAME}${NC}"
echo -e "${CYAN}  DB_DISPLAY_NAME = ${DB_DISPLAY_NAME}${NC}"
echo -e "${CYAN}  ADB_SERVICE     = ${ADB_SERVICE}${NC}"
echo -e "${CYAN}  WALLET_DIR      = ${WALLET_DIR}${NC}"
echo -e "${CYAN}  IAM groups      = ${OCI_IAM_SCHEMA_GROUP}, ${OCI_IAM_EMPLOYEE_GROUP}, ${OCI_IAM_MANAGER_GROUP}${NC}"
echo

echo -e "${YELLOW}Step 1: Creating or reusing Autonomous Database...${NC}"
echo -e "${CYAN}  Checking for existing ADB:${NC}"
show_cmd oci db autonomous-database list \
  --compartment-id "$ROOT_COMP_ID" \
  --all \
  --raw-output \
  --query "data[?\"db-name\"=='${DB_NAME}'].id | [0]"
ADB_OCID=$(oci db autonomous-database list \
  --compartment-id "$ROOT_COMP_ID" \
  --all \
  --raw-output \
  --query "data[?\"db-name\"=='${DB_NAME}'].id | [0]")

if [ -z "$ADB_OCID" ] || [ "$ADB_OCID" = "null" ]; then
  echo -e "${CYAN}  Creating ADB:${NC}"
  show_cmd oci db autonomous-database create \
    --compartment-id "$ROOT_COMP_ID" \
    --db-name "$DB_NAME" \
    --display-name "$DB_DISPLAY_NAME" \
    --is-free-tier true \
    --admin-password '<hidden>' \
    --cpu-core-count 1 \
    --data-storage-size-in-tbs 1 \
    --wait-for-state AVAILABLE
  oci db autonomous-database create \
    --compartment-id "$ROOT_COMP_ID" \
    --db-name "$DB_NAME" \
    --display-name "$DB_DISPLAY_NAME" \
    --is-free-tier true \
    --admin-password "$ADMIN_PWD" \
    --cpu-core-count 1 \
    --data-storage-size-in-tbs 1 \
    --wait-for-state AVAILABLE \
    >/dev/null

  ADB_OCID=$(oci db autonomous-database list \
    --compartment-id "$ROOT_COMP_ID" \
    --all \
    --raw-output \
    --query "data[?\"db-name\"=='${DB_NAME}'].id | [0]")
  echo -e "${CYAN}  Created ADB: ${ADB_OCID}${NC}"
else
  echo -e "${CYAN}  Reusing ADB: ${ADB_OCID}${NC}"
fi

echo
echo -e "${YELLOW}Step 2: Downloading wallet...${NC}"
mkdir -p "$WALLET_DIR"
show_cmd oci db autonomous-database generate-wallet \
  --autonomous-database-id "$ADB_OCID" \
  --password '<hidden>' \
  --file "${WALLET_DIR}/${DB_NAME}_wallet.zip"
oci db autonomous-database generate-wallet \
  --autonomous-database-id "$ADB_OCID" \
  --password "$WALLET_PWD" \
  --file "${WALLET_DIR}/${DB_NAME}_wallet.zip" \
  >/dev/null

(
  cd "$WALLET_DIR"
  unzip -oq "${DB_NAME}_wallet.zip"
)

if [ -f "${WALLET_DIR}/sqlnet.ora" ]; then
  echo -e "${CYAN}  Rewriting sqlnet.ora wallet directory to ${WALLET_DIR}:${NC}"
  show_cmd sed -i.bak-wallet-dir -E "s#DIRECTORY=\"?\\?\/network\/admin\"#DIRECTORY=\"${WALLET_DIR}\"#g" "${WALLET_DIR}/sqlnet.ora"
  sed -i.bak-wallet-dir -E "s#DIRECTORY=\"\\?/network/admin\"#DIRECTORY=\"${WALLET_DIR}\"#g" "${WALLET_DIR}/sqlnet.ora"
fi

echo
echo -e "${YELLOW}Step 3: Creating or reusing IAM groups for the lab...${NC}"

ensure_group() {
  local group_name="$1"
  local group_id

  echo -e "${CYAN}  Checking IAM group ${group_name}:${NC}" >&2
  show_cmd oci iam group list \
    --all \
    --raw-output \
    --query "data[?name=='${group_name}'].id | [0]" >&2
  group_id=$(oci iam group list \
    --all \
    --raw-output \
    --query "data[?name=='${group_name}'].id | [0]" 2>/dev/null || true)

  if [ -z "$group_id" ] || [ "$group_id" = "null" ]; then
    if [ -z "$TENANCY_OCID" ]; then
      echo -e "${RED}ERROR: TENANCY_OCID is not set and group ${group_name} does not exist.${NC}" >&2
      echo "Set TENANCY_OCID to the tenancy OCID, then rerun this script." >&2
      exit 1
    fi
    echo -e "${CYAN}  Creating IAM group ${group_name}:${NC}" >&2
    show_cmd oci iam group create \
      --compartment-id "$TENANCY_OCID" \
      --name "$group_name" \
      --description "Deep Data Security ADB lab group ${group_name}" \
      --raw-output \
      --query 'data.id' >&2
    group_id=$(oci iam group create \
      --compartment-id "$TENANCY_OCID" \
      --name "$group_name" \
      --description "Deep Data Security ADB lab group ${group_name}" \
      --raw-output \
      --query 'data.id')
    echo -e "${CYAN}  Created group ${group_name}: ${group_id}${NC}" >&2
  else
    echo -e "${CYAN}  Reusing group ${group_name}: ${group_id}${NC}" >&2
  fi

  printf '%s' "$group_id"
}

ALL_DB_USERS_OCID=$(ensure_group "$OCI_IAM_SCHEMA_GROUP")
EMPLOYEES_OCID=$(ensure_group "$OCI_IAM_EMPLOYEE_GROUP")
MANAGERS_OCID=$(ensure_group "$OCI_IAM_MANAGER_GROUP")

ADB_LAB_USER_OCID="${ADB_LAB_USER_OCID:-${OCI_CS_USER_OCID:-}}"
ADB_LAB_USERNAME="${ADB_LAB_USERNAME:-}"

if [ -n "$ADB_LAB_USER_OCID" ]; then
  echo -e "${CYAN}  Resolving lab user name:${NC}"
  show_cmd oci iam user get \
    --user-id "$ADB_LAB_USER_OCID" \
    --raw-output \
    --query 'data.name'
  ADB_LAB_USERNAME=$(oci iam user get \
    --user-id "$ADB_LAB_USER_OCID" \
    --raw-output \
    --query 'data.name')

  add_user_to_group() {
    local group_id="$1"
    local group_name="$2"
    local already_member

    echo -e "${CYAN}  Checking ${ADB_LAB_USERNAME} membership in ${group_name}:${NC}"
    show_cmd oci iam group list-users \
      --group-id "$group_id" \
      --all \
      --raw-output \
      --query "data[?id=='${ADB_LAB_USER_OCID}'].id | [0]"
    already_member=$(oci iam group list-users \
      --group-id "$group_id" \
      --all \
      --raw-output \
      --query "data[?id=='${ADB_LAB_USER_OCID}'].id | [0]" 2>/dev/null || true)

    if [ -z "$already_member" ] || [ "$already_member" = "null" ]; then
      echo -e "${CYAN}  Adding ${ADB_LAB_USERNAME} to ${group_name}:${NC}"
      show_cmd oci iam group add-user \
        --group-id "$group_id" \
        --user-id "$ADB_LAB_USER_OCID"
      oci iam group add-user \
        --group-id "$group_id" \
        --user-id "$ADB_LAB_USER_OCID" \
        >/dev/null
      echo -e "${CYAN}  Added ${ADB_LAB_USERNAME} to ${group_name}${NC}"
    else
      echo -e "${CYAN}  ${ADB_LAB_USERNAME} is already in ${group_name}${NC}"
    fi
  }

  add_user_to_group "$ALL_DB_USERS_OCID" "$OCI_IAM_SCHEMA_GROUP"
  add_user_to_group "$EMPLOYEES_OCID" "$OCI_IAM_EMPLOYEE_GROUP"
  add_user_to_group "$MANAGERS_OCID" "$OCI_IAM_MANAGER_GROUP"
else
  echo -e "${YELLOW}  OCI_CS_USER_OCID was not set, so current-user group membership was skipped.${NC}"
  echo -e "${YELLOW}  Set ADB_LAB_USER_OCID and rerun this script if you want it to add a user to the lab groups.${NC}"
fi

cat > "$ENV_FILE" <<EOF
export OCI_COMPARTMENT='${OCI_COMPARTMENT}'
export ROOT_COMP_ID='${ROOT_COMP_ID}'
export DB_NAME='${DB_NAME}'
export DB_DISPLAY_NAME='${DB_DISPLAY_NAME}'
export ADB_OCID='${ADB_OCID}'
export ADB_SERVICE='${ADB_SERVICE}'
export ADMIN_PWD='${ADMIN_PWD}'
export WALLET_PWD='${WALLET_PWD}'
export WALLET_DIR='${WALLET_DIR}'
export TNS_ADMIN='${WALLET_DIR}'
export TENANCY_OCID='${TENANCY_OCID}'
export OCI_IAM_SCHEMA_GROUP='${OCI_IAM_SCHEMA_GROUP}'
export OCI_IAM_EMPLOYEE_GROUP='${OCI_IAM_EMPLOYEE_GROUP}'
export OCI_IAM_MANAGER_GROUP='${OCI_IAM_MANAGER_GROUP}'
export ALL_DB_USERS_OCID='${ALL_DB_USERS_OCID}'
export EMPLOYEES_OCID='${EMPLOYEES_OCID}'
export MANAGERS_OCID='${MANAGERS_OCID}'
export ADB_LAB_USER_OCID='${ADB_LAB_USER_OCID}'
export ADB_LAB_USERNAME='${ADB_LAB_USERNAME}'
EOF
chmod 600 "$ENV_FILE"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 0 Completed: ADB and Wallet Ready                                ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}Environment file: ${ENV_FILE}${NC}"
echo "Load it before continuing:"
echo "  source ./.adb-oci-iam.env"
echo
