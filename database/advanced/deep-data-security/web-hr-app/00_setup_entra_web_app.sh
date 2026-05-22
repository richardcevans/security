#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTRA_LAB_ENV="${ENTRA_LAB_ENV:-${SCRIPT_DIR}/../entra-id-data-grants/.entra-id-data-grants.env}"
ENV_FILE="${SCRIPT_DIR}/.web-hr-app.env"
PUBLIC_IP_REDIRECT=1
LOCALHOST_REDIRECT=0
REDIRECT_URI_ARG=""
REDIRECT_MODE_EXPLICIT=0

usage() {
  cat <<'EOF'
Usage:
  ./00_setup_entra_web_app.sh [options]

Options:
  --localhost
      Use http://localhost:${WEB_HR_PORT:-8012}/callback as the Entra redirect URI.
      Use this only when the browser runs on the DBSec-Lab VM itself.

  --public-ip
      Discover this OCI VM public IP from instance metadata and use
      https://<public-ip>:${WEB_HR_PORT:-8012}/callback as the Entra redirect URI.
      Also writes WEB_HR_HOST=0.0.0.0 and demo TLS settings to .web-hr-app.env.
      If metadata discovery fails, the script tries an internet IP service and
      then prompts for the public IP when running interactively.

  --redirect-uri URI
      Use an explicit redirect URI such as https://203.0.113.10:8012/callback.
      Public redirect URIs must use https. Localhost may use http.

  -h, --help
      Show this help.

By default, this script uses --public-ip because most workshop users open the app
from a browser outside the VM.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --localhost)
      LOCALHOST_REDIRECT=1
      PUBLIC_IP_REDIRECT=0
      REDIRECT_MODE_EXPLICIT=1
      ;;
    --public-ip)
      PUBLIC_IP_REDIRECT=1
      LOCALHOST_REDIRECT=0
      REDIRECT_MODE_EXPLICIT=1
      ;;
    --redirect-uri)
      shift
      if [ "$#" -eq 0 ]; then
        echo "ERROR: --redirect-uri requires a value."
        exit 1
      fi
      REDIRECT_URI_ARG="$1"
      REDIRECT_MODE_EXPLICIT=1
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

if [ -f "$ENTRA_LAB_ENV" ]; then
  # shellcheck disable=SC1090
  source "$ENTRA_LAB_ENV"
else
  echo "ERROR: Cannot find ${ENTRA_LAB_ENV}. Run entra-id-data-grants first."
  exit 1
fi

if ! command -v az >/dev/null 2>&1; then
  echo "ERROR: Azure CLI is required."
  exit 1
fi

: "${TENANT_ID:?TENANT_ID is required from entra-id-data-grants}"
: "${APP_ID:?APP_ID is required from entra-id-data-grants}"
: "${APP_ID_URI:?APP_ID_URI is required from entra-id-data-grants}"
: "${PDB_NAME:?PDB_NAME is required from entra-id-data-grants}"

discover_public_ip() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl is required for --public-ip discovery." >&2
    return 1
  fi

  local payload=""
  local public_ip=""

  payload="$(curl -fsS --connect-timeout 3 \
    -H "Authorization: Bearer Oracle" \
    http://169.254.169.254/opc/v2/vnics/ 2>/dev/null || true)"

  if [ -z "$payload" ]; then
    payload="$(curl -fsS --connect-timeout 3 \
      http://169.254.169.254/opc/v1/vnics/ 2>/dev/null || true)"
  fi

  if [ -z "$payload" ]; then
    return 1
  fi

  public_ip="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    vnics = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for vnic in vnics if isinstance(vnics, list) else []:
    public_ip = vnic.get("publicIp")
    if public_ip:
        print(public_ip)
        break
' 2>/dev/null || true)"

  if [ -z "$public_ip" ]; then
    public_ip="$(discover_public_ip_from_internet || true)"
  fi

  if [ -z "$public_ip" ]; then
    public_ip="$(prompt_for_public_ip || true)"
  fi

  printf '%s\n' "$public_ip"
}

