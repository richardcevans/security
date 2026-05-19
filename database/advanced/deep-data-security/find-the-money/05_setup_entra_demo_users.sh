#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIND_MONEY_ENV="${FIND_MONEY_ENV:-${SCRIPT_DIR}/.find-the-money.env}"

find_first_file() {
  local candidate
  for candidate in "$@"; do
    if [ -f "$candidate" ]; then
      printf '%s' "$candidate"
      return
    fi
  done
}

ENTRA_LAB_ENV="${ENTRA_LAB_ENV:-$(find_first_file \
  "${SCRIPT_DIR}/../entra-id-data-grants/.entra-id-data-grants.env" \
  "/home/oracle/DBSecLab/livelabs/deep-data-security/entra-id-data-grants/.entra-id-data-grants.env" \
  "/home/oracle/livelabs/entra-id-data-grants/.entra-id-data-grants.env" \
)}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

if ! command -v az >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Azure CLI is required.${NC}"
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Azure CLI is not logged in.${NC}"
  echo -e "${YELLOW}Run: az login${NC}"
  exit 1
fi

if [ -f "$ENTRA_LAB_ENV" ]; then
  # shellcheck disable=SC1090
  source "$ENTRA_LAB_ENV"
fi

if [ -f "$FIND_MONEY_ENV" ]; then
  # shellcheck disable=SC1090
  source "$FIND_MONEY_ENV"
fi

: "${APP_ID:?APP_ID is required from ${ENTRA_LAB_ENV} or ${FIND_MONEY_ENV}}"

discover_domain_name() {
  local discovered
  discovered=$(az rest --method GET \
    --uri "https://graph.microsoft.com/v1.0/domains?\$filter=isDefault eq true" \
    --query "value[0].id" \
    --output tsv 2>/dev/null || true)
  if [ -n "$discovered" ]; then
    printf '%s' "$discovered"
    return
  fi

  discovered=$(az ad signed-in-user show \
    --query userPrincipalName \
    --output tsv 2>/dev/null | awk -F@ 'NF == 2 { print $2; exit }' || true)
  printf '%s' "$discovered"
}

DOMAIN_NAME="${DOMAIN_NAME:-$(discover_domain_name)}"
if [ -z "$DOMAIN_NAME" ]; then
  echo -e "${RED}ERROR: Could not discover the default Entra domain.${NC}"
  echo -e "${YELLOW}Set DOMAIN_NAME, for example: export DOMAIN_NAME=example.onmicrosoft.com${NC}"
  exit 1
fi

FIND_MONEY_DEMO_PASSWORD="${FIND_MONEY_DEMO_PASSWORD:-$(python3 -c 'import secrets,string; alphabet=string.ascii_letters+string.digits+"#@!"; print("Fm26!"+"".join(secrets.choice(alphabet) for _ in range(18)))')}"
RESET_FIND_MONEY_PASSWORDS="${RESET_FIND_MONEY_PASSWORDS:-0}"

ALEX_UPN="${ALEX_UPN:-alex@${DOMAIN_NAME}}"
PRIYA_UPN="${PRIYA_UPN:-priya@${DOMAIN_NAME}}"
MARCUS_UPN="${MARCUS_UPN:-marcus@${DOMAIN_NAME}}"
NORA_UPN="${NORA_UPN:-nora@${DOMAIN_NAME}}"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 5: Create Find the Money Entra Demo Users and Roles              ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}  DOMAIN_NAME = ${DOMAIN_NAME}${NC}"
echo -e "${CYAN}  APP_ID      = ${APP_ID}${NC}"
echo

