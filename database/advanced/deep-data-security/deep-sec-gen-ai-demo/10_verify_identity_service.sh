#!/usr/bin/env bash
# Send the current OAuth token to the loopback identity-proof API.

set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${script_dir}/lab_common.sh"
load_adb_lab_environment
# shellcheck disable=SC1091
source "${ADB_LAB_DIR}/lib_token_check.sh"

command -v curl >/dev/null 2>&1 || die 'curl is required.'
check_current_oauth_token

host=${IDENTITY_SERVICE_HOST:-127.0.0.1}
port=${IDENTITY_SERVICE_PORT:-8030}
[[ "$host" == "127.0.0.1" || "$host" == "localhost" || "$host" == "::1" ]] || die 'This verifier only sends tokens to the loopback service.'
token_file="${OCI_TOKEN_DIR:?OCI_TOKEN_DIR is required}/token"
[[ -r "$token_file" ]] || die "Token file not found: ${token_file}"
token=$(<"$token_file")

green_banner 'Verify OCI IAM token propagation through the local service'
printf 'Target: http://%s:%s/v1/identity/proof\n' "$host" "$port"
printf '%s\n' 'The bearer token is read from OCI_TOKEN_DIR/token and is not printed.'
printf '\n'

response_file=$(mktemp)
trap 'rm -f "$response_file"' EXIT

if ! curl --fail-with-body --silent --show-error \
  --connect-timeout 10 \
  --max-time 60 \
  --request POST "http://${host}:${port}/v1/identity/proof" \
  --header "Authorization: Bearer ${token}" \
  --header 'Content-Type: application/json' \
  --data '{}' >"$response_file"; then
  error 'The identity-proof API did not return a successful response.'
  if [[ -s "$response_file" ]]; then
    printf 'Response body:\n' >&2
    cat "$response_file" >&2
    printf '\n' >&2
  fi
  printf 'Start it in another terminal with: %s/09_start_identity_service.sh\n' "$script_dir" >&2
  exit 1
fi

python3 -m json.tool <"$response_file"
