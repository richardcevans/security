#!/bin/bash
# ---------------------------------------------------------------------------
# Script Name : export_server_cert_for_client.sh
# Description : Export the database TCPS server certificate for a client
#               SQLcl / VS Code / Oracle client trust store.
# Author      : Oracle Database Security Product Management
# Notes       : Run on the DBSec-Lab VM after 02_configure_network.sh.
# ---------------------------------------------------------------------------

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.entra-id-data-grants.env"

if [ -f "$ENV_FILE" ]; then
  # Load the lab app IDs so the generated client TNS snippet is ready to use.
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

export DB_SID="${DB_SID:-FREE}"
export ORACLE_SID="$DB_SID"
export PDB_NAME="${PDB_NAME:-FREEPDB1}"
export SECRET_PWD="${SECRET_PWD:-WalletPasswd123}"
export ORACLE_BASE="${ORACLE_BASE:-/opt/oracle}"
export WALLET_DIR="${WALLET_DIR:-${ORACLE_BASE}/admin/${ORACLE_SID}/wallet}"
export TCPS_PORT="${TCPS_PORT:-2484}"
export CLIENT_BUNDLE_DIR="${CLIENT_BUNDLE_DIR:-${SCRIPT_DIR}/client-trust}"
export TRUSTSTORE_PASSWORD="${TRUSTSTORE_PASSWORD:-WalletPasswd123}"

FQDN="${DB_HOSTNAME:-$(hostname -f)}"
CERT_DN="${CERT_DN:-CN=${FQDN},O=DBSecLab,C=US}"
CLIENT_ID_VALUE="${CLIENT_ID:-<client-id>}"
APP_ID_URI_VALUE="${APP_ID_URI:-<app-id-uri>}"
TENANT_ID_VALUE="${TENANT_ID:-<tenant-id>}"
SERVER_CERT="${CLIENT_BUNDLE_DIR}/db_server_cert.pem"
ORACLE_CLIENT_WALLET_DIR="${CLIENT_BUNDLE_DIR}/oracle_client_wallet"
TRUSTSTORE="${CLIENT_BUNDLE_DIR}/db_server_truststore.p12"
TNS_SNIPPET="${CLIENT_BUNDLE_DIR}/tnsnames-client-snippet.ora"
README_FILE="${CLIENT_BUNDLE_DIR}/README-client-trust.txt"
ZIP_FILE="${SCRIPT_DIR}/entra-id-data-grants-client-trust.zip"

echo -e "${GREEN}=========================================================================${NC}"
echo -e "${GREEN}      Export Database Server Certificate for Client Trust                  ${NC}"
echo -e "${GREEN}=========================================================================${NC}"
echo

echo -e "${PURPLE}Configuration:${NC}"
echo -e "${CYAN}  WALLET_DIR          = ${WALLET_DIR}${NC}"
echo -e "${CYAN}  FQDN                = ${FQDN}${NC}"
echo -e "${CYAN}  CERT_DN             = ${CERT_DN}${NC}"
echo -e "${CYAN}  CLIENT_ID           = ${CLIENT_ID_VALUE}${NC}"
echo -e "${CYAN}  APP_ID_URI          = ${APP_ID_URI_VALUE}${NC}"
echo -e "${CYAN}  TENANT_ID           = ${TENANT_ID_VALUE}${NC}"
echo -e "${CYAN}  CLIENT_BUNDLE_DIR   = ${CLIENT_BUNDLE_DIR}${NC}"
echo -e "${CYAN}  TRUSTSTORE_PASSWORD = ${TRUSTSTORE_PASSWORD}${NC}"
echo

if [ ! -d "$WALLET_DIR" ]; then
  echo -e "${RED}ERROR: Wallet directory does not exist: ${WALLET_DIR}${NC}"
  echo -e "${YELLOW}Run ./02_configure_network.sh first, then rerun this script.${NC}"
  exit 1
fi

if ! command -v orapki >/dev/null 2>&1; then
  echo -e "${RED}ERROR: orapki was not found in PATH.${NC}"
  echo -e "${YELLOW}Set ORACLE_HOME and PATH for the Oracle database home, then rerun.${NC}"
  exit 1
fi

mkdir -p "$CLIENT_BUNDLE_DIR"

echo -e "${YELLOW}Step 1: Exporting the database server certificate...${NC}"
orapki wallet export \
  -wallet "$WALLET_DIR" \
  -pwd "$SECRET_PWD" \
  -dn "$CERT_DN" \
  -cert "$SERVER_CERT"

echo -e "${CYAN}  Exported: ${SERVER_CERT}${NC}"
echo

echo -e "${YELLOW}Step 2: Creating an Oracle client trust wallet for Instant Client...${NC}"
rm -rf "$ORACLE_CLIENT_WALLET_DIR"
mkdir -p "$ORACLE_CLIENT_WALLET_DIR"

orapki wallet create \
  -wallet "$ORACLE_CLIENT_WALLET_DIR" \
  -auto_login \
  -pwd "$TRUSTSTORE_PASSWORD"

orapki wallet add \
  -wallet "$ORACLE_CLIENT_WALLET_DIR" \
  -pwd "$TRUSTSTORE_PASSWORD" \
  -trusted_cert \
  -cert "$SERVER_CERT"

echo -e "${CYAN}  Created: ${ORACLE_CLIENT_WALLET_DIR}${NC}"
echo -e "${CYAN}  Copy this directory to a client that does not have orapki.${NC}"
echo

