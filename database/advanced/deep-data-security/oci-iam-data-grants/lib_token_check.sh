#!/bin/bash
# Shared helpers for checking the OCI IAM OAuth2 access token before sqlplus.

check_oauth_token() {
  local expected_user="$1"
  shift
  local required_groups=("$@")
  local token_dir="${OCI_TOKEN_DIR:-$HOME/.oci/oci-iam-data-grants}"
  local token_file="${token_dir}/token"

  if [ ! -s "$token_file" ]; then
    echo -e "${RED:-}ERROR: OAuth2 token file not found: ${token_file}${NC:-}"
    echo -e "${YELLOW:-}Run ./get_oci_oauth_token.sh and sign in as ${expected_user}.${NC:-}"
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
import time

token_file = os.environ["TOKEN_FILE"]
expected_user = os.environ["EXPECTED_USER"].lower()
required_groups = [g for g in os.environ.get("REQUIRED_GROUPS", "").split(",") if g]

with open(token_file, "r", encoding="utf-8") as handle:
    token = handle.read().strip()

try:
    payload_part = token.split(".")[1]
    payload_part += "=" * (-len(payload_part) % 4)
    payload = json.loads(base64.urlsafe_b64decode(payload_part.encode("ascii")))
except Exception as exc:
    print(f"ERROR: Could not decode OAuth2 token: {exc}", file=sys.stderr)
    sys.exit(1)

subject = str(payload.get("sub", "")).lower()
groups = payload.get("group") or payload.get("groups") or []
if isinstance(groups, str):
    groups = [groups]
group_set = {str(group) for group in groups}
expires = int(payload.get("exp", 0) or 0)
now = int(time.time())

print(f"Token subject: {payload.get('sub', '')}")
print(f"Token groups : {', '.join(groups) if groups else '(none)'}")

if subject != expected_user:
    print(f"ERROR: Token is for {payload.get('sub', '')}, expected {expected_user}.", file=sys.stderr)
    sys.exit(1)

if expires and expires <= now:
    print("ERROR: Token is expired. Run ./get_oci_oauth_token.sh again.", file=sys.stderr)
    sys.exit(1)

missing = [group for group in required_groups if group not in group_set]
if missing:
    print(f"ERROR: Token is missing required group(s): {', '.join(missing)}", file=sys.stderr)
    sys.exit(1)

if expires:
    print(f"Token expires in: {expires - now} seconds")
PY
}
