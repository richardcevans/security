#!/usr/bin/env bash
# Start the local identity-preserving ADB connection proof API.

set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${script_dir}/lab_common.sh"
load_adb_lab_environment

if [[ -n "${PYTHON_BIN:-}" ]]; then
  python_bin=$PYTHON_BIN
elif [[ -x "${script_dir}/.venv/bin/python" ]]; then
  python_bin="${script_dir}/.venv/bin/python"
else
  python_bin=python3
fi
"$python_bin" -c 'import jwt, oracledb' >/dev/null 2>&1 || {
  cat >&2 <<EOF
ERROR: Python dependencies are missing from ${python_bin}.
Create the project-local virtual environment and install them:
  python3 -m venv ${script_dir}/.venv
  ${script_dir}/.venv/bin/python -m pip install -r ${script_dir}/service/requirements.txt
EOF
  exit 1
}

export IDENTITY_SERVICE_HOST=${IDENTITY_SERVICE_HOST:-127.0.0.1}
export IDENTITY_SERVICE_PORT=${IDENTITY_SERVICE_PORT:-8030}

printf '%s\n' '============================================================================'
printf '%s\n' 'Start OCI IAM-to-ADB identity-proof API'
printf '%s\n' '============================================================================'
printf 'Listening only on: http://%s:%s\n' "$IDENTITY_SERVICE_HOST" "$IDENTITY_SERVICE_PORT"
printf '%s\n' 'The service accepts a bearer token, validates it, and connects to ADB using that same token.'
printf '%s\n' 'The LLM endpoint selects only reviewed query tools; it never accepts SQL.'
printf '\nRun the verification script in a second terminal:\n'
printf '  %s/10_verify_identity_service.sh\n\n' "$script_dir"

exec "$python_bin" "$script_dir/service/identity_service.py"