echo -e "${YELLOW}Step 3: Creating an optional PKCS12 truststore for SQLcl / JDBC clients...${NC}"
if command -v keytool >/dev/null 2>&1; then
  rm -f "$TRUSTSTORE"
  keytool -importcert \
    -alias entra-id-data-grants-db \
    -file "$SERVER_CERT" \
    -keystore "$TRUSTSTORE" \
    -storetype PKCS12 \
    -storepass "$TRUSTSTORE_PASSWORD" \
    -noprompt >/dev/null
  echo -e "${CYAN}  Created: ${TRUSTSTORE}${NC}"
else
  echo -e "${YELLOW}  keytool was not found; skipping PKCS12 truststore creation.${NC}"
  echo -e "${YELLOW}  Copy ${SERVER_CERT} to your client and import it into the client trust store.${NC}"
fi
echo

echo -e "${YELLOW}Step 4: Writing client connection notes...${NC}"
cat > "$TNS_SNIPPET" <<EOF
hrdb_client =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCPS)(HOST = ${FQDN})(PORT = ${TCPS_PORT}))
    (SECURITY =
      (SSL_SERVER_DN_MATCH = YES)
      (SSL_SERVER_CERT_DN = "${CERT_DN}")
      (TOKEN_AUTH = AZURE_INTERACTIVE)
      (CLIENT_ID = ${CLIENT_ID_VALUE})
      (AZURE_DB_APP_ID_URI = ${APP_ID_URI_VALUE})
      (TENANT_ID = ${TENANT_ID_VALUE})
    )
    (CONNECT_DATA =
      (SERVICE_NAME = ${PDB_NAME})
    )
  )
EOF

cat > "$README_FILE" <<EOF
Oracle client trust files
=========================

This bundle contains the database server certificate exported from:

  ${WALLET_DIR}

The certificate subject is:

  ${CERT_DN}

Use this certificate as the trust anchor on your client. This is one-way TLS:

  - the client trusts this database server certificate
  - the database does not request a client certificate
  - SSL_SERVER_DN_MATCH stays set to YES

Files:

  db_server_cert.pem
    The PEM certificate to import into a client wallet or trust store.

  oracle_client_wallet/
    Ready-to-copy Oracle client trust wallet for Instant Client systems that
    do not have orapki. It contains cwallet.sso and ewallet.p12 with the lab
    database server certificate as a trusted certificate.

  db_server_truststore.p12
    Optional PKCS12 truststore created with keytool, if keytool was available.
    Password: ${TRUSTSTORE_PASSWORD}

  tnsnames-client-snippet.ora
    Example TCPS connect descriptor for a client using this lab database.

For Oracle Instant Client without orapki:

  1. Copy oracle_client_wallet to your client machine.
  2. Point sqlnet.ora at that wallet directory.
  3. Keep SSL_SERVER_DN_MATCH=YES.

Example sqlnet.ora:

  WALLET_LOCATION =
    (SOURCE =
      (METHOD = FILE)
      (METHOD_DATA =
        (DIRECTORY = C:\\oracle\\tns_admin\\oracle_client_wallet)
      )
    )

  SSL_CLIENT_AUTHENTICATION = FALSE
  SSL_SERVER_DN_MATCH = YES

Example SQLcl Java truststore properties on Windows:

  set JAVA_TOOL_OPTIONS=-Djavax.net.ssl.trustStore=C:\\path\\to\\db_server_truststore.p12 -Djavax.net.ssl.trustStorePassword=${TRUSTSTORE_PASSWORD} -Djavax.net.ssl.trustStoreType=PKCS12

Example SQLcl Java truststore properties on Linux or macOS:

  export JAVA_TOOL_OPTIONS="-Djavax.net.ssl.trustStore=/path/to/db_server_truststore.p12 -Djavax.net.ssl.trustStorePassword=${TRUSTSTORE_PASSWORD} -Djavax.net.ssl.trustStoreType=PKCS12"

Then connect using a TCPS descriptor that includes:

  SSL_SERVER_DN_MATCH=YES
  SSL_SERVER_CERT_DN="${CERT_DN}"
  TOKEN_AUTH=AZURE_INTERACTIVE

EOF

echo -e "${CYAN}  Wrote: ${TNS_SNIPPET}${NC}"
echo -e "${CYAN}  Wrote: ${README_FILE}${NC}"
echo

echo -e "${YELLOW}Step 5: Packaging the client trust bundle...${NC}"
rm -f "$ZIP_FILE"
if command -v zip >/dev/null 2>&1; then
  (cd "$SCRIPT_DIR" && zip -qr "$(basename "$ZIP_FILE")" "$(basename "$CLIENT_BUNDLE_DIR")")
  echo -e "${CYAN}  Created: ${ZIP_FILE}${NC}"
else
  echo -e "${YELLOW}  zip was not found; copy the directory instead:${NC}"
  echo -e "${YELLOW}  ${CLIENT_BUNDLE_DIR}${NC}"
fi

echo
echo -e "${GREEN}=========================================================================${NC}"
echo -e "${GREEN}      Export Complete                                                     ${NC}"
echo -e "${GREEN}=========================================================================${NC}"
echo -e "${CYAN}Copy this file or directory to your client:${NC}"
if [ -f "$ZIP_FILE" ]; then
  echo -e "${CYAN}  ${ZIP_FILE}${NC}"
else
  echo -e "${CYAN}  ${CLIENT_BUNDLE_DIR}${NC}"
fi
echo
