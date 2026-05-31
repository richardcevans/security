#!/bin/bash
# Create or reuse an ADB-S 26ai instance and prepare the DEAL Deep Sec owner.
# Intended to run from OCI Cloud Shell or a client with OCI CLI and SQL*Plus.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deal-adb.env"
APP_ENV_FILE="${SCRIPT_DIR}/.env"

usage() {
  cat <<'EOF'
Usage:
  ./00_setup_adb.sh [compartment-name|compartment-ocid|root]

Creates or reuses an Autonomous Database Serverless 26ai instance, downloads
the wallet, creates DEEPSEC_ADMIN, grants the privileges required by this lab,
creates local Deep Sec end users linda and wendy, and writes .env for the
Python scripts.

Compartment selection:
  ROOT_COMP_ID       Direct compartment OCID. Highest priority.
  OCI_COMPARTMENT    Compartment name, compartment OCID, or root.
  argument           Same as OCI_COMPARTMENT.

Useful overrides:
  DB_NAME             Default: dealdeepsec<host-suffix>
  DB_DISPLAY_NAME     Default: DB_NAME
  DB_VERSION          Default: 26ai
  ADMIN_PWD           Default: Oracle123+Oracle123+
  WALLET_PWD          Default: Oracle123+
  WALLET_DIR          Default: $HOME/adb_wallet/$DB_NAME
  ADB_SERVICE         Default: ${DB_NAME}_low
  DEEPSEC_ADMIN_PWD   Default: Oracle123+DeepSec+
  LINDA_PWD           Default: Oracle123+Linda+
  WENDY_PWD           Default: Oracle123+Wendy+
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

read_oci_config_value() {
  local key="$1"
  local profile="${OCI_PROFILE:-${OCI_CLI_PROFILE:-DEFAULT}}"
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

ensure_safe_sql_password() {
  local name="$1"
  local value="$2"
  if [[ "$value" == *\"* ]] || [[ "$value" == *\'* ]] || [[ "$value" == *\$* ]] || [[ "$value" == *\\* ]]; then
    echo -e "${RED}ERROR: ${name} contains a quote, dollar sign, or backslash.${NC}" >&2
    echo -e "${YELLOW}Use a lab password without those characters for this setup script.${NC}" >&2
    exit 1
  fi
}

admin_sqlplus() {
  sqlplus -L -s "admin/${ADMIN_PWD}@${ADB_SERVICE}"
}

host_suffix() {
  local source_value
  source_value="$(hostname 2>/dev/null || printf deal)"
  printf '%s' "$source_value" | cksum | awk '{ printf "%06x", $1 % 16777216 }'
}

oci_global_args=()
[ -n "${OCI_CONFIG_FILE:-${OCI_CLI_CONFIG_FILE:-}}" ] && oci_global_args+=(--config-file "${OCI_CONFIG_FILE:-${OCI_CLI_CONFIG_FILE:-}}")
[ -n "${OCI_PROFILE:-${OCI_CLI_PROFILE:-}}" ] && oci_global_args+=(--profile "${OCI_PROFILE:-${OCI_CLI_PROFILE:-}}")

if ! command -v oci >/dev/null 2>&1; then
  echo -e "${RED}ERROR: OCI CLI is not available. Run this from OCI Cloud Shell or install OCI CLI.${NC}"
  exit 1
fi

if ! command -v sqlplus >/dev/null 2>&1; then
  echo -e "${RED}ERROR: SQL*Plus is not available in PATH.${NC}"
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo -e "${RED}ERROR: unzip is not available in PATH.${NC}"
  exit 1
fi

if ! oci iam region list "${oci_global_args[@]}" >/dev/null 2>&1; then
  echo -e "${RED}ERROR: OCI CLI cannot call OCI. Refresh Cloud Shell or check OCI CLI authentication.${NC}"
  exit 1
fi

if [ -z "${TENANCY_OCID:-${OCI_TENANCY:-}}" ]; then
  TENANCY_OCID="$(read_oci_config_value tenancy)"
else
  TENANCY_OCID="${TENANCY_OCID:-${OCI_TENANCY:-}}"
fi

if [ -z "${TENANCY_OCID:-}" ]; then
  echo -e "${RED}ERROR: Could not determine tenancy OCID.${NC}"
  echo -e "${YELLOW}Set TENANCY_OCID, OCI_TENANCY, or use an OCI CLI config with tenancy set.${NC}"
  exit 1
fi

export OCI_COMPARTMENT="${1:-${OCI_COMPARTMENT:-root}}"

if [ -z "${ROOT_COMP_ID:-}" ]; then
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
      "${oci_global_args[@]}" \
      --raw-output \
      --query "data[?name=='${OCI_COMPARTMENT}'].id | [0]")

    if [ -z "$ROOT_COMP_ID" ] || [ "$ROOT_COMP_ID" = "null" ]; then
      echo -e "${RED}ERROR: Could not find an accessible active compartment named ${OCI_COMPARTMENT}.${NC}"
      echo "Use root, a compartment OCID, or set OCI_COMPARTMENT to an accessible compartment name."
      exit 1
    fi
  fi
fi
export ROOT_COMP_ID

suffix=$(host_suffix)
export DB_NAME="${DB_NAME:-dealdeepsec${suffix}}"
export DB_DISPLAY_NAME="${DB_DISPLAY_NAME:-${DB_NAME}}"
export DB_VERSION="${DB_VERSION:-26ai}"
export ADMIN_PWD="${ADMIN_PWD:-Oracle123+Oracle123+}"
export WALLET_PWD="${WALLET_PWD:-Oracle123+}"
export WALLET_DIR="${WALLET_DIR:-$HOME/adb_wallet/${DB_NAME}}"
export ADB_SERVICE="${ADB_SERVICE:-${DB_NAME}_low}"
export TNS_ADMIN="${WALLET_DIR}"
export DEEPSEC_ADMIN_PWD="${DEEPSEC_ADMIN_PWD:-Oracle123+DeepSec+}"
export LINDA_PWD="${LINDA_PWD:-Oracle123+Linda+}"
export WENDY_PWD="${WENDY_PWD:-Oracle123+Wendy+}"

ensure_safe_sql_password "ADMIN_PWD" "$ADMIN_PWD"
ensure_safe_sql_password "WALLET_PWD" "$WALLET_PWD"
ensure_safe_sql_password "DEEPSEC_ADMIN_PWD" "$DEEPSEC_ADMIN_PWD"
ensure_safe_sql_password "LINDA_PWD" "$LINDA_PWD"
ensure_safe_sql_password "WENDY_PWD" "$WENDY_PWD"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 0: Create ADB-S and Prepare DEAL Deep Sec Admin                  ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}Configuration:${NC}"
echo -e "${CYAN}  OCI_COMPARTMENT = ${OCI_COMPARTMENT}${NC}"
echo -e "${CYAN}  ROOT_COMP_ID    = ${ROOT_COMP_ID}${NC}"
echo -e "${CYAN}  DB_NAME         = ${DB_NAME}${NC}"
echo -e "${CYAN}  DB_DISPLAY_NAME = ${DB_DISPLAY_NAME}${NC}"
echo -e "${CYAN}  DB_VERSION      = ${DB_VERSION}${NC}"
echo -e "${CYAN}  ADB_SERVICE     = ${ADB_SERVICE}${NC}"
echo -e "${CYAN}  WALLET_DIR      = ${WALLET_DIR}${NC}"
echo

echo -e "${YELLOW}Step 1: Creating or reusing Autonomous Database...${NC}"
show_cmd oci db autonomous-database list \
  --compartment-id "$ROOT_COMP_ID" \
  --lifecycle-state AVAILABLE \
  --all \
  --raw-output \
  --query "data[?\"db-name\"=='${DB_NAME}'].id | [0]"

ADB_OCID=$(oci db autonomous-database list \
  --compartment-id "$ROOT_COMP_ID" \
  --lifecycle-state AVAILABLE \
  --all \
  "${oci_global_args[@]}" \
  --raw-output \
  --query "data[?\"db-name\"=='${DB_NAME}'].id | [0]")
ADB_DB_VERSION=$(oci db autonomous-database list \
  --compartment-id "$ROOT_COMP_ID" \
  --lifecycle-state AVAILABLE \
  --all \
  "${oci_global_args[@]}" \
  --raw-output \
  --query "data[?\"db-name\"=='${DB_NAME}'].\"db-version\" | [0]")
ADB_ANY_STATE=$(oci db autonomous-database list \
  --compartment-id "$ROOT_COMP_ID" \
  --all \
  "${oci_global_args[@]}" \
  --raw-output \
  --query "data[?\"db-name\"=='${DB_NAME}'].\"lifecycle-state\" | [0]")

if [ -z "$ADB_OCID" ] || [ "$ADB_OCID" = "null" ]; then
  if [ -n "$ADB_ANY_STATE" ] && [ "$ADB_ANY_STATE" != "null" ]; then
    echo -e "${YELLOW}  Found ${DB_NAME} in lifecycle state ${ADB_ANY_STATE}; it is not reusable.${NC}"
  fi
  show_cmd oci db autonomous-database create \
    --compartment-id "$ROOT_COMP_ID" \
    --db-name "$DB_NAME" \
    --display-name "$DB_DISPLAY_NAME" \
    --db-version "$DB_VERSION" \
    --is-free-tier true \
    --admin-password '<hidden>' \
    --cpu-core-count 1 \
    --data-storage-size-in-tbs 1 \
    --wait-for-state AVAILABLE
  oci db autonomous-database create \
    --compartment-id "$ROOT_COMP_ID" \
    --db-name "$DB_NAME" \
    --display-name "$DB_DISPLAY_NAME" \
    --db-version "$DB_VERSION" \
    --is-free-tier true \
    --admin-password "$ADMIN_PWD" \
    --cpu-core-count 1 \
    --data-storage-size-in-tbs 1 \
    --wait-for-state AVAILABLE \
    "${oci_global_args[@]}" \
    >/dev/null

  ADB_OCID=$(oci db autonomous-database list \
    --compartment-id "$ROOT_COMP_ID" \
    --lifecycle-state AVAILABLE \
    --all \
    "${oci_global_args[@]}" \
    --raw-output \
    --query "data[?\"db-name\"=='${DB_NAME}'].id | [0]")
  ADB_DB_VERSION=$(oci db autonomous-database list \
    --compartment-id "$ROOT_COMP_ID" \
    --lifecycle-state AVAILABLE \
    --all \
    "${oci_global_args[@]}" \
    --raw-output \
    --query "data[?\"db-name\"=='${DB_NAME}'].\"db-version\" | [0]")
  echo -e "${CYAN}  Created ADB: ${ADB_OCID}${NC}"
else
  if [ "$ADB_DB_VERSION" != "$DB_VERSION" ]; then
    echo -e "${RED}ERROR: Found existing ADB ${DB_NAME}, but it is ${ADB_DB_VERSION}, not ${DB_VERSION}.${NC}"
    echo -e "${YELLOW}Use a different DB_NAME or create an Autonomous Database ${DB_VERSION}.${NC}"
    exit 1
  fi
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
  "${oci_global_args[@]}" \
  >/dev/null

(
  cd "$WALLET_DIR"
  unzip -oq "${DB_NAME}_wallet.zip"
)

if [ -f "${WALLET_DIR}/sqlnet.ora" ]; then
  sed -i.bak-wallet-dir -E "s#DIRECTORY=\"\\?/network/admin\"#DIRECTORY=\"${WALLET_DIR}\"#g" "${WALLET_DIR}/sqlnet.ora"
fi

echo
echo -e "${YELLOW}Step 3: Creating DEEPSEC_ADMIN and local Deep Sec users...${NC}"
show_cmd sqlplus -L -s "admin/<hidden>@${ADB_SERVICE}"

admin_sqlplus <<SQL
set echo on
set serveroutput on
set lines 180
whenever sqlerror exit sql.sqlcode

DECLARE
  user_missing EXCEPTION;
  PRAGMA EXCEPTION_INIT(user_missing, -1918);
BEGIN
  BEGIN
    EXECUTE IMMEDIATE 'CREATE USER deepsec_admin IDENTIFIED BY "${DEEPSEC_ADMIN_PWD}" DEFAULT TABLESPACE data QUOTA UNLIMITED ON data';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -1920 THEN
        EXECUTE IMMEDIATE 'ALTER USER deepsec_admin IDENTIFIED BY "${DEEPSEC_ADMIN_PWD}"';
        EXECUTE IMMEDIATE 'ALTER USER deepsec_admin QUOTA UNLIMITED ON data';
      ELSE
        RAISE;
      END IF;
  END;
END;
/

GRANT CREATE SESSION TO deepsec_admin;
GRANT CREATE TABLE TO deepsec_admin;
GRANT CREATE DATA ROLE TO deepsec_admin;
GRANT CREATE DATA GRANT TO deepsec_admin;
GRANT CREATE ANY DATA GRANT TO deepsec_admin;
GRANT ADMINISTER ANY DATA GRANT TO deepsec_admin;
GRANT GRANT ANY DATA ROLE TO deepsec_admin;
GRANT CREATE END USER TO deepsec_admin;
GRANT CREATE END USER SECURITY CONTEXT TO deepsec_admin;
GRANT SET USE DATA GRANTS ONLY TO deepsec_admin;

BEGIN
  EXECUTE IMMEDIATE 'CREATE END USER "linda" IDENTIFIED BY "${LINDA_PWD}"';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -1920 THEN
      EXECUTE IMMEDIATE 'ALTER END USER "linda" IDENTIFIED BY "${LINDA_PWD}"';
    ELSE
      RAISE;
    END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'CREATE END USER "wendy" IDENTIFIED BY "${WENDY_PWD}"';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -1920 THEN
      EXECUTE IMMEDIATE 'ALTER END USER "wendy" IDENTIFIED BY "${WENDY_PWD}"';
    ELSE
      RAISE;
    END IF;
END;
/

CREATE ROLE IF NOT EXISTS deal_direct_logon_role;
GRANT CREATE SESSION TO deal_direct_logon_role;
GRANT deal_direct_logon_role TO deepsec_admin WITH ADMIN OPTION;

exit;
SQL

cat > "$ENV_FILE" <<EOF
export OCI_COMPARTMENT='${OCI_COMPARTMENT}'
export ROOT_COMP_ID='${ROOT_COMP_ID}'
export DB_NAME='${DB_NAME}'
export DB_DISPLAY_NAME='${DB_DISPLAY_NAME}'
export DB_VERSION='${DB_VERSION}'
export ADB_OCID='${ADB_OCID}'
export ADB_SERVICE='${ADB_SERVICE}'
export ADMIN_PWD='${ADMIN_PWD}'
export WALLET_PWD='${WALLET_PWD}'
export WALLET_DIR='${WALLET_DIR}'
export TNS_ADMIN='${WALLET_DIR}'
export DEEPSEC_ADMIN_PWD='${DEEPSEC_ADMIN_PWD}'
export LINDA_PWD='${LINDA_PWD}'
export WENDY_PWD='${WENDY_PWD}'
EOF
chmod 600 "$ENV_FILE"

cat > "$APP_ENV_FILE" <<EOF
ADB_USERNAME=DEEPSEC_ADMIN
ADB_PASSWORD=${DEEPSEC_ADMIN_PWD}
ADB_DSN=${ADB_SERVICE}
ADB_WALLET_LOCATION=${WALLET_DIR}
ADB_WALLET_PASSPHRASE=${WALLET_PWD}

DEEPSEC_CONTEXT_MODE=direct_logon
DEEPSEC_DATABASE_ACCESS_TOKEN=
DEEPSEC_LINDA_IDENTITY=linda
DEEPSEC_LINDA_KEY=${LINDA_PWD}
DEEPSEC_WENDY_IDENTITY=wendy
DEEPSEC_WENDY_KEY=${WENDY_PWD}
DEAL_OBJECT_OWNER=DEEPSEC_ADMIN

DEAL_VECTOR_DIM=3
DEAL_VECTOR_METRIC=COSINE

OCI_CONFIG_FILE=~/.oci/config
OCI_PROFILE=DEFAULT
OCI_GENAI_ENDPOINT=https://inference.generativeai.us-chicago-1.oci.oraclecloud.com
OCI_GENAI_COMPARTMENT_ID=ocid1.compartment.oc1..replace-with-compartment-ocid
OCI_GENAI_MODEL_ID=ocid1.generativeaimodel.oc1.us-chicago-1.replace-with-model-ocid
EOF
chmod 600 "$APP_ENV_FILE"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 0 Completed: ADB-S and DEAL Deep Sec Admin Ready                 ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}Environment file: ${ENV_FILE}${NC}"
echo -e "${CYAN}Python app .env:  ${APP_ENV_FILE}${NC}"
echo
echo "Next:"
echo "  source ./.deal-adb.env"
echo "  python 01_verify_deepsec.py"
echo "  python 02_create_schema.py"
echo "  python 03_load_data.py"
echo "  python 04_configure_deepsec.py"
echo
