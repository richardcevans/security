#!/usr/bin/env bash
set -euo pipefail

VENV_DIR="${WEB_HR_VENV_DIR:-${HOME}/web-hr-app-venv}"
PYTHON_BIN="${WEB_HR_PYTHON_BIN:-python3.9}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTRA_LAB_DIR="${ENTRA_LAB_DIR:-${SCRIPT_DIR}/../entra-id-data-grants}"
ENTRA_CERT_EXPORT="${ENTRA_LAB_DIR}/export_server_cert_for_client.sh"
ENTRA_CLIENT_TRUST_DIR="${ENTRA_LAB_DIR}/client-trust"
SERVER_CERT="${WEB_HR_SERVER_CERT:-${ENTRA_CLIENT_TRUST_DIR}/db_server_cert.pem}"
PYTHON_WALLET_DIR="${WEB_HR_WALLET_LOCATION:-${SCRIPT_DIR}/python-wallet}"
ENV_FILE="${SCRIPT_DIR}/.env"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

upsert_export() {
  local name="$1"
  local value="$2"
  local escaped
  escaped="$(printf '%s' "$value" | sed "s/'/'\\\\''/g")"
  if grep -Eq "^(export[[:space:]]+)?${name}=" "$ENV_FILE"; then
    echo "Updating ${name} in ${ENV_FILE}."
    sed -i -E "s|^(export[[:space:]]+)?${name}=.*|export ${name}='${escaped}'|" "$ENV_FILE"
  else
    echo "Adding ${name} to ${ENV_FILE}."
    echo "export ${name}='${escaped}'" >> "$ENV_FILE"
  fi
}

install_python39() {
  if command_exists "$PYTHON_BIN"; then
    return
  fi

  echo "Python 3.9 was not found. Installing Oracle Linux 8 python39 module..."

  if [ "$(id -u)" -eq 0 ]; then
    dnf module install -y python39
  elif command_exists sudo; then
    sudo dnf module install -y python39
  else
    echo "ERROR: sudo is required to install python39, or run this script as root."
    exit 1
  fi
}

ensure_pip_support() {
  if "$PYTHON_BIN" -m pip --version >/dev/null 2>&1; then
    return
  fi

  echo "python3.9 pip support was not found. Installing python39-pip..."

  if [ "$(id -u)" -eq 0 ]; then
    dnf install -y python39-pip
  elif command_exists sudo; then
    sudo dnf install -y python39-pip
  else
    echo "ERROR: sudo is required to install python39-pip, or run this script as root."
    exit 1
  fi
}

install_python39
ensure_pip_support

echo "Using Python:"
"$PYTHON_BIN" --version

echo
if [ -d "$VENV_DIR" ]; then
  echo "Reusing existing virtual environment and updating packages:"
else
  echo "Creating virtual environment:"
fi
echo "$VENV_DIR"
"$PYTHON_BIN" -m venv "$VENV_DIR"

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

echo
echo "Installing or updating python-oracledb 4.x in the virtual environment..."
python -m pip install --upgrade pip
python -m pip install "oracledb>=4"

echo
echo "Verifying Deep Data Security API support..."
python -c "import oracledb; print('python-oracledb', oracledb.__version__); assert hasattr(oracledb, 'create_end_user_security_context'), 'Missing create_end_user_security_context'"

echo
echo "Preparing python-oracledb Thin-mode trust wallet..."
if [ ! -f "$SERVER_CERT" ] && [ -x "$ENTRA_CERT_EXPORT" ]; then
  echo "Server certificate not found; exporting it with entra-id-data-grants helper."
  (cd "$ENTRA_LAB_DIR" && ./export_server_cert_for_client.sh --linux)
fi

if [ ! -f "$SERVER_CERT" ]; then
  echo "ERROR: Server certificate was not found:"
  echo "$SERVER_CERT"
  echo "Run ../entra-id-data-grants/export_server_cert_for_client.sh --linux, then rerun this script."
  exit 1
fi

mkdir -p "$PYTHON_WALLET_DIR"
echo "Writing or replacing python-oracledb Thin-mode trust wallet:"
echo "${PYTHON_WALLET_DIR}/ewallet.pem"
cp "$SERVER_CERT" "${PYTHON_WALLET_DIR}/ewallet.pem"
chmod 700 "$PYTHON_WALLET_DIR"
chmod 600 "${PYTHON_WALLET_DIR}/ewallet.pem"

echo "Created:"
echo "${PYTHON_WALLET_DIR}/ewallet.pem"

touch "$ENV_FILE"
upsert_export "PYTHON_BIN" "${VENV_DIR}/bin/python"
upsert_export "WEB_HR_WALLET_LOCATION" "$PYTHON_WALLET_DIR"

if [ -n "${TNS_ADMIN:-}" ]; then
  upsert_export "WEB_HR_CONFIG_DIR" "$TNS_ADMIN"
fi

echo
echo "Ready."
echo "Next:"
echo "./start.sh --verbose"