ensure_tls_certificate() {
  local public_host="$1"
  local tls_dir="${SCRIPT_DIR}/tls"
  local cert_file="${tls_dir}/web-hr-app.crt"
  local key_file="${tls_dir}/web-hr-app.key"
  local config_file="${tls_dir}/web-hr-app-openssl.cnf"
  local san_line=""

  if ! command -v openssl >/dev/null 2>&1; then
    echo "ERROR: openssl is required to create a demo HTTPS certificate." >&2
    echo "       Install openssl or use --localhost for local-only HTTP." >&2
    return 1
  fi

  mkdir -p "$tls_dir"
  chmod 700 "$tls_dir"

  if is_ipv4 "$public_host"; then
    san_line="IP.1 = ${public_host}"
  else
    san_line="DNS.1 = ${public_host}"
  fi

  cat > "$config_file" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_req

[dn]
CN = ${public_host}

[v3_req]
subjectAltName = @alt_names

[alt_names]
${san_line}
EOF

  echo "Creating or replacing demo HTTPS certificate for ${public_host}:"
  echo "  Certificate = ${cert_file}"
  echo "  Private key = ${key_file}"
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$key_file" \
    -out "$cert_file" \
    -days 30 \
    -config "$config_file" >/dev/null 2>&1
  chmod 600 "$cert_file" "$key_file"

  WEB_HR_TLS_CERT_TO_WRITE="$cert_file"
  WEB_HR_TLS_KEY_TO_WRITE="$key_file"
}

discover_public_ip_from_internet() {
  local public_ip=""
  local service

  for service in \
    "https://api.ipify.org" \
    "https://ifconfig.me/ip" \
    "https://icanhazip.com"
  do
    public_ip="$(curl -fsS --connect-timeout 5 "$service" 2>/dev/null | tr -d '[:space:]' || true)"
    if is_ipv4 "$public_ip"; then
      echo "Using public IP discovered from ${service}: ${public_ip}" >&2
      printf '%s\n' "$public_ip"
      return 0
    fi
  done

  return 1
}

prompt_for_public_ip() {
  local public_ip=""

  if [ ! -t 0 ]; then
    return 1
  fi

  echo "Could not automatically discover the VM public IP." >&2
  echo "Enter the public IP address for this DBSec-Lab VM." >&2
  echo "You can find it in the OCI Console, or paste the IP you use in your browser." >&2
  while true; do
    read -r -p "Public IP: " public_ip
    public_ip="$(printf '%s' "$public_ip" | tr -d '[:space:]')"
    if is_ipv4 "$public_ip"; then
      printf '%s\n' "$public_ip"
      return 0
    fi
    echo "That does not look like an IPv4 address. Try again, or press Ctrl+C to stop." >&2
  done
}

is_ipv4() {
  python3 - "$1" <<'PY'
import ipaddress
import sys
try:
    ipaddress.IPv4Address(sys.argv[1])
except Exception:
    sys.exit(1)
PY
}

is_local_http_redirect() {
  case "$1" in
    http://localhost:*|http://127.0.0.1:*|http://[::1]:*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

validate_redirect_uri() {
  local uri="$1"

  case "$uri" in
    https://*)
      return 0
      ;;
    http://*)
      if is_local_http_redirect "$uri"; then
        return 0
      fi
      echo "ERROR: Microsoft Entra ID requires public reply URLs to use https." >&2
      echo "       Use: ./00_setup_entra_web_app.sh --redirect-uri https://<public-ip>:${WEB_HR_PORT}/callback" >&2
      echo "       Or local-only mode: ./00_setup_entra_web_app.sh --localhost" >&2
      return 1
      ;;
    *)
      echo "ERROR: Redirect URI must start with https://, or http://localhost for local-only mode." >&2
      return 1
      ;;
  esac
}

