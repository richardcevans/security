#!/bin/bash
# Build a Windows SQL*Plus client bundle for Microsoft Entra interactive login.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/lib_adb.sh"
require_adb_entra_env

BUNDLE_NAME="${BUNDLE_NAME:-adb-entra-id-client}"
BUNDLE_DIR="${SCRIPT_DIR}/${BUNDLE_NAME}"
BUNDLE_ZIP="${SCRIPT_DIR}/${BUNDLE_NAME}.zip"
DOWNLOAD_DIR="${HOME}/adb-entra-id-download"
DOWNLOAD_ZIP="${DOWNLOAD_DIR}/${BUNDLE_NAME}.zip"
TNSNAMES_FILE="${TNS_ADMIN}/tnsnames.ora"
ALIAS_NAME="${ADB_ENTRA_ALIAS:-hrdb_entra}"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 6: Prepare Windows SQL*Plus Client Bundle                        ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}TNS_ADMIN   = ${TNS_ADMIN}${NC}"
echo -e "${CYAN}ADB_SERVICE = ${ADB_SERVICE}${NC}"
echo -e "${CYAN}BUNDLE_ZIP  = ${BUNDLE_ZIP}${NC}"
echo -e "${CYAN}ALIAS_NAME  = ${ALIAS_NAME}${NC}"
echo

if [ ! -f "$TNSNAMES_FILE" ]; then
  echo -e "${RED}ERROR: ${TNSNAMES_FILE} was not found. Re-run ./01_setup_adb_entra_id.sh.${NC}"
  exit 1
fi

for cmd in python3 zip; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: ${cmd} is not available on PATH.${NC}"
    exit 1
  fi
done

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

if [ -e "$BUNDLE_ZIP" ] || [ -e "$DOWNLOAD_ZIP" ] || [ -d "$BUNDLE_DIR" ]; then
  echo -e "${YELLOW}Existing client bundle files found. This script will overwrite them.${NC}"
  echo -e "${YELLOW}  Recreate directory: ${BUNDLE_DIR}${NC}"
  echo -e "${YELLOW}  Overwrite ZIP:      ${BUNDLE_ZIP}${NC}"
  echo -e "${YELLOW}  Overwrite ZIP:      ${DOWNLOAD_ZIP}${NC}"
  echo
else
  echo -e "${CYAN}No existing client bundle files found. This script will create a new ZIP.${NC}"
  echo
fi

rm -rf "$BUNDLE_DIR" "$BUNDLE_ZIP"
mkdir -p "$BUNDLE_DIR"
cp -R "${TNS_ADMIN}/." "$BUNDLE_DIR/"

cp "$TNSNAMES_FILE" "${BUNDLE_DIR}/tnsnames.ora"
sed -i "/^${ALIAS_NAME}[[:space:]]*=/,/^$/d" "${BUNDLE_DIR}/tnsnames.ora"

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
} >> "${BUNDLE_DIR}/tnsnames.ora"

cat > "${BUNDLE_DIR}/run-marvin.ps1" <<'EOF'
$ErrorActionPreference = "Stop"
$ClientRoot = Split-Path -Parent $PSScriptRoot
$InstantClient = Get-ChildItem -Path $ClientRoot -Directory -Filter "instantclient_*" | Sort-Object Name -Descending | Select-Object -First 1
if (-not $InstantClient) {
  throw "Could not find instantclient_* under $ClientRoot. Unzip Instant Client Basic and SQL*Plus into C:\temp\oracle-client first."
}
$env:PATH = "$($InstantClient.FullName);$env:PATH"
$env:TNS_ADMIN = $PSScriptRoot
$Sqlnet = Join-Path $PSScriptRoot "sqlnet.ora"
$WalletPath = ($PSScriptRoot -replace "\\", "/")
(Get-Content $Sqlnet) -replace 'DIRECTORY\s*=\s*"[^"]*"', "DIRECTORY=`"$WalletPath`"" | Set-Content $Sqlnet
Write-Host "TNS_ADMIN=$env:TNS_ADMIN"
Get-Command sqlplus.exe
sqlplus -L /@hrdb_entra
if ($LASTEXITCODE -ne 0) {
  Write-Host ""
  Write-Host "SQL*Plus launched Entra ID login but the database rejected the token."
  Write-Host "Re-run ./05_verify_db_setup.sh in Oracle Cloud Shell, then recreate and redownload this client bundle."
  exit $LASTEXITCODE
}
EOF

cat > "${BUNDLE_DIR}/run-emma.ps1" <<'EOF'
$ErrorActionPreference = "Stop"
$ClientRoot = Split-Path -Parent $PSScriptRoot
$InstantClient = Get-ChildItem -Path $ClientRoot -Directory -Filter "instantclient_*" | Sort-Object Name -Descending | Select-Object -First 1
if (-not $InstantClient) {
  throw "Could not find instantclient_* under $ClientRoot. Unzip Instant Client Basic and SQL*Plus into C:\temp\oracle-client first."
}
$env:PATH = "$($InstantClient.FullName);$env:PATH"
$env:TNS_ADMIN = $PSScriptRoot
$Sqlnet = Join-Path $PSScriptRoot "sqlnet.ora"
$WalletPath = ($PSScriptRoot -replace "\\", "/")
(Get-Content $Sqlnet) -replace 'DIRECTORY\s*=\s*"[^"]*"', "DIRECTORY=`"$WalletPath`"" | Set-Content $Sqlnet
Write-Host "TNS_ADMIN=$env:TNS_ADMIN"
Get-Command sqlplus.exe
sqlplus -L /@hrdb_entra
if ($LASTEXITCODE -ne 0) {
  Write-Host ""
  Write-Host "SQL*Plus launched Entra ID login but the database rejected the token."
  Write-Host "Re-run ./05_verify_db_setup.sh in Oracle Cloud Shell, then recreate and redownload this client bundle."
  exit $LASTEXITCODE
}
EOF

cat > "${BUNDLE_DIR}/README-WINDOWS.txt" <<EOF
ADB Microsoft Entra ID Windows client bundle

1. Save adb-entra-id-client.zip as C:\temp\oracle-client\adb-entra-id-client.zip.
2. Unzip adb-entra-id-client.zip into C:\temp\oracle-client.
3. Unzip Oracle Instant Client Basic and SQL*Plus into C:\temp\oracle-client.
4. In PowerShell:

   cd C:\temp\oracle-client\${BUNDLE_NAME}
   .\run-marvin.ps1

SQL*Plus uses TOKEN_AUTH=AZURE_INTERACTIVE and should open your local browser.
Sign in as the expected Microsoft Entra user.
EOF

(
  cd "$SCRIPT_DIR"
  zip -qr "$BUNDLE_ZIP" "$BUNDLE_NAME"
)

mkdir -p "$DOWNLOAD_DIR"
cp "$BUNDLE_ZIP" "$DOWNLOAD_ZIP"

echo -e "${GREEN}Created Windows client bundle:${NC}"
echo -e "${CYAN}  ${DOWNLOAD_ZIP}${NC}"
echo -e "${GREEN}This ZIP overwrites any previous ${DOWNLOAD_ZIP} from this lab.${NC}"
echo
echo "In Oracle Cloud Shell, use Menu > Download and enter:"
echo "  adb-entra-id-download/${BUNDLE_NAME}.zip"
echo
echo "Save it on Windows to:"
echo "  C:\\temp\\oracle-client\\${BUNDLE_NAME}.zip"
echo "If Windows says the file already exists, replace it."
echo
