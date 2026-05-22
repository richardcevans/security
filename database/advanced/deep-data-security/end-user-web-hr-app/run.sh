#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VERBOSE="${WEB_HR_VERBOSE:-0}"

usage() {
  cat <<'EOF'
Usage:
  ./run.sh [options]

Options:
  -v, --verbose
      Print safe startup diagnostics before launching the web app.

  -h, --help
      Show this help.

Secrets and passwords are redacted from verbose output.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -v|--verbose)
      VERBOSE=1
      export WEB_HR_VERBOSE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

WEB_HR_ENV_LOADED=0
if [ -f .end-user-web-hr-app.env ]; then
  WEB_HR_ENV_LOADED=1
  set -a
  # shellcheck disable=SC1091
  source ./.end-user-web-hr-app.env
  set +a
elif [ -f .web-hr-app.env ]; then
  WEB_HR_ENV_LOADED=1
  set -a
  # shellcheck disable=SC1091
  source ./.web-hr-app.env
  set +a
fi

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source ./.env
  set +a
fi

if [ -z "${WEB_HR_DB_MODE:-}" ]; then
  if [ "$WEB_HR_ENV_LOADED" -eq 1 ]; then
    export WEB_HR_DB_MODE="oracledb"
  else
    export WEB_HR_DB_MODE="mock"
  fi
fi

if [ "$WEB_HR_ENV_LOADED" -eq 1 ] && [ "${WEB_HR_DB_MODE}" = "mock" ]; then
  echo "WARNING: .web-hr-app.env exists, but WEB_HR_DB_MODE=mock."
  echo "This will simulate responses and will not prove Oracle Deep Data Security."
  echo "Use WEB_HR_DB_MODE=oracledb ./run.sh or remove WEB_HR_DB_MODE=mock from .env."
  echo
fi

tns_has_alias() {
  local dir="$1"
  local alias_name="${WEB_HR_TNS_ALIAS:-${PDB_NAME:-FREEPDB1}}"
  [ -f "${dir}/tnsnames.ora" ] || return 1
  grep -Eiq "^[[:space:]]*${alias_name}[[:space:]]*=" "${dir}/tnsnames.ora"
}

find_tns_admin_with_alias() {
  local dir
  for dir in \
    "${WEB_HR_CONFIG_DIR:-}" \
    "${TNS_ADMIN:-}" \
    "${ORACLE_HOME:-}/network/admin" \
    /opt/oracle/product/*/dbhome_*/network/admin \
    /u01/app/oracle/product/*/dbhome_*/network/admin
  do
    [ -n "$dir" ] || continue
    [ -d "$dir" ] || continue
    if tns_has_alias "$dir"; then
      printf '%s\n' "$dir"
      return 0
    fi
  done
  return 1
}

detected_config_dir="$(find_tns_admin_with_alias || true)"
WEB_HR_EFFECTIVE_TNS_ALIAS="${WEB_HR_TNS_ALIAS:-${PDB_NAME:-FREEPDB1}}"
export WEB_HR_EFFECTIVE_TNS_ALIAS
if [ -n "$detected_config_dir" ]; then
  if [ -z "${WEB_HR_CONFIG_DIR:-}" ]; then
    export WEB_HR_CONFIG_DIR="$detected_config_dir"
    echo "WARNING: WEB_HR_CONFIG_DIR was not set; using ${WEB_HR_CONFIG_DIR} for ${WEB_HR_EFFECTIVE_TNS_ALIAS}."
  elif [ "$WEB_HR_CONFIG_DIR" != "$detected_config_dir" ] && ! tns_has_alias "$WEB_HR_CONFIG_DIR"; then
    echo "WARNING: WEB_HR_CONFIG_DIR=${WEB_HR_CONFIG_DIR} does not contain ${WEB_HR_EFFECTIVE_TNS_ALIAS}; using ${detected_config_dir}."
    export WEB_HR_CONFIG_DIR="$detected_config_dir"
  fi
elif [ -z "${WEB_HR_CONFIG_DIR:-}" ] && [ -n "${TNS_ADMIN:-}" ] && ! tns_has_alias "$TNS_ADMIN"; then
  echo "WARNING: TNS_ADMIN=${TNS_ADMIN} does not contain ${WEB_HR_EFFECTIVE_TNS_ALIAS}. Run ./setup_python_oracledb.sh."
fi

PYTHON_BIN="${PYTHON_BIN:-}"
if [ -z "$PYTHON_BIN" ]; then
  VENV_DIR="${WEB_HR_VENV_DIR:-${HOME}/web-hr-app-venv}"
  DEFAULT_PYTHON_BIN="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
  if [ -x "${VENV_DIR}/bin/python" ]; then
    PYTHON_BIN="${VENV_DIR}/bin/python"
    if [ -n "$DEFAULT_PYTHON_BIN" ] && [ "$DEFAULT_PYTHON_BIN" != "$PYTHON_BIN" ]; then
      echo "WARNING: default Python is ${DEFAULT_PYTHON_BIN}; using lab Python ${PYTHON_BIN}."
    fi
  elif [ -x "${SCRIPT_DIR}/.venv/bin/python" ]; then
    PYTHON_BIN="${SCRIPT_DIR}/.venv/bin/python"
    if [ -n "$DEFAULT_PYTHON_BIN" ] && [ "$DEFAULT_PYTHON_BIN" != "$PYTHON_BIN" ]; then
      echo "WARNING: default Python is ${DEFAULT_PYTHON_BIN}; using lab Python ${PYTHON_BIN}."
    fi
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    PYTHON_BIN="python"
  fi
else
  echo "Using PYTHON_BIN from environment: ${PYTHON_BIN}"
