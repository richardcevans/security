#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTRA_LAB_ENV="${ENTRA_LAB_ENV:-${SCRIPT_DIR}/../entra-id-data-grants/.entra-id-data-grants.env}"
ENV_FILE="${SCRIPT_DIR}/.web-hr-app.env"

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

WEB_HR_APP_NAME="${WEB_HR_APP_NAME:-Web HR App - ${PDB_NAME}}"
WEB_HR_REDIRECT_URI="${WEB_HR_REDIRECT_URI:-http://localhost:8012/callback}"
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
chmod 600 "$ENV_FILE"

echo
echo "Saved: ${ENV_FILE}"
echo "Next:"
echo "source ./.web-hr-app.env"
echo "./01_configure_database_app_identity.sh"
