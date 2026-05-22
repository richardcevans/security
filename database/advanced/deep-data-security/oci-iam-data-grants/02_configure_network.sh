#!/bin/bash
# =========================================================================================
# Script Name : 02_configure_network.sh
#
# Parameter   : None (uses environment variables)
#
# Notes       : Task 2 - Configure TCPS listener, sqlnet.ora, and tnsnames.ora.
#               Creates wallet, configures TLS, and adds an OAuth2 token
#               connection descriptor for OCI IAM authentication.
#
# Environment : PDB_NAME        - Pluggable database name and service name (default: FREEPDB1)
#               SECRET_PWD      - Wallet password (default: WalletPasswd123)
#               OCI_DOMAIN_URL  - OCI IAM identity domain URL
#               OCI_CLIENT_ID   - Interactive/client app client ID
#               OCI_AUDIENCE    - OAuth audience (default: OracleDB)
#               OCI_SCOPE       - OAuth scope (default: OracleDBDB_ACCESS_SCOPE)
#               OCI_TOKEN_AUTH  - Client token auth mode (default: OAUTH)
#               OCI_TOKEN_DIR   - Directory containing OAuth2 token file
# =========================================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 2: Configure TCPS Listener, sqlnet.ora, and tnsnames.ora         ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

export PDB_NAME="${PDB_NAME:-FREEPDB1}"
export DB_SID="${DB_SID:-FREE}"
export ORACLE_SID="$DB_SID"
export SECRET_PWD="${SECRET_PWD:-WalletPasswd123}"
export WALLET_DIR="${ORACLE_BASE}/admin/${ORACLE_SID}/wallet"
export OCI_AUDIENCE="${OCI_AUDIENCE:-OracleDB}"
export OCI_SCOPE="${OCI_SCOPE:-OracleDBDB_ACCESS_SCOPE}"
export OCI_TOKEN_AUTH="${OCI_TOKEN_AUTH:-OAUTH}"
export OCI_TOKEN_DIR="${OCI_TOKEN_DIR:-$HOME/.oci/oci-iam-data-grants}"

if [ -z "${OCI_DOMAIN_URL:-}" ]; then
    echo -e "${RED}ERROR: OCI_DOMAIN_URL is not set.${NC}"
    echo -e "${YELLOW}Run ./00_setup_oci_iam.sh and source ./.oci-iam-data-grants.env first.${NC}"
    exit 1
fi

if [ -z "${OCI_CLIENT_ID:-}" ]; then
    echo -e "${RED}ERROR: OCI_CLIENT_ID is not set.${NC}"
    echo -e "${YELLOW}Run ./00_setup_oci_iam.sh and source ./.oci-iam-data-grants.env first.${NC}"
    exit 1
fi

FQDN=$(hostname -f)
CERT_DN="CN=${FQDN},O=DBSecLab,C=US"
NETWORK_ADMIN="${ORACLE_HOME}/network/admin"
LISTENER_ORA="${NETWORK_ADMIN}/listener.ora"
SQLNET_ORA="${NETWORK_ADMIN}/sqlnet.ora"
TNSNAMES_ORA="${NETWORK_ADMIN}/tnsnames.ora"

TCP_LISTENER_ADDRESS=""
if [ -f "$LISTENER_ORA" ]; then
    TCP_LISTENER_ADDRESS=$(awk '
        tolower($0) ~ /protocol[[:space:]]*=[[:space:]]*tcp[)][[:space:]]*/ && tolower($0) ~ /port[[:space:]]*=/ {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            sub(/[[:space:]]*$/, "", line)
            print line
            exit
        }
    ' "$LISTENER_ORA")
fi
if [ -z "$TCP_LISTENER_ADDRESS" ]; then
    TCP_LISTENER_ADDRESS="(ADDRESS = (PROTOCOL = TCP)(HOST = ${FQDN})(PORT = 1521))"
    echo -e "${YELLOW}WARNING: Could not find an existing TCP listener address in ${LISTENER_ORA}.${NC}"
    echo -e "${YELLOW}         Falling back to ${TCP_LISTENER_ADDRESS}.${NC}"
fi
TCPS_LISTENER_ADDRESS="(ADDRESS = (PROTOCOL = TCPS)(HOST = ${FQDN})(PORT = 2484))"

echo -e "${PURPLE}Configuration:${NC}"
echo -e "${CYAN}  WALLET_DIR      = ${WALLET_DIR}${NC}"
echo -e "${CYAN}  ORACLE_SID      = ${ORACLE_SID}${NC}"
echo -e "${CYAN}  FQDN            = ${FQDN}${NC}"
echo -e "${CYAN}  CERT_DN         = ${CERT_DN}${NC}"
echo -e "${CYAN}  PDB_NAME        = ${PDB_NAME}${NC}"
echo -e "${CYAN}  OCI_DOMAIN_URL  = ${OCI_DOMAIN_URL}${NC}"
echo -e "${CYAN}  OCI_CLIENT_ID   = ${OCI_CLIENT_ID}${NC}"
echo -e "${CYAN}  OCI_AUDIENCE    = ${OCI_AUDIENCE}${NC}"
echo -e "${CYAN}  OCI_SCOPE       = ${OCI_SCOPE}${NC}"
echo -e "${CYAN}  OCI_TOKEN_AUTH  = ${OCI_TOKEN_AUTH}${NC}"
echo -e "${CYAN}  OCI_TOKEN_DIR   = ${OCI_TOKEN_DIR}${NC}"
echo -e "${CYAN}  TCP_ADDR        = ${TCP_LISTENER_ADDRESS}${NC}"
echo -e "${CYAN}  TCPS_ADDR       = ${TCPS_LISTENER_ADDRESS}${NC}"
echo

