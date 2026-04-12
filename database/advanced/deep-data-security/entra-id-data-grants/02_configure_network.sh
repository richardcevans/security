#!/bin/bash
# =========================================================================================
# Script Name : 02_configure_network.sh
#
# Parameter   : None (uses environment variables)
#
# Notes       : Task 8 - Configure TCPS listener, sqlnet.ora, and tnsnames.ora.
#               Creates wallet, configures TLS, and adds AZURE_INTERACTIVE
#               connection descriptor for Entra ID browser-based authentication.
#
# Environment : APP_ID_URI   - Application ID URI
#               TENANT_ID    - Azure Directory (tenant) ID
#               CLIENT_ID    - Oracle Client Interactive Application ID
#               PDB_NAME     - Pluggable database name (default: pdb1)
#               SECRET_PWD   - Wallet password (default: WalletPasswd123)
#
# Modified by         Date         Change
# Oracle DB Security  04/02/2026   Creation
# =========================================================================================

# Define colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 8: Configure TCPS Listener, sqlnet.ora, and tnsnames.ora         ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"
export SECRET_PWD="${SECRET_PWD:-WalletPasswd123}"
export WALLET_DIR="${ORACLE_BASE}/admin/${ORACLE_SID}/wallet"

if [ -z "$APP_ID_URI" ]; then
    echo -e "${RED}ERROR: APP_ID_URI is not set.${NC}"
    exit 1
fi

if [ -z "$TENANT_ID" ]; then
    echo -e "${RED}ERROR: TENANT_ID is not set.${NC}"
    exit 1
fi

if [ -z "$CLIENT_ID" ]; then
    echo -e "${RED}ERROR: CLIENT_ID is not set.${NC}"
    echo -e "${YELLOW}  export CLIENT_ID=<oracle-client-interactive-app-id>${NC}"
    exit 1
fi

FQDN=$(hostname -f)
CERT_DN="CN=${FQDN},O=DBSecLab,C=US"

echo -e "${PURPLE}Configuration:${NC}"
echo -e "${CYAN}  WALLET_DIR = ${WALLET_DIR}${NC}"
echo -e "${CYAN}  FQDN       = ${FQDN}${NC}"
echo -e "${CYAN}  CERT_DN    = ${CERT_DN}${NC}"
echo -e "${CYAN}  CLIENT_ID  = ${CLIENT_ID}${NC}"
echo -e "${CYAN}  PDB_NAME   = ${PDB_NAME}${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Step 1: Create wallet (if it does not exist)
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
echo -e "${YELLOW}Step 1: Creating wallet directory and certificate...${NC}"

if [ -d "$WALLET_DIR" ] && [ -f "$WALLET_DIR/cwallet.sso" ]; then
    echo -e "${CYAN}  Wallet already exists at ${WALLET_DIR} — skipping creation.${NC}"
else
    mkdir -vp "$WALLET_DIR"

    orapki wallet create \
        -wallet "$WALLET_DIR" \
        -auto_login \
        -pwd "$SECRET_PWD"

    orapki wallet add \
        -wallet "$WALLET_DIR" \
        -pwd "$SECRET_PWD" \
        -dn "$CERT_DN" \
        -keysize 2048 \
        -self_signed \
        -validity 3650

    orapki wallet export \
        -wallet "$WALLET_DIR" \
        -pwd "$SECRET_PWD" \
        -dn "$CERT_DN" \
        -cert "$WALLET_DIR/server_cert.pem"

    orapki wallet add \
        -wallet "$WALLET_DIR" \
        -pwd "$SECRET_PWD" \
        -trusted_cert \
        -cert "$WALLET_DIR/server_cert.pem" 2>/dev/null

    echo -e "${CYAN}  Wallet created and self-signed certificate added.${NC}"
fi

echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Step 2: Configure listener.ora
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
echo -e "${YELLOW}Step 2: Configuring listener.ora...${NC}"

cp -vp "$ORACLE_HOME/network/admin/listener.ora" \
       "$ORACLE_HOME/network/admin/listener.ora.bak" 2>/dev/null

cat > "$ORACLE_HOME/network/admin/listener.ora" <<EOF
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = ${FQDN})(PORT = 1521))
      (ADDRESS = (PROTOCOL = TCPS)(HOST = ${FQDN})(PORT = 2484))
    )
  )

WALLET_LOCATION =
  (SOURCE =
    (METHOD = FILE)
    (METHOD_DATA =
      (DIRECTORY = ${WALLET_DIR})
    )
  )

SSL_CLIENT_AUTHENTICATION = FALSE

EOF

echo -e "${CYAN}  listener.ora updated.${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Step 3: Configure sqlnet.ora
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
echo -e "${YELLOW}Step 3: Configuring sqlnet.ora...${NC}"

cp -vp "$ORACLE_HOME/network/admin/sqlnet.ora" \
       "$ORACLE_HOME/network/admin/sqlnet.ora.bak" 2>/dev/null

cat > "$ORACLE_HOME/network/admin/sqlnet.ora" <<EOF
WALLET_LOCATION =
  (SOURCE =
    (METHOD = FILE)
    (METHOD_DATA =
      (DIRECTORY = ${WALLET_DIR})
    )
  )

SSL_CLIENT_AUTHENTICATION = FALSE
SSL_VERSION = 1.2

EOF

echo -e "${CYAN}  sqlnet.ora updated.${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Step 4: Add hrdb to tnsnames.ora
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
echo -e "${YELLOW}Step 4: Adding hrdb entry to tnsnames.ora...${NC}"

cp -vp "$ORACLE_HOME/network/admin/tnsnames.ora" \
       "$ORACLE_HOME/network/admin/tnsnames.ora.bak" 2>/dev/null

# Remove existing hrdb entry if present
sed -i '/^hrdb/,/^$/d' "$ORACLE_HOME/network/admin/tnsnames.ora" 2>/dev/null

cat >> "$ORACLE_HOME/network/admin/tnsnames.ora" <<EOF
hrdb =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCPS)(HOST = ${FQDN})(PORT = 2484))
    (SECURITY =
      (SSL_SERVER_DN_MATCH = YES)
      (SSL_SERVER_CERT_DN = "${CERT_DN}")
      (TOKEN_AUTH = AZURE_INTERACTIVE)
      (CLIENT_ID = ${CLIENT_ID})
      (AZURE_DB_APP_ID_URI = ${APP_ID_URI})
      (TENANT_ID = ${TENANT_ID})
    )
    (CONNECT_DATA =
      (SERVICE_NAME = ${PDB_NAME})
    )
  )
EOF

echo -e "${CYAN}  hrdb entry added to tnsnames.ora.${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Step 5: Restart listener and register database
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
echo -e "${YELLOW}Step 5: Restarting listener and registering database...${NC}"

lsnrctl stop
lsnrctl start

sqlplus -s / as sysdba <<EOF
ALTER SYSTEM REGISTER;
exit;
EOF

echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Step 6: Test connectivity
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
echo -e "${YELLOW}Step 6: Testing connectivity with tnsping...${NC}"
echo

tnsping hrdb

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 8 Completed: Network Configured!                                 ${NC}"
echo -e "${GREEN}      TCPS listener on port 2484, hrdb entry with AZURE_INTERACTIVE.         ${NC}"
echo -e "${GREEN}      Next: run 03_create_hr_schema.sh                                      ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
