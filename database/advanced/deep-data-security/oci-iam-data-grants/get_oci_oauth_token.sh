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
export OCI_REDIRECT_URI="${OCI_REDIRECT_URI:-http://localhost:8888/callback}"
export OCI_REDIRECT_URIS="${OCI_REDIRECT_URIS:-${OCI_REDIRECT_URI}}"
export OCI_OPEN_BROWSER="${OCI_OPEN_BROWSER:-0}"
export OCI_HEADLESS="${OCI_HEADLESS:-0}"

normalize_redirect_uri() {
  local first_uri
  first_uri="${OCI_REDIRECT_URIS%%,*}"
  if [ -n "$OCI_REDIRECT_URIS" ] && [[ ",${OCI_REDIRECT_URIS}," != *",${OCI_REDIRECT_URI},"* ]]; then
    echo -e "${YELLOW}Ignoring stale OCI_REDIRECT_URI=${OCI_REDIRECT_URI}${NC}"
    echo -e "${YELLOW}Using OCI_REDIRECT_URI=${first_uri}${NC}"
    OCI_REDIRECT_URI="$first_uri"
    export OCI_REDIRECT_URI
  fi
}

usage() {
  cat <<EOF
Usage:
  ./get_oci_oauth_token.sh
  ./get_oci_oauth_token.sh --headless
  OCI_OPEN_BROWSER=1 ./get_oci_oauth_token.sh

Options:
  --headless     Do not listen for the localhost callback. Print the login URL
                 and prompt for the final redirected URL or code value.
  -h, --help     Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --headless)
      OCI_HEADLESS=1
      export OCI_HEADLESS
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

for var in OCI_DOMAIN_URL OCI_CLIENT_ID OCI_CLIENT_SECRET OCI_SCOPE OCI_REDIRECT_URI; do
  if [ -z "${!var:-}" ]; then
    echo -e "${RED}ERROR: ${var} is not set.${NC}"
    echo -e "${YELLOW}Run ./00_setup_oci_iam.sh and source ./.oci-iam-data-grants.env first.${NC}"
    exit 1
  fi
done

normalize_redirect_uri

if ! command -v python3 >/dev/null 2>&1; then
  echo -e "${RED}ERROR: python3 is required.${NC}"
  exit 1
fi

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Get OCI IAM OAuth2 Access Token                                       ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${PURPLE}This starts OCI IAM OAuth2 authorization-code login, captures or accepts${NC}"
echo -e "${PURPLE}the authorization callback, and writes the access token for SQL*Plus.${NC}"
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
token_dir = os.environ["OCI_TOKEN_DIR"]
open_browser = os.environ.get("OCI_OPEN_BROWSER", "0").lower() in ("1", "true", "yes", "y")
headless = os.environ.get("OCI_HEADLESS", "0").lower() in ("1", "true", "yes", "y")

redirect_candidates = []
raw_redirect_uris = os.environ.get("OCI_REDIRECT_URIS", "")
for raw_uri in os.environ.get("OCI_REDIRECT_URIS", os.environ["OCI_REDIRECT_URI"]).split(","):
    raw_uri = raw_uri.strip()
    if raw_uri:
        redirect_candidates.append(raw_uri)

if os.environ["OCI_REDIRECT_URI"] not in redirect_candidates and not raw_redirect_uris:
    redirect_candidates.insert(0, os.environ["OCI_REDIRECT_URI"])
elif os.environ["OCI_REDIRECT_URI"] not in redirect_candidates:
    print(f"Ignoring stale OCI_REDIRECT_URI not in registered URI list: {os.environ['OCI_REDIRECT_URI']}")

if not redirect_candidates:
    redirect_candidates = [os.environ["OCI_REDIRECT_URI"]]

server = None
redirect_uri = None
host = None
port = None
path = None

state = base64.urlsafe_b64encode(os.urandom(24)).decode("ascii").rstrip("=")
result = {}

def prompt_from_tty(prompt):
    try:
        with open("/dev/tty", "r", encoding="utf-8") as tty_in:
            with open("/dev/tty", "w", encoding="utf-8") as tty_out:
                tty_out.write(prompt)
                tty_out.flush()
                return tty_in.readline().strip()
    except OSError:
        return input(prompt).strip()

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

if not headless:
    for candidate in redirect_candidates:
        redirect = urllib.parse.urlparse(candidate)
        if redirect.scheme != "http" or redirect.hostname not in ("localhost", "127.0.0.1"):
            continue

        candidate_host = redirect.hostname or "localhost"
        candidate_port = redirect.port or 80
        candidate_path = redirect.path or "/"

        try:
            server = HTTPServer((candidate_host, candidate_port), CallbackHandler)
            redirect_uri = candidate
            host = candidate_host
            port = candidate_port
            path = candidate_path
            server_thread = threading.Thread(target=serve_once, args=(server,), daemon=True)
            server_thread.start()
            break
        except OSError as exc:
            print(f"Could not listen on {candidate_host}:{candidate_port}: {exc}")

if not redirect_uri:
    redirect_uri = redirect_candidates[0]
    redirect = urllib.parse.urlparse(redirect_uri)
    path = redirect.path or "/"
    if headless:
        print("Running in headless mode.")
    else:
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
if headless:
    print("Open this URL in any browser:")
    print(auth_url)
elif open_browser:
    print("Opening browser for OCI IAM login...")
    opened = webbrowser.open(auth_url, new=2)
    if not opened:
        print("Could not open a browser automatically. Open this URL manually:")
        print(auth_url)
    else:
        print("If the browser did not open, use this URL:")
        print(auth_url)
else:
    print("Open this URL in the NoVNC browser:")
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
    if headless:
        print("After login, the browser will redirect to a localhost URL.")
        print("The page may not load. That is expected in headless mode.")
    else:
        print("Automatic callback was not captured.")
    print("Copy the final redirected URL")
    print("or copy only the code= value from that URL.")
    pasted = prompt_from_tty("Paste redirected URL or authorization code: ")
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

def post_token_request(strip_padding=False):
    form = {
        "grant_type": "authorization_code",
        "code": code,
    }
    headers = {
        "Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
        "Accept": "application/json",
    }

    basic = base64.urlsafe_b64encode(f"{client_id}:{client_secret}".encode("utf-8")).decode("ascii")
    if strip_padding:
        basic = basic.rstrip("=")
    headers["Authorization"] = f"Basic {basic}"

    request = urllib.request.Request(
        f"{domain}/oauth2/v1/token",
        data=urllib.parse.urlencode(form).encode("utf-8"),
        headers=headers,
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        return {
            "_http_error": exc.code,
            "_detail": detail,
        }

token_response = post_token_request(strip_padding=False)
if token_response.get("_http_error"):
    detail = token_response.get("_detail", "")
    if "decode Client Header" in detail or "decode client header" in detail.lower():
        token_response = post_token_request(strip_padding=True)

if token_response.get("_http_error"):
    print(f"ERROR: OCI IAM token exchange failed: HTTP {token_response['_http_error']}", file=sys.stderr)
    print(token_response.get("_detail", ""), file=sys.stderr)
    print("Hint: rerun ./00_setup_oci_iam.sh, source ./.oci-iam-data-grants.env, then retry with a fresh authorization URL.", file=sys.stderr)
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
