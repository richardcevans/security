#!/bin/bash
# Token preflight helpers for OCI IAM OAuth2 SQL*Plus logins.

check_oauth_token() {
  local expected_user="$1"
  shift
  local required_groups=("$@")
  local token_dir="${OCI_TOKEN_DIR:-$HOME/.oci/deep-sec-mcp}"
  local token_file="${token_dir}/token"

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
  python3 - <<'PY'
import base64
import json
import os
import sys

expected_user = os.environ["EXPECTED_USER"].lower()
required_groups = [g for g in os.environ.get("REQUIRED_GROUPS", "").split(",") if g]
token_file = os.environ["TOKEN_FILE"]

with open(token_file, "r", encoding="utf-8") as handle:
    token = handle.read().strip()

def error_panel(title, lines):
    red = "\033[1;31m"
    reset = "\033[0m"
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
        f"Commands: rm -rf $HOME/.oci/deep-sec-mcp && ./04_get_iam_oauth_token.sh --headless",
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
