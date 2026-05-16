#!/usr/bin/env bash
set -euo pipefail

VENV_DIR="${WEB_HR_VENV_DIR:-${HOME}/web-hr-app-venv}"
PYTHON_BIN="${WEB_HR_PYTHON_BIN:-python3.9}"

command_exists() {
  command -v "$1" >/dev/null 2>&1
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
echo "Creating virtual environment:"
echo "$VENV_DIR"
"$PYTHON_BIN" -m venv "$VENV_DIR"

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

echo
echo "Installing python-oracledb 4.x..."
python -m pip install --upgrade pip
python -m pip install "oracledb>=4"

echo
echo "Verifying Deep Data Security API support..."
python -c "import oracledb; print('python-oracledb', oracledb.__version__); assert hasattr(oracledb, 'create_end_user_security_context'), 'Missing create_end_user_security_context'"

echo
echo "Ready."
echo "Next:"
echo "source ${VENV_DIR}/bin/activate"
echo "./run.sh"