db_app_json=$(az ad app show --id "$APP_ID" -o json)
db_object_id=$(printf '%s' "$db_app_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')

ensure_service_principal() {
  local app_id="$1"
  if az ad sp show --id "$app_id" >/dev/null 2>&1; then
    return
  fi
  az ad sp create --id "$app_id" >/dev/null
}

ensure_service_principal "$APP_ID"
db_sp_id=$(az ad sp show --id "$APP_ID" --query id --output tsv)

echo -e "${YELLOW}Step 1: Ensuring FIN app roles on the reused database app...${NC}"
roles_patch=$(mktemp)
DB_APP_JSON="$db_app_json" python3 - <<'PY' > "$roles_patch"
import json
import os
import sys
import uuid

app = json.loads(os.environ["DB_APP_JSON"])
roles = app.get("appRoles") or []
required = [
    ("FINAPP_TELLERS", "Find the Money tellers"),
    ("FINAPP_INVESTIGATORS", "Find the Money investigators"),
    ("FINAPP_SENIOR_INVESTIGATORS", "Find the Money senior investigators"),
    ("FINAPP_AUDITORS", "Find the Money auditors"),
]

by_value = {role.get("value"): role for role in roles}
for value, description in required:
    role = by_value.get(value)
    if role:
        role["isEnabled"] = True
        role["allowedMemberTypes"] = sorted(set(role.get("allowedMemberTypes") or ["User"]))
        if "User" not in role["allowedMemberTypes"]:
            role["allowedMemberTypes"].append("User")
        continue
    roles.append({
        "allowedMemberTypes": ["User"],
        "description": description,
        "displayName": value,
        "id": str(uuid.uuid4()),
        "isEnabled": True,
        "value": value,
    })

print(json.dumps({"appRoles": roles}))
PY

az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/${db_object_id}" \
  --headers "Content-Type=application/json" \
  --body @"$roles_patch" \
  >/dev/null
rm -f "$roles_patch"

db_app_json=$(az ad app show --id "$APP_ID" -o json)
role_id_for() {
  local role_name="$1"
  printf '%s' "$db_app_json" | ROLE_NAME="$role_name" python3 -c 'import json,os,sys; d=json.load(sys.stdin); print(next((r["id"] for r in d.get("appRoles", []) if r.get("value") == os.environ["ROLE_NAME"]), ""))'
}

FINAPP_TELLERS_ROLE_ID=$(role_id_for FINAPP_TELLERS)
FINAPP_INVESTIGATORS_ROLE_ID=$(role_id_for FINAPP_INVESTIGATORS)
FINAPP_SENIOR_INVESTIGATORS_ROLE_ID=$(role_id_for FINAPP_SENIOR_INVESTIGATORS)
FINAPP_AUDITORS_ROLE_ID=$(role_id_for FINAPP_AUDITORS)

echo -e "${CYAN}  Ensured FINAPP_TELLERS, FINAPP_INVESTIGATORS, FINAPP_SENIOR_INVESTIGATORS, FINAPP_AUDITORS.${NC}"
echo

ensure_user() {
  local upn="$1"
  local display_name="$2"
  local mail_nickname="$3"
  local user_id

  user_id=$(az ad user show --id "$upn" --query id --output tsv 2>/dev/null || true)
  if [ -n "$user_id" ]; then
    echo -e "${CYAN}  User already exists: ${upn}${NC}"
    if [ "$RESET_FIND_MONEY_PASSWORDS" = "1" ]; then
      az ad user update \
        --id "$upn" \
        --password "$FIND_MONEY_DEMO_PASSWORD" \
        --force-change-password-next-sign-in false \
        >/dev/null
      echo -e "${CYAN}  Password reset for: ${upn}${NC}"
    fi
    return
  fi

  az ad user create \
    --display-name "$display_name" \
    --user-principal-name "$upn" \
    --mail-nickname "$mail_nickname" \
    --password "$FIND_MONEY_DEMO_PASSWORD" \
    --force-change-password-next-sign-in false \
    >/dev/null
  echo -e "${CYAN}  Created user: ${upn}${NC}"
}

assign_role_to_user() {
  local upn="$1"
  local role_name="$2"
  local role_id="$3"
  local user_id
  local existing
  local body

  user_id=$(az ad user show --id "$upn" --query id --output tsv 2>/dev/null || true)
  if [ -z "$user_id" ]; then
    echo -e "${YELLOW}  WARNING: User not found, skipping ${role_name}: ${upn}${NC}"
    return
  fi

  existing=$(az rest --method GET \
    --uri "https://graph.microsoft.com/v1.0/users/${user_id}/appRoleAssignments" \
    --query "value[?resourceId=='${db_sp_id}' && appRoleId=='${role_id}'].id | [0]" \
    --output tsv 2>/dev/null || true)

  if [ -n "$existing" ]; then
    echo -e "${CYAN}  Assignment already exists: ${upn} -> ${role_name}${NC}"
    return
  fi

  body=$(mktemp)
  USER_ID="$user_id" SP_ID="$db_sp_id" ROLE_ID="$role_id" python3 - <<'PY' > "$body"
import json
import os
print(json.dumps({
    "principalId": os.environ["USER_ID"],
    "resourceId": os.environ["SP_ID"],
    "appRoleId": os.environ["ROLE_ID"],
}))
PY

  az rest --method POST \
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${db_sp_id}/appRoleAssignedTo" \
    --headers "Content-Type=application/json" \
    --body @"$body" \
    >/dev/null
  rm -f "$body"
  echo -e "${CYAN}  Assigned ${upn} -> ${role_name}${NC}"
}

echo -e "${YELLOW}Step 2: Creating or reusing demo users...${NC}"
ensure_user "$ALEX_UPN" "Alex Teller" "alex"
ensure_user "$PRIYA_UPN" "Priya Investigator" "priya"
ensure_user "$MARCUS_UPN" "Marcus Senior Investigator" "marcus"
ensure_user "$NORA_UPN" "Nora Auditor" "nora"
echo

echo -e "${YELLOW}Step 3: Assigning FIN app roles...${NC}"
assign_role_to_user "$ALEX_UPN" "FINAPP_TELLERS" "$FINAPP_TELLERS_ROLE_ID"
assign_role_to_user "$PRIYA_UPN" "FINAPP_TELLERS" "$FINAPP_TELLERS_ROLE_ID"
assign_role_to_user "$PRIYA_UPN" "FINAPP_INVESTIGATORS" "$FINAPP_INVESTIGATORS_ROLE_ID"
assign_role_to_user "$MARCUS_UPN" "FINAPP_TELLERS" "$FINAPP_TELLERS_ROLE_ID"
assign_role_to_user "$MARCUS_UPN" "FINAPP_INVESTIGATORS" "$FINAPP_INVESTIGATORS_ROLE_ID"
assign_role_to_user "$MARCUS_UPN" "FINAPP_SENIOR_INVESTIGATORS" "$FINAPP_SENIOR_INVESTIGATORS_ROLE_ID"
assign_role_to_user "$NORA_UPN" "FINAPP_AUDITORS" "$FINAPP_AUDITORS_ROLE_ID"

cat >> "$FIND_MONEY_ENV" <<EOF
export ALEX_UPN='${ALEX_UPN}'
export PRIYA_UPN='${PRIYA_UPN}'
export MARCUS_UPN='${MARCUS_UPN}'
export NORA_UPN='${NORA_UPN}'
EOF

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 5 Completed: Demo Users and FIN Roles Ready                      ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}Demo users:${NC}"
echo -e "${CYAN}  Alex   ${ALEX_UPN}   FINAPP_TELLERS${NC}"
echo -e "${CYAN}  Priya  ${PRIYA_UPN}  FINAPP_TELLERS, FINAPP_INVESTIGATORS${NC}"
echo -e "${CYAN}  Marcus ${MARCUS_UPN} FINAPP_TELLERS, FINAPP_INVESTIGATORS, FINAPP_SENIOR_INVESTIGATORS${NC}"
echo -e "${CYAN}  Nora   ${NORA_UPN}   FINAPP_AUDITORS${NC}"
echo
if [ "$RESET_FIND_MONEY_PASSWORDS" = "1" ]; then
  echo -e "${YELLOW}Existing users were reset to this password.${NC}"
else
  echo -e "${YELLOW}New users were created with this password. Existing users were not reset.${NC}"
fi
echo -e "${CYAN}  FIND_MONEY_DEMO_PASSWORD=${FIND_MONEY_DEMO_PASSWORD}${NC}"
echo