echo -e "${YELLOW}Step 1: Creating wallet directory and certificate...${NC}"

if [ -d "$WALLET_DIR" ] && [ -f "$WALLET_DIR/cwallet.sso" ]; then
    echo -e "${CYAN}  Wallet already exists at ${WALLET_DIR} — skipping creation.${NC}"
else
    mkdir -vp "$WALLET_DIR"

    orapki wallet create -wallet "$WALLET_DIR" -auto_login -pwd "$SECRET_PWD"
    orapki wallet add -wallet "$WALLET_DIR" -pwd "$SECRET_PWD" -dn "$CERT_DN" -keysize 2048 -self_signed -validity 3650
    orapki wallet export -wallet "$WALLET_DIR" -pwd "$SECRET_PWD" -dn "$CERT_DN" -cert "$WALLET_DIR/server_cert.pem"
    orapki wallet add -wallet "$WALLET_DIR" -pwd "$SECRET_PWD" -trusted_cert -cert "$WALLET_DIR/server_cert.pem" 2>/dev/null

    echo -e "${CYAN}  Wallet created and self-signed certificate added.${NC}"
fi

echo

echo -e "${YELLOW}Step 2: Configuring listener.ora...${NC}"
cp -vp "$LISTENER_ORA" "${LISTENER_ORA}.bak" 2>/dev/null

cat > "$LISTENER_ORA" <<EOF
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      ${TCP_LISTENER_ADDRESS}
      ${TCPS_LISTENER_ADDRESS}
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

echo -e "${YELLOW}Step 3: Configuring sqlnet.ora...${NC}"
cp -vp "$SQLNET_ORA" "${SQLNET_ORA}.bak" 2>/dev/null

cat > "$SQLNET_ORA" <<EOF
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

echo -e "${YELLOW}Step 4: Adding hrdb entry to tnsnames.ora...${NC}"
cp -vp "$TNSNAMES_ORA" "${TNSNAMES_ORA}.bak" 2>/dev/null
sed -i '/^hrdb/,/^$/d' "$TNSNAMES_ORA" 2>/dev/null

cat >> "$TNSNAMES_ORA" <<EOF
hrdb =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCPS)(HOST = ${FQDN})(PORT = 2484))
    (SECURITY =
      (SSL_SERVER_DN_MATCH = YES)
      (SSL_SERVER_CERT_DN = "${CERT_DN}")
      (TOKEN_AUTH = ${OCI_TOKEN_AUTH})
      (TOKEN_LOCATION = "${OCI_TOKEN_DIR}")
    )
    (CONNECT_DATA =
      (SERVICE_NAME = ${PDB_NAME})
    )
  )
EOF

echo -e "${CYAN}  hrdb entry added to tnsnames.ora.${NC}"
echo

echo -e "${YELLOW}Step 5: Restarting listener and registering database...${NC}"
lsnrctl stop
lsnrctl start

sqlplus -s / as sysdba <<EOF
set serveroutput on
whenever sqlerror exit sql.sqlcode

BEGIN
  EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE ${PDB_NAME} OPEN';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -65019 THEN
      RAISE;
    END IF;
END;
/

ALTER SYSTEM SET local_listener =
  '(ADDRESS_LIST =
     ${TCP_LISTENER_ADDRESS}
     ${TCPS_LISTENER_ADDRESS}
   )'
  SCOPE = BOTH;

ALTER SYSTEM REGISTER;

ALTER SESSION SET CONTAINER = ${PDB_NAME};

ALTER SYSTEM SET local_listener =
  '(ADDRESS_LIST =
     ${TCP_LISTENER_ADDRESS}
     ${TCPS_LISTENER_ADDRESS}
   )'
  SCOPE = BOTH;

DECLARE
  service_missing EXCEPTION;
  PRAGMA EXCEPTION_INIT(service_missing, -44304);
BEGIN
  BEGIN
    DBMS_SERVICE.START_SERVICE('${PDB_NAME}');
  EXCEPTION
    WHEN service_missing THEN
      DBMS_SERVICE.CREATE_SERVICE(
        service_name => '${PDB_NAME}',
        network_name => '${PDB_NAME}'
      );
      DBMS_SERVICE.START_SERVICE('${PDB_NAME}');
    WHEN OTHERS THEN
      IF SQLCODE NOT IN (-44305, -44311) THEN
        RAISE;
      END IF;
  END;
END;
/

ALTER SYSTEM REGISTER;

ALTER SESSION SET CONTAINER = CDB\$ROOT;
ALTER SYSTEM REGISTER;

prompt
prompt Registered database services:
col name format a40
SELECT name FROM v\$services ORDER BY name;

exit;
EOF

echo

echo -e "${YELLOW}Step 6: Checking listener services and testing connectivity...${NC}"
echo
lsnrctl services | sed -n "/Service \\\"${PDB_NAME}\\\"/,/Service/p"
echo
tnsping hrdb

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 2 Completed: Network Configured for OCI IAM Authentication!      ${NC}"
echo -e "${GREEN}      Next: run 03_create_hr_schema.sh                                      ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
