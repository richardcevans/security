#!/bin/bash
# Configure the ADB wallet tnsnames.ora for Microsoft Entra ID interactive login.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/lib_adb.sh"
require_adb_entra_env

TNSNAMES_FILE="${TNS_ADMIN}/tnsnames.ora"
ALIAS_NAME="${ADB_ENTRA_ALIAS:-hrdb_entra}"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 4: Configure ADB Wallet for Entra ID Interactive Login           ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}TNS_ADMIN   = ${TNS_ADMIN}${NC}"
echo -e "${CYAN}ADB_SERVICE = ${ADB_SERVICE}${NC}"
echo -e "${CYAN}ALIAS_NAME  = ${ALIAS_NAME}${NC}"
echo

if [ ! -f "$TNSNAMES_FILE" ]; then
  echo -e "${RED}ERROR: ${TNSNAMES_FILE} was not found. Re-run ./00_setup_adb_entra_id.sh.${NC}"
  exit 1
fi

base_descriptor=$(python3 - "$TNSNAMES_FILE" "$ADB_SERVICE" <<'PY'
import re
import sys

path, alias = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
match = re.search(rf"(?im)^\s*{re.escape(alias)}\s*=", text)
if not match:
    sys.exit(0)

start = match.start()
first_paren = text.find("(", match.end())
if first_paren < 0:
    sys.exit(0)

depth = 0
end = first_paren
for pos in range(first_paren, len(text)):
    ch = text[pos]
    if ch == "(":
        depth += 1
    elif ch == ")":
        depth -= 1
        if depth == 0:
            end = pos + 1
            break

print(text[start:end])
PY
)

if [ -z "$base_descriptor" ]; then
  echo -e "${RED}ERROR: Could not find ${ADB_SERVICE} in ${TNSNAMES_FILE}.${NC}"
  exit 1
fi

parsed=$(BASE_DESCRIPTOR="$base_descriptor" python3 -c '
import os
import re

text = os.environ["BASE_DESCRIPTOR"]

def value(name):
    match = re.search(r"\(\s*" + re.escape(name) + r"\s*=\s*(\"[^\"]*\"|[^)\s]+)", text, re.I)
    if not match:
        return ""
    value = match.group(1)
    if value.startswith("\"") and value.endswith("\""):
        value = value[1:-1]
    return value

print(value("host"))
print(value("port"))
print(value("service_name"))
print(value("ssl_server_cert_dn"))
')
host=$(printf '%s\n' "$parsed" | sed -n '1p')
port=$(printf '%s\n' "$parsed" | sed -n '2p')
service_name=$(printf '%s\n' "$parsed" | sed -n '3p')
ssl_dn=$(printf '%s\n' "$parsed" | sed -n '4p')

if [ -z "$host" ] || [ -z "$port" ] || [ -z "$service_name" ]; then
  echo -e "${RED}ERROR: Could not parse host, port, or service_name from ${ADB_SERVICE}.${NC}"
  exit 1
fi

cp "$TNSNAMES_FILE" "${TNSNAMES_FILE}.bak-entra"
sed -i "/^${ALIAS_NAME}[[:space:]]*=/,/^$/d" "$TNSNAMES_FILE"

{
  echo
  echo "${ALIAS_NAME} ="
  echo "  (DESCRIPTION ="
  echo "    (ADDRESS = (PROTOCOL = TCPS)(HOST = ${host})(PORT = ${port}))"
  echo "    (SECURITY ="
  echo "      (SSL_SERVER_DN_MATCH = YES)"
  if [ -n "$ssl_dn" ]; then
    echo "      (SSL_SERVER_CERT_DN = \"${ssl_dn}\")"
  fi
  echo "      (TOKEN_AUTH = AZURE_INTERACTIVE)"
  echo "      (CLIENT_ID = ${CLIENT_ID})"
  echo "      (AZURE_DB_APP_ID_URI = ${APP_ID_URI})"
  echo "      (TENANT_ID = ${TENANT_ID})"
  echo "    )"
  echo "    (CONNECT_DATA ="
  echo "      (SERVICE_NAME = ${service_name})"
  echo "    )"
  echo "  )"
} >> "$TNSNAMES_FILE"

echo -e "${CYAN}Added ${ALIAS_NAME} to ${TNSNAMES_FILE}.${NC}"
echo
echo -e "${GREEN}Task 4 completed. Next: run ./05_verify_as_marvin.sh${NC}"
echo
