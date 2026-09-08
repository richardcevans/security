#!/bin/bash
# Token preflight helpers for OCI IAM OAuth2 SQL*Plus logins.

check_oauth_token() {
  local expected_user="$1"
  shift
  local required_groups=("$@")
  local token_dir="${OCI_TOKEN_DIR:-$HOME/.oci/adb-oci-iam}"
  local token_file="${token_dir}/token"
  local token_lab_dir
  token_lab_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

  if [ ! -f "$token_file" ]; then
    echo >&2
    echo -e "\033[1;31m============================================================================\033[0m" >&2
    echo -e "\033[1;31mERROR: OAUTH TOKEN WAS NOT FOUND\033[0m" >&2
    echo -e "\033[1;31m============================================================================\033[0m" >&2
    echo "Expected token file: ${token_file}" >&2
    echo "Run ./04_get_iam_oauth_token.sh --headless and sign in as ${expected_user}" >&2
    echo "in a separate private browser session." >&2
    echo -e "\033[1;31m============================================================================\033[0m" >&2
    echo >&2
    return 1
  fi

  EXPECTED_USER="$expected_user" \
  REQUIRED_GROUPS="$(IFS=,; echo "${required_groups[*]}")" \
  TOKEN_FILE="$token_file" \
  TOKEN_REFRESH_COMMAND="cd '${token_lab_dir}' && source ./.adb-oci-iam.env && ./04_get_iam_oauth_token.sh --headless" \
  python3 - <<'PY'
import base64
import json
import os
import sys
from datetime import datetime, timezone

expected_user = os.environ["EXPECTED_USER"].lower()
required_groups = [g for g in os.environ.get("REQUIRED_GROUPS", "").split(",") if g]
token_file = os.environ["TOKEN_FILE"]
refresh_command = os.environ["TOKEN_REFRESH_COMMAND"]

with open(token_file, "r", encoding="utf-8") as handle:
    token = handle.read().strip()

def error_panel(title, lines):
    red = "\033[1;31m"
    reset = "\033[0m"
    print(file=sys.stderr)
    print(file=sys.stderr)
    print(red + "=" * 76, file=sys.stderr)
    print(f"ERROR: {title}", file=sys.stderr)
    print("=" * 76, file=sys.stderr)
    for line in lines:
        print(line, file=sys.stderr)
    print("=" * 76 + reset, file=sys.stderr)
    print(file=sys.stderr)

parts = token.split(".")
if len(parts) != 3:
    error_panel("TOKEN FILE IS NOT A JWT ACCESS TOKEN", [
        f"Token file: {token_file}",
        "Get a fresh token with ./04_get_iam_oauth_token.sh --headless.",
    ])
    sys.exit(1)

payload_raw = parts[1] + "=" * (-len(parts[1]) % 4)
payload = json.loads(base64.urlsafe_b64decode(payload_raw.encode("ascii")).decode("utf-8"))

expiry = payload.get("exp")
if expiry:
    expiry_time = datetime.fromtimestamp(int(expiry), tz=timezone.utc)
    if expiry_time <= datetime.now(timezone.utc):
        error_panel("OAUTH TOKEN EXPIRED", [
            f"Expired at : {expiry_time.isoformat()}",
            "Refresh the token, sign in as the intended OCI IAM user, then rerun this verifier:",
            f"  {refresh_command}",
            "Use a separate private/incognito browser session if another OCI IAM user is cached.",
        ])
        sys.exit(1)

subject = str(payload.get("user_name") or payload.get("sub") or "").lower()
groups = payload.get("group") or payload.get("groups") or []
if isinstance(groups, str):
    groups = [groups]
group_set = {str(group) for group in groups}

print(f"Token subject: {subject or '(missing)'}")
print(f"Token groups : {', '.join(str(group) for group in groups) if groups else '(none)'}")

if subject != expected_user:
    error_panel("TOKEN IS FOR THE WRONG USER", [
        f"Token subject: {subject or '(missing)'}",
        f"Expected user : {expected_user}",
        "Remove the current token, then get a fresh token in a separate browser session.",
        f"Commands: rm -rf $HOME/.oci/adb-oci-iam && ./04_get_iam_oauth_token.sh --headless",
        f"Sign in as {expected_user}, not the tenancy owner or another cached OCI session.",
    ])
    sys.exit(1)

missing = [group for group in required_groups if group not in group_set]
if missing:
    error_panel("TOKEN IS MISSING REQUIRED GROUPS", [
        f"Missing group(s): {', '.join(missing)}",
        "Confirm OCI IAM group membership, then get a fresh token.",
    ])
    sys.exit(1)
PY
}

