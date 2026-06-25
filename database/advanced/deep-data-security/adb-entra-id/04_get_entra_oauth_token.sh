#!/bin/bash
# Configure the ADB wallet for Microsoft Entra OAuth2 auth and get a user token.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/lib_adb.sh"
require_adb_entra_env

export AZURE_TOKEN_DIR="${AZURE_TOKEN_DIR:-$HOME/.azure/adb-entra-id}"
export AZURE_REDIRECT_URI="${AZURE_REDIRECT_URI:-http://localhost:8888/callback}"
export AZURE_REDIRECT_URIS="${AZURE_REDIRECT_URIS:-${AZURE_REDIRECT_URI},http://localhost:8889/callback,http://localhost:8890/callback,http://localhost}"
export AZURE_OPEN_BROWSER="${AZURE_OPEN_BROWSER:-0}"
export AZURE_HEADLESS="${AZURE_HEADLESS:-0}"
export AZURE_SCOPE="${AZURE_SCOPE:-${APP_ID_URI}/${ENTRA_SCOPE_VALUE:-session:scope:connect}}"

DEFAULT_REDIRECT_URIS="http://localhost:8888/callback,http://localhost:8889/callback,http://localhost:8890/callback,http://localhost"
SQLNET_FILE="${TNS_ADMIN}/sqlnet.ora"

usage() {
  cat <<'EOF'
Usage:
  ./04_get_entra_oauth_token.sh
  ./04_get_entra_oauth_token.sh --headless
  AZURE_OPEN_BROWSER=1 ./04_get_entra_oauth_token.sh

Options:
  --headless     Print the login URL and prompt for the full localhost callback URL.
  -h, --help     Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --headless)
      AZURE_HEADLESS=1
      export AZURE_HEADLESS
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo -e "${RED}ERROR: Unknown option: $1${NC}" >&2
      usage
      exit 1
      ;;
  esac
done

set_sqlnet_value() {
  local key="$1"
  local value="$2"
  local escaped_value
  escaped_value=$(printf '%s' "$value" | sed 's/[&#]/\\&/g')

  if grep -Eiq "^[[:space:]]*${key}[[:space:]]*=" "$SQLNET_FILE"; then
    sed -i.bak-entra-oauth -E "s#^[[:space:]]*${key}[[:space:]]*=.*#${key}=${escaped_value}#I" "$SQLNET_FILE"
  else
    echo "${key}=${value}" >> "$SQLNET_FILE"
  fi
}

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 4: Get Microsoft Entra OAuth2 Access Token                       ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}TNS_ADMIN       = ${TNS_ADMIN}${NC}"
echo -e "${CYAN}ADB_SERVICE     = ${ADB_SERVICE}${NC}"
echo -e "${CYAN}AZURE_TOKEN_DIR = ${AZURE_TOKEN_DIR}${NC}"
echo -e "${CYAN}AZURE_SCOPE     = ${AZURE_SCOPE}${NC}"
echo

if [ ! -f "$SQLNET_FILE" ]; then
  echo -e "${RED}ERROR: ${SQLNET_FILE} was not found. Re-run ./00_setup_adb_entra_id.sh to download the ADB wallet.${NC}"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo -e "${RED}ERROR: python3 is required.${NC}"
  exit 1
fi

echo -e "${YELLOW}Step 1: Configuring sqlnet.ora for OAuth2 token login...${NC}"
cp "$SQLNET_FILE" "${SQLNET_FILE}.bak-entra-oauth"
set_sqlnet_value TOKEN_AUTH OAUTH
set_sqlnet_value TOKEN_LOCATION "$AZURE_TOKEN_DIR"
echo -e "${CYAN}  sqlnet.ora now uses TOKEN_AUTH=OAUTH and TOKEN_LOCATION=${AZURE_TOKEN_DIR}${NC}"

echo
echo -e "${YELLOW}Step 2: Starting Microsoft Entra OAuth2 authorization-code login...${NC}"
echo -e "${PURPLE}This prints a Microsoft Entra login URL, then writes the returned OAuth2 access${NC}"
echo -e "${PURPLE}token where SQL*Plus can read it.${NC}"
echo

python3 - <<'PY'
import base64
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer

tenant_id = os.environ["TENANT_ID"]
client_id = os.environ["CLIENT_ID"]
scope = os.environ["AZURE_SCOPE"]
token_dir = os.environ["AZURE_TOKEN_DIR"]
open_browser = os.environ.get("AZURE_OPEN_BROWSER", "0").lower() in ("1", "true", "yes", "y")
headless = os.environ.get("AZURE_HEADLESS", "0").lower() in ("1", "true", "yes", "y")

redirect_candidates = []
for raw_uri in os.environ.get("AZURE_REDIRECT_URIS", os.environ["AZURE_REDIRECT_URI"]).split(","):
    raw_uri = raw_uri.strip()
    if raw_uri:
        redirect_candidates.append(raw_uri)
if os.environ["AZURE_REDIRECT_URI"] not in redirect_candidates:
    redirect_candidates.insert(0, os.environ["AZURE_REDIRECT_URI"])

state = base64.urlsafe_b64encode(os.urandom(24)).decode("ascii").rstrip("=")
code_verifier = base64.urlsafe_b64encode(os.urandom(48)).decode("ascii").rstrip("=")
code_challenge = base64.urlsafe_b64encode(
    __import__("hashlib").sha256(code_verifier.encode("ascii")).digest()
).decode("ascii").rstrip("=")
result = {}
server = None
redirect_uri = None
path = None

def prompt_from_tty(prompt):
    try:
        with open("/dev/tty", "r", encoding="utf-8") as tty_in:
            with open("/dev/tty", "w", encoding="utf-8") as tty_out:
                tty_out.write(prompt)
                tty_out.flush()
                return tty_in.readline().strip()
    except OSError:
        return input(prompt).strip()

def extract_authorization_code(pasted):
    pasted = pasted.strip()
    if not pasted:
        return ""
    if "://" not in pasted and "code=" not in pasted:
        print("Using pasted value as the authorization code.")
        return pasted

    parsed = urllib.parse.urlparse(pasted)
    params = {**urllib.parse.parse_qs(parsed.fragment), **urllib.parse.parse_qs(parsed.query)}
    if "error" in params:
        error = params.get("error", [""])[0]
        description = params.get("error_description", [""])[0]
        print(f"ERROR: Microsoft Entra returned {error}: {description}", file=sys.stderr)
        sys.exit(1)

    returned_state = params.get("state", [""])[0]
    if returned_state and returned_state != state:
        print("ERROR: The pasted URL state value does not match this token request.", file=sys.stderr)
        sys.exit(1)

    code = params.get("code", [""])[0]
    if not code:
        print("ERROR: No code= parameter was found in the pasted value.", file=sys.stderr)
        sys.exit(1)
    print(f"Parsed authorization code ({len(code)} characters).")
    return code

class CallbackHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)
        if parsed.path != path:
            self.send_response(404)
            self.end_headers()
            return
        if params.get("state", [""])[0] != state:
            result["error"] = "Returned OAuth state did not match the request."
        elif "error" in params:
            result["error"] = params.get("error_description", params["error"])[0]
        else:
            result["code"] = params.get("code", [""])[0]

        body = b"You can close this browser tab and return to the terminal.\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

def serve_once(http_server):
    http_server.handle_request()

if not headless:
    for candidate in redirect_candidates:
        parsed = urllib.parse.urlparse(candidate)
        if parsed.scheme != "http" or parsed.hostname not in ("localhost", "127.0.0.1"):
            continue
        try:
            server = HTTPServer((parsed.hostname, parsed.port or 80), CallbackHandler)
            redirect_uri = candidate
            path = parsed.path or "/"
            threading.Thread(target=serve_once, args=(server,), daemon=True).start()
            break
        except OSError as exc:
            print(f"Could not listen on {parsed.hostname}:{parsed.port or 80}: {exc}")

if not redirect_uri:
    redirect_uri = redirect_candidates[0]
    path = urllib.parse.urlparse(redirect_uri).path or "/"
    if headless:
        print("Running in headless mode.")
    else:
        print("Continuing in manual callback mode.")