WEB_HR_APP_NAME="${WEB_HR_APP_NAME:-Web HR App - ${PDB_NAME}}"
WEB_HR_PORT="${WEB_HR_PORT:-8012}"
WEB_HR_HOST_TO_WRITE="${WEB_HR_HOST:-}"
WEB_HR_TLS_CERT_TO_WRITE="${WEB_HR_TLS_CERT:-}"
WEB_HR_TLS_KEY_TO_WRITE="${WEB_HR_TLS_KEY:-}"
if [ -n "${WEB_HR_REDIRECT_URI:-}" ] && [ "$REDIRECT_MODE_EXPLICIT" -eq 0 ]; then
  unset WEB_HR_REDIRECT_URI
fi

if [ -n "$REDIRECT_URI_ARG" ]; then
  WEB_HR_REDIRECT_URI="$REDIRECT_URI_ARG"
  validate_redirect_uri "$WEB_HR_REDIRECT_URI"
  PUBLIC_IP_REDIRECT=0
  case "$WEB_HR_REDIRECT_URI" in
    http://localhost:*|http://127.0.0.1:*|http://[::1]:*)
      WEB_HR_HOST_TO_WRITE=""
      WEB_HR_TLS_CERT_TO_WRITE=""
      WEB_HR_TLS_KEY_TO_WRITE=""
      ;;
    *)
      WEB_HR_HOST_TO_WRITE="${WEB_HR_HOST_TO_WRITE:-0.0.0.0}"
      if [[ "$WEB_HR_REDIRECT_URI" == https://* ]]; then
        redirect_host="$(printf '%s' "$WEB_HR_REDIRECT_URI" | python3 -c 'from urllib.parse import urlparse; import sys; print(urlparse(sys.stdin.read().strip()).hostname or "")')"
        ensure_tls_certificate "$redirect_host"
      fi
      ;;
  esac
elif [ "$PUBLIC_IP_REDIRECT" -eq 1 ]; then
  public_ip="$(discover_public_ip || true)"
  if [ -z "$public_ip" ]; then
    echo "ERROR: Could not discover or prompt for a public IP."
    echo "       Use: ./00_setup_entra_web_app.sh --redirect-uri https://<public-ip>:${WEB_HR_PORT}/callback"
    echo "       Or use local-only mode: ./00_setup_entra_web_app.sh --localhost"
    exit 1
  fi
  WEB_HR_REDIRECT_URI="https://${public_ip}:${WEB_HR_PORT}/callback"
  WEB_HR_HOST_TO_WRITE="${WEB_HR_HOST_TO_WRITE:-0.0.0.0}"
  ensure_tls_certificate "$public_ip"
elif [ "$LOCALHOST_REDIRECT" -eq 1 ]; then
  WEB_HR_REDIRECT_URI="http://localhost:${WEB_HR_PORT}/callback"
  WEB_HR_HOST_TO_WRITE=""
  WEB_HR_TLS_CERT_TO_WRITE=""
  WEB_HR_TLS_KEY_TO_WRITE=""
else
  WEB_HR_REDIRECT_URI="${WEB_HR_REDIRECT_URI:-http://localhost:${WEB_HR_PORT}/callback}"
fi
WEB_HR_USER_SCOPE_VALUE="${WEB_HR_USER_SCOPE_VALUE:-user_access}"
WEB_HR_DB_SCOPE_VALUE="${ENTRA_SCOPE_VALUE:-session:scope:connect}"
WEB_HR_DB_SCOPE="${APP_ID_URI}/${WEB_HR_DB_SCOPE_VALUE}"
WEB_HR_TOKEN_URI="https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token"
WEB_HR_AUTH_URI="https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/authorize"

json_get_or_empty() {
  python3 -c "import json,sys; data=json.load(sys.stdin); print(${1} or '')"
}

new_uuid() {
  python3 -c 'import uuid; print(uuid.uuid4())'
}

find_app_json() {
  local display_name="$1"
  az ad app list --display-name "$display_name" -o json | APP_NAME="$display_name" python3 -c '
import json, os, sys
name = os.environ["APP_NAME"]
apps = json.load(sys.stdin)
match = next((a for a in apps if a.get("displayName") == name), {})
print(json.dumps(match))
'
}

graph_patch() {
  local uri="$1"
  local body_file="$2"
  az rest --method PATCH \
    --uri "$uri" \
    --headers "Content-Type=application/json" \
    --body @"$body_file" >/dev/null
}

ensure_service_principal() {
  local app_id="$1"
  if az ad sp show --id "$app_id" >/dev/null 2>&1; then
    return
  fi
  az ad sp create --id "$app_id" >/dev/null
}

echo "Using existing database app:"
echo "  APP_ID      = ${APP_ID}"
echo "  APP_ID_URI  = ${APP_ID_URI}"
echo "  TENANT_ID   = ${TENANT_ID}"
echo "  REDIRECT    = ${WEB_HR_REDIRECT_URI}"
echo

db_app_full=$(az ad app show --id "$APP_ID" -o json)
db_scope_id=$(printf '%s' "$db_app_full" | WEB_HR_DB_SCOPE_VALUE="$WEB_HR_DB_SCOPE_VALUE" python3 -c 'import json,os,sys; d=json.load(sys.stdin); v=os.environ.get("WEB_HR_DB_SCOPE_VALUE","session:scope:connect"); print(next((s["id"] for s in d.get("api",{}).get("oauth2PermissionScopes",[]) if s.get("value")==v), ""))')
if [ -z "$db_scope_id" ]; then
  echo "ERROR: Database app scope not found: ${WEB_HR_DB_SCOPE_VALUE}"
  exit 1
fi

app_json=$(find_app_json "$WEB_HR_APP_NAME")
app_object_id=$(printf '%s' "$app_json" | json_get_or_empty 'data.get("id")')
app_client_id=$(printf '%s' "$app_json" | json_get_or_empty 'data.get("appId")')

if [ -z "$app_client_id" ]; then
  app_json=$(az ad app create \
    --display-name "$WEB_HR_APP_NAME" \
    --sign-in-audience AzureADMyOrg \
    --web-redirect-uris "$WEB_HR_REDIRECT_URI" \
    -o json)
  app_object_id=$(printf '%s' "$app_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  app_client_id=$(printf '%s' "$app_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["appId"])')
  echo "Created Web HR App: ${app_client_id}"
else
  echo "Reusing Web HR App: ${app_client_id}"
  echo "Updating Web HR App configuration:"
  echo "  Redirect URI             = ${WEB_HR_REDIRECT_URI}"
  echo "  Identifier URI           = api://${app_client_id}"
  echo "  User delegated scope     = ${WEB_HR_USER_SCOPE_VALUE}"
  echo "  Database delegated scope = ${WEB_HR_DB_SCOPE}"
fi
ensure_service_principal "$app_client_id"

app_full=$(az ad app show --id "$app_client_id" -o json)
user_scope_id=$(printf '%s' "$app_full" | WEB_HR_USER_SCOPE_VALUE="$WEB_HR_USER_SCOPE_VALUE" python3 -c 'import json,os,sys; d=json.load(sys.stdin); v=os.environ["WEB_HR_USER_SCOPE_VALUE"]; print(next((s["id"] for s in d.get("api",{}).get("oauth2PermissionScopes",[]) if s.get("value")==v), ""))')
[ -n "$user_scope_id" ] || user_scope_id=$(new_uuid)

patch=$(mktemp)
APP_CLIENT_ID="$app_client_id" \
WEB_HR_REDIRECT_URI="$WEB_HR_REDIRECT_URI" \
WEB_HR_USER_SCOPE_VALUE="$WEB_HR_USER_SCOPE_VALUE" \
USER_SCOPE_ID="$user_scope_id" \
DB_APP_ID="$APP_ID" \
DB_SCOPE_ID="$db_scope_id" \
python3 - <<'PY' > "$patch"
import json, os
print(json.dumps({
    "web": {
        "redirectUris": [os.environ["WEB_HR_REDIRECT_URI"]],
        "implicitGrantSettings": {
            "enableAccessTokenIssuance": False,
            "enableIdTokenIssuance": True,
        },
    },
    "identifierUris": ["api://%s" % os.environ["APP_CLIENT_ID"]],
    "api": {
        "oauth2PermissionScopes": [{
            "adminConsentDescription": "Access Web HR App as the signed-in user",
            "adminConsentDisplayName": "Access Web HR App",
            "id": os.environ["USER_SCOPE_ID"],
            "isEnabled": True,
            "type": "User",
            "userConsentDescription": "Access Web HR App as the signed-in user",
            "userConsentDisplayName": "Access Web HR App",
            "value": os.environ["WEB_HR_USER_SCOPE_VALUE"],
        }]
    },
    "requiredResourceAccess": [{
        "resourceAppId": os.environ["DB_APP_ID"],
        "resourceAccess": [{
            "id": os.environ["DB_SCOPE_ID"],
            "type": "Scope",
        }],
    }],
}))
PY
graph_patch "https://graph.microsoft.com/v1.0/applications/${app_object_id}" "$patch"
rm -f "$patch"

echo "Creating a client secret for the application pool token flow..."
secret=$(az ad app credential reset \
  --id "$app_client_id" \
  --display-name "web-hr-app-lab-secret" \
  --append \
  --query password \
  --output tsv)

if az ad app permission admin-consent --id "$app_client_id" >/dev/null 2>&1; then
  echo "Admin consent granted for Web HR App."
else
  echo "WARNING: Could not grant admin consent automatically."
  echo "Grant admin consent for ${WEB_HR_APP_NAME} in the Azure portal."
fi

cat > "$ENV_FILE" <<EOF
export TENANT_ID='${TENANT_ID}'
export DOMAIN_NAME='${DOMAIN_NAME:-}'
export PDB_NAME='${PDB_NAME}'
export APP_ID='${APP_ID}'
export APP_ID_URI='${APP_ID_URI}'
export WEB_HR_APP_NAME='${WEB_HR_APP_NAME}'
export WEB_HR_APP_CLIENT_ID='${app_client_id}'
export WEB_HR_APP_CLIENT_SECRET='${secret}'
export WEB_HR_REDIRECT_URI='${WEB_HR_REDIRECT_URI}'
export WEB_HR_USER_SCOPE='api://${app_client_id}/${WEB_HR_USER_SCOPE_VALUE}'
export WEB_HR_DB_SCOPE='${APP_ID_URI}/${WEB_HR_DB_SCOPE_VALUE}'
export WEB_HR_APP_DB_SCOPE='${APP_ID_URI}/.default'
export WEB_HR_TOKEN_URI='${WEB_HR_TOKEN_URI}'
export WEB_HR_AUTH_URI='${WEB_HR_AUTH_URI}'
EOF
if [ -n "$WEB_HR_HOST_TO_WRITE" ]; then
  cat >> "$ENV_FILE" <<EOF
export WEB_HR_HOST='${WEB_HR_HOST_TO_WRITE}'
EOF
fi
if [ -n "$WEB_HR_TLS_CERT_TO_WRITE" ] && [ -n "$WEB_HR_TLS_KEY_TO_WRITE" ]; then
  cat >> "$ENV_FILE" <<EOF
export WEB_HR_TLS_CERT='${WEB_HR_TLS_CERT_TO_WRITE}'
export WEB_HR_TLS_KEY='${WEB_HR_TLS_KEY_TO_WRITE}'
EOF
fi
chmod 600 "$ENV_FILE"

echo
echo "Saved: ${ENV_FILE}"
echo "Next:"
echo "source ./.web-hr-app.env"
if [ "$PUBLIC_IP_REDIRECT" -eq 1 ] || [ -n "$REDIRECT_URI_ARG" ]; then
  echo "./run.sh"
else
  echo "./01_configure_database_app_identity.sh"
fi