# Validate the current token without prescribing a specific lab persona. The
# optional first argument is an expected user; later arguments are required
# IAM groups.
check_current_oauth_token() {
  local expected_user="${1:-}"
  shift || true
  local required_groups=("$@")
  local token_dir="${OCI_TOKEN_DIR:-$HOME/.oci/adb-oci-iam}"
  local token_file="${token_dir}/token"
  local token_lab_dir
  token_lab_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

  if [ ! -f "$token_file" ]; then
    echo >&2
    echo >&2
    echo -e "\033[0;31mERROR: No OAuth token exists at ${token_file}.\033[0m" >&2
    echo "Run ./04_get_iam_oauth_token.sh --headless and sign in as the user you want to test." >&2
    return 1
  fi

  EXPECTED_USER="$expected_user" \
  REQUIRED_GROUPS="$(IFS=,; echo "${required_groups[*]}")" \
  TOKEN_FILE="$token_file" \
  TOKEN_REFRESH_COMMAND="cd '${token_lab_dir}' && source ./.adb-oci-iam.env && ./04_get_iam_oauth_token.sh --headless" \
  python3 - <<'PY'
import base64
import json
import os
import sys
from datetime import datetime, timezone

expected_user = os.environ.get("EXPECTED_USER", "").lower()
required_groups = [group for group in os.environ.get("REQUIRED_GROUPS", "").split(",") if group]
token_file = os.environ["TOKEN_FILE"]
refresh_command = os.environ["TOKEN_REFRESH_COMMAND"]

def fail(message):
    print(file=sys.stderr)
    print(file=sys.stderr)
    print(f"\033[0;31mERROR: {message}\033[0m", file=sys.stderr)
    sys.exit(1)

with open(token_file, "r", encoding="utf-8") as handle:
    token = handle.read().strip()

parts = token.split(".")
if len(parts) != 3:
    fail(f"{token_file} is not a JWT access token. Get a fresh token with ./04_get_iam_oauth_token.sh --headless.")

try:
    encoded_payload = parts[1] + "=" * (-len(parts[1]) % 4)
    payload = json.loads(base64.urlsafe_b64decode(encoded_payload).decode("utf-8"))
except Exception as error:
    fail(f"Cannot decode the token payload: {error}")

subject = str(payload.get("user_name") or payload.get("sub") or "").lower()
groups = payload.get("group") or payload.get("groups") or []
if isinstance(groups, str):
    groups = [groups]
groups = [str(group) for group in groups]

print()
print()
print(f"Token file   : {token_file}")
print(f"Token subject: {subject or '(missing)'}")
print(f"Token groups : {', '.join(groups) if groups else '(none)'}")
audience = payload.get("aud")
if isinstance(audience, list):
    audience = ", ".join(str(value) for value in audience)
print(f"Token audience: {audience or '(missing)'}")
print(f"Token scope   : {payload.get('scope') or '(missing)'}")
print(f"Token issuer  : {payload.get('iss') or '(missing)'}")
if payload.get("exp"):
    expiry = datetime.fromtimestamp(int(payload["exp"]), tz=timezone.utc).isoformat()
    print(f"Token expires: {expiry}")
    if datetime.fromtimestamp(int(payload["exp"]), tz=timezone.utc) <= datetime.now(timezone.utc):
        fail(
            "OAuth token is expired. Refresh it, sign in as the intended OCI IAM user, then rerun this verifier:\n"
            f"  {refresh_command}\n"
            "Use a separate private/incognito browser session if another OCI IAM user is cached."
        )

if expected_user and subject != expected_user:
    fail(f"Token is for {subject or '(missing)'}, not expected user {expected_user}.")

missing = [group for group in required_groups if group not in groups]
if missing:
    fail(f"Token is missing required group(s): {', '.join(missing)}.")
PY
}
