#!/bin/bash
# Open a browser for OCI IAM OAuth2 authorization-code login, capture the
# localhost callback, exchange the code for an access token, and write the
# token where SQL*Plus can read it with TOKEN_AUTH=OAUTH.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

export OCI_TOKEN_DIR="${OCI_TOKEN_DIR:-$HOME/.oci/oci-iam-data-grants}"
export OCI_REDIRECT_URI="${OCI_REDIRECT_URI:-http://localhost:8080/callback}"

for var in OCI_DOMAIN_URL OCI_CLIENT_ID OCI_CLIENT_SECRET OCI_SCOPE OCI_REDIRECT_URI; do
  if [ -z "${!var:-}" ]; then
    echo -e "${RED}ERROR: ${var} is not set.${NC}"
    echo -e "${YELLOW}Run ./00_setup_oci_iam.sh and source ./.oci-iam-data-grants.env first.${NC}"
    exit 1
  fi
done

if ! command -v python3 >/dev/null 2>&1; then
  echo -e "${RED}ERROR: python3 is required.${NC}"
  exit 1
fi

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Get OCI IAM OAuth2 Access Token                                       ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${PURPLE}This opens OCI IAM in your browser, captures the authorization callback,${NC}"
echo -e "${PURPLE}and writes the OAuth2 access token for SQL*Plus TOKEN_AUTH=OAUTH.${NC}"
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

domain = os.environ["OCI_DOMAIN_URL"].rstrip("/")
client_id = os.environ["OCI_CLIENT_ID"]
client_secret = os.environ["OCI_CLIENT_SECRET"]
scope = os.environ["OCI_SCOPE"]
redirect_uri = os.environ["OCI_REDIRECT_URI"]
token_dir = os.environ["OCI_TOKEN_DIR"]

redirect = urllib.parse.urlparse(redirect_uri)
if redirect.scheme != "http" or redirect.hostname not in ("localhost", "127.0.0.1"):
    print(f"ERROR: OCI_REDIRECT_URI must be a localhost HTTP URL, got: {redirect_uri}", file=sys.stderr)
    sys.exit(1)

host = redirect.hostname or "localhost"
port = redirect.port or 80
path = redirect.path or "/"

state = base64.urlsafe_b64encode(os.urandom(24)).decode("ascii").rstrip("=")
result = {}

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

def serve_once(server):
    server.handle_request()

server = None
try:
    server = HTTPServer((host, port), CallbackHandler)
    server_thread = threading.Thread(target=serve_once, args=(server,), daemon=True)
    server_thread.start()
except OSError as exc:
    print(f"Could not listen on {host}:{port}: {exc}")
    print("Continuing in manual callback mode.")

auth_params = urllib.parse.urlencode({
    "client_id": client_id,
    "response_type": "code",
    "redirect_uri": redirect_uri,
    "scope": scope,
    "state": state,
})
auth_url = f"{domain}/oauth2/v1/authorize?{auth_params}"

if server:
    print(f"Listening for OAuth callback on {redirect_uri}")
else:
    print(f"Manual callback mode for redirect URI {redirect_uri}")
print()
print("Opening browser for OCI IAM login...")
opened = webbrowser.open(auth_url, new=2)
if not opened:
    print("Could not open a browser automatically. Open this URL manually:")
    print(auth_url)
else:
    print("If the browser did not open, use this URL:")
    print(auth_url)
print()

if server:
    deadline = time.time() + int(os.environ.get("OCI_OAUTH_TIMEOUT_SECONDS", "300"))
    while time.time() < deadline and not result:
        time.sleep(0.25)

if server:
    server.server_close()

if "error" in result:
    print(f"ERROR: {result['error']}", file=sys.stderr)
    sys.exit(1)

code = result.get("code")
if not code:
    print()
    print("Automatic callback was not captured.")
    print("If your browser is on another machine, copy the final redirected URL")
    print("or copy only the code= value from that URL.")
    pasted = input("Paste redirected URL or authorization code: ").strip()
    if not pasted:
        print("ERROR: No authorization code provided.", file=sys.stderr)
        sys.exit(1)
    if "code=" in pasted:
        parsed_pasted = urllib.parse.urlparse(pasted)
        pasted_params = urllib.parse.parse_qs(parsed_pasted.query)
        code = pasted_params.get("code", [""])[0]
    else:
        code = pasted

if not code:
    print("ERROR: Could not determine authorization code.", file=sys.stderr)
    sys.exit(1)

token_body = urllib.parse.urlencode({
    "grant_type": "authorization_code",
    "code": code,
    "redirect_uri": redirect_uri,
}).encode("utf-8")

basic = base64.b64encode(f"{client_id}:{client_secret}".encode("utf-8")).decode("ascii")
request = urllib.request.Request(
    f"{domain}/oauth2/v1/token",
    data=token_body,
    headers={
        "Authorization": f"Basic {basic}",
        "Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
        "Accept": "application/json",
    },
    method="POST",
)

try:
    with urllib.request.urlopen(request, timeout=60) as response:
        token_response = json.loads(response.read().decode("utf-8"))
except urllib.error.HTTPError as exc:
    detail = exc.read().decode("utf-8", errors="replace")
    print(f"ERROR: OCI IAM token exchange failed: HTTP {exc.code}", file=sys.stderr)
    print(detail, file=sys.stderr)
    sys.exit(1)
except Exception as exc:
    print(f"ERROR: OCI IAM token exchange failed: {exc}", file=sys.stderr)
    sys.exit(1)

access_token = token_response.get("access_token")
if not access_token:
    print("ERROR: OCI IAM token response did not include access_token.", file=sys.stderr)
    print(json.dumps(token_response, indent=2), file=sys.stderr)
    sys.exit(1)

os.makedirs(token_dir, mode=0o700, exist_ok=True)
token_path = os.path.join(token_dir, "token")
with open(token_path, "w", encoding="utf-8") as token_file:
    token_file.write(access_token)
os.chmod(token_dir, 0o700)
os.chmod(token_path, 0o600)

expires = token_response.get("expires_in", "unknown")
print()
print("OAuth2 access token written for SQL*Plus.")
print(f"  TOKEN_LOCATION = {token_dir}")
print(f"  token file     = {token_path}")
print(f"  expires_in     = {expires}")
PY

echo
echo -e "${GREEN}Ready: run sqlplus /@hrdb or the verification script.${NC}"
echo