auth_url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/authorize?" + urllib.parse.urlencode({
    "client_id": client_id,
    "response_type": "code",
    "redirect_uri": redirect_uri,
    "response_mode": "query",
    "scope": scope,
    "state": state,
    "code_challenge": code_challenge,
    "code_challenge_method": "S256",
})

if server:
    print(f"Listening for OAuth callback on {redirect_uri}")
else:
    print(f"Manual callback mode for redirect URI {redirect_uri}")
print()

if headless:
    print("=" * 76)
    print("ACTION REQUIRED: USE A SEPARATE PRIVATE BROWSER WINDOW")
    print("=" * 76)
    print("1. Copy the login URL below into a separate browser profile, private")
    print("   window, incognito window, or different browser.")
    print("2. Sign in as the target demo user.")
    print("3. The final localhost page will usually fail to load. That is expected.")
    print("4. Copy the entire localhost callback URL from that browser address bar")
    print("   and paste it back here.")
    print("=" * 76)
    print()

if open_browser:
    print("Opening browser for Microsoft Entra login...")
    if not webbrowser.open(auth_url, new=2):
        print("Could not open a browser automatically. Open this URL manually:")
        print(auth_url)
else:
    if not headless:
        print("Open this URL in a separate browser profile, private window, or independent browser.")
    print("LOGIN URL:")
    print(auth_url)
print()

if server:
    deadline = time.time() + int(os.environ.get("AZURE_OAUTH_TIMEOUT_SECONDS", "300"))
    while time.time() < deadline and not result:
        time.sleep(0.25)
    server.server_close()

if "error" in result:
    print(f"ERROR: {result['error']}", file=sys.stderr)
    sys.exit(1)

code = result.get("code")
if not code:
    print("Copy the entire final redirected URL from the separate browser address bar.")
    if headless:
        print("The localhost page will usually fail to load from a local browser when the script runs in Cloud Shell.")
        print("That is expected. Do not troubleshoot the page load; copy the full localhost callback URL shown in the address bar.")
    for attempt in range(1, 4):
        pasted_value = prompt_from_tty("Paste the full callback URL: ")
        if pasted_value.strip():
            code = extract_authorization_code(pasted_value)
            break
        if attempt < 3:
            print("No URL pasted. Paste the full callback URL, then press Enter.")

if not code:
    print("ERROR: Could not determine authorization code. Re-run this script and paste the full localhost callback URL from the browser address bar.", file=sys.stderr)
    sys.exit(1)

form = {
    "grant_type": "authorization_code",
    "code": code,
    "redirect_uri": redirect_uri,
    "client_id": client_id,
    "code_verifier": code_verifier,
    "scope": scope,
}
request = urllib.request.Request(
    f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token",
    data=urllib.parse.urlencode(form).encode("utf-8"),
    headers={
        "Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
        "Accept": "application/json",
    },
    method="POST",
)
try:
    with urllib.request.urlopen(request, timeout=60) as response:
        token_response = json.loads(response.read().decode("utf-8"))
except urllib.error.HTTPError as exc:
    print(f"ERROR: Microsoft Entra token exchange failed: HTTP {exc.code}", file=sys.stderr)
    print(exc.read().decode("utf-8", errors="replace"), file=sys.stderr)
    sys.exit(1)

access_token = token_response.get("access_token")
if not access_token:
    print("ERROR: Microsoft Entra token response did not include access_token.", file=sys.stderr)
    print(json.dumps(token_response, indent=2), file=sys.stderr)
    sys.exit(1)

os.makedirs(token_dir, mode=0o700, exist_ok=True)
token_path = os.path.join(token_dir, "token")
with open(token_path, "w", encoding="utf-8") as token_file:
    token_file.write(access_token)
os.chmod(token_dir, 0o700)
os.chmod(token_path, 0o600)

print()
print("Microsoft Entra OAuth2 access token written for SQL*Plus.")
print(f"  TOKEN_LOCATION={token_dir}")
print(f"  token file     = {token_path}")
print(f"  expires_in     = {token_response.get('expires_in', 'unknown')}")
PY

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 4 Completed: Microsoft Entra OAuth2 Token Ready                  ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo "Ready: run ./05_verify_as_marvin.sh or ./06_verify_as_emma.sh"
echo