fi
export PYTHON_BIN

exists_text() {
  if [ -e "$1" ]; then
    printf 'exists'
  else
    printf 'missing'
  fi
}

dir_text() {
  if [ -d "$1" ]; then
    printf 'exists'
  else
    printf 'missing'
  fi
}

print_var() {
  local name="$1"
  local value="${!name-}"
  case "$name" in
    *SECRET*|*PASSWORD*|*ACCESS_TOKEN*|*ID_TOKEN*)
      if [ -n "$value" ]; then
        printf '  %-28s = <set, redacted>\n' "$name"
      else
        printf '  %-28s = <not set>\n' "$name"
      fi
      ;;
    *)
      if [ -n "$value" ]; then
        printf '  %-28s = %s\n' "$name" "$value"
      else
        printf '  %-28s = <not set>\n' "$name"
      fi
      ;;
  esac
}

print_verbose_startup() {
  echo
  echo "========================================================================"
  echo "Web HR App verbose startup diagnostics"
  echo "========================================================================"
  echo "Generated: $(date -Is)"
  echo "User:      $(id -un 2>/dev/null || true)"
  echo "Hostname:  $(hostname 2>/dev/null || true)"
  echo "Directory: ${SCRIPT_DIR}"
  echo
  echo "Environment files:"
  echo "  ${SCRIPT_DIR}/.end-user-web-hr-app.env = $([ -f "${SCRIPT_DIR}/.end-user-web-hr-app.env" ] && echo loaded || echo missing)"
  echo "  ${SCRIPT_DIR}/.web-hr-app.env = $([ -f "${SCRIPT_DIR}/.web-hr-app.env" ] && echo loaded || echo missing)"
  echo "  ${SCRIPT_DIR}/.env = $([ -f "${SCRIPT_DIR}/.env" ] && echo loaded || echo missing)"
  echo
  echo "Selected configuration:"
  for name in \
    WEB_HR_DB_MODE WEB_HR_HOST WEB_HR_PORT \
    WEB_HR_HTTPS_PORT WEB_HR_HTTP_REDIRECT_PORT WEB_HR_PUBLIC_HOST \
    PDB_NAME WEB_HR_TNS_ALIAS WEB_HR_EFFECTIVE_TNS_ALIAS WEB_HR_CONFIG_DIR TNS_ADMIN WEB_HR_WALLET_LOCATION \
    WEB_HR_WALLET_PASSWORD WEB_HR_EMMA_PASSWORD WEB_HR_MARVIN_PASSWORD \
    WEB_HR_END_USER_PASSWORD WEB_HR_ADMIN_USER WEB_HR_ADMIN_PASSWORD \
    WEB_HR_TLS_CERT WEB_HR_TLS_KEY PYTHON_BIN
  do
    print_var "$name"
  done
  echo
  echo "File checks:"
  if [ -n "${WEB_HR_CONFIG_DIR:-}" ]; then
    echo "  WEB_HR_CONFIG_DIR directory = $(dir_text "$WEB_HR_CONFIG_DIR")"
    echo "  WEB_HR_CONFIG_DIR/tnsnames.ora = $(exists_text "${WEB_HR_CONFIG_DIR}/tnsnames.ora")"
    echo "  WEB_HR_CONFIG_DIR/sqlnet.ora = $(exists_text "${WEB_HR_CONFIG_DIR}/sqlnet.ora")"
  elif [ -n "${TNS_ADMIN:-}" ]; then
    echo "  TNS_ADMIN directory = $(dir_text "$TNS_ADMIN")"
    echo "  TNS_ADMIN/tnsnames.ora = $(exists_text "${TNS_ADMIN}/tnsnames.ora")"
    echo "  TNS_ADMIN/sqlnet.ora = $(exists_text "${TNS_ADMIN}/sqlnet.ora")"
  fi
  if [ -n "${WEB_HR_WALLET_LOCATION:-}" ]; then
    echo "  WEB_HR_WALLET_LOCATION directory = $(dir_text "$WEB_HR_WALLET_LOCATION")"
    echo "  WEB_HR_WALLET_LOCATION/ewallet.pem = $(exists_text "${WEB_HR_WALLET_LOCATION}/ewallet.pem")"
  else
    echo "  python-wallet/ewallet.pem = $(exists_text "${SCRIPT_DIR}/python-wallet/ewallet.pem")"
  fi
  [ -n "${WEB_HR_TLS_CERT:-}" ] && echo "  WEB_HR_TLS_CERT = $(exists_text "$WEB_HR_TLS_CERT")"
  [ -n "${WEB_HR_TLS_KEY:-}" ] && echo "  WEB_HR_TLS_KEY = $(exists_text "$WEB_HR_TLS_KEY")"
  echo
  echo "Python:"
  "$PYTHON_BIN" - <<'PY'
import sys
print("  executable = {0}".format(sys.executable))
print("  version    = {0}".format(sys.version.replace("\n", " ")))
try:
    import oracledb
    print("  oracledb   = {0}".format(getattr(oracledb, "__version__", "unknown")))
except Exception as exc:
    print("  oracledb   = unavailable ({0})".format(exc))
PY
  echo
  echo "Network hints:"
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp 2>/dev/null | grep ":${WEB_HR_PORT:-8012} " || echo "  No existing listener on port ${WEB_HR_PORT:-8012} before startup."
  else
    echo "  ss command is not available."
  fi
  echo "========================================================================"
  echo
}

if [ "$VERBOSE" = "1" ]; then
  print_verbose_startup
fi

export PYTHONUNBUFFERED="${PYTHONUNBUFFERED:-1}"
exec "$PYTHON_BIN" -m app.main
