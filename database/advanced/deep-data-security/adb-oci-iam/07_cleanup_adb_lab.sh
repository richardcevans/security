#!/bin/bash
# Remove ADB OCI IAM lab database objects. Optionally remove OCI resources too.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

DELETE_ADB=false
DELETE_DB_OBJECTS=false
DELETE_IAM_USERS=false
DELETE_IAM_GROUPS=false
DELETE_IAM_APPS=false
DELETE_ALL_LAB_APPS=false
DELETE_LOCAL_FILES=false
REMOVE_ALL=false
FORCE=false
ENV_FILE=""
CLEANUP_FAILURES=()
CLEANUP_COMPLETED=()
CLEANUP_NOT_COMPLETED=()
ACTION_SELECTED=false

for arg in "$@"; do
  case "$arg" in
    --delete-adb)
      DELETE_ADB=true
      ACTION_SELECTED=true
      ;;
    --delete-db-objects)
      DELETE_DB_OBJECTS=true
      ACTION_SELECTED=true
      ;;
    --delete-iam-users)
      DELETE_IAM_USERS=true
      ACTION_SELECTED=true
      ;;
    --delete-iam-groups)
      DELETE_IAM_GROUPS=true
      ACTION_SELECTED=true
      ;;
    --delete-iam-apps)
      DELETE_IAM_APPS=true
      ACTION_SELECTED=true
      ;;
    --delete-all-lab-apps)
      DELETE_ALL_LAB_APPS=true
      ACTION_SELECTED=true
      ;;
    --delete-local-files)
      DELETE_LOCAL_FILES=true
      ACTION_SELECTED=true
      ;;
    --remove-all)
      REMOVE_ALL=true
      DELETE_ADB=true
      DELETE_DB_OBJECTS=true
      DELETE_IAM_USERS=true
      DELETE_IAM_GROUPS=true
      DELETE_IAM_APPS=true
      DELETE_LOCAL_FILES=true
      ACTION_SELECTED=true
      ;;
    --env-file=*)
      ENV_FILE="${arg#*=}"
      ;;
    -f|--force|--DELETE)
      FORCE=true
      ;;
    *)
      echo "Usage: $0 [--env-file=path] [--delete-db-objects] [--delete-adb] [--delete-iam-users] [--delete-iam-groups] [--delete-iam-apps] [--delete-all-lab-apps] [--delete-local-files] [--remove-all] [-f|--force|--DELETE]" >&2
      exit 2
      ;;
  esac
done

# Preserve the original no-argument behavior, but never mix database cleanup
# into an explicitly selected OCI IAM or local-file cleanup action.
if [ "$ACTION_SELECTED" = false ]; then
  DELETE_DB_OBJECTS=true
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -n "$ENV_FILE" ]; then
  if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: Environment file not found: ${ENV_FILE}" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
source "${SCRIPT_DIR}/lib_adb.sh"

require_adb_delete_env() {
  local missing=false
  for var in ADB_OCID DB_NAME; do
    if [ -z "${!var:-}" ]; then
      echo "ERROR: ${var} is required for --delete-adb." >&2
      missing=true
    fi
  done
  if [ "$missing" = true ]; then
    echo "Next: set ADB_OCID and DB_NAME in an environment file, then retry." >&2
    exit 1
  fi
}

if [ "$DELETE_DB_OBJECTS" = true ]; then
  require_adb_env
  require_wallet_files
fi
if [ "$DELETE_ADB" = true ]; then
  require_adb_delete_env
fi

confirm() {
  local prompt="$1"

  if [ "$FORCE" = true ]; then
    return 0
  fi

  echo -n "$prompt Type DELETE to continue: "
  read -r answer
  [ "$answer" = "DELETE" ]
}

record_cleanup_failure() {
  CLEANUP_FAILURES+=("$1")
}

cleanup_label() {
  case "$1" in
    Deleting\ *) printf 'Deleted %s' "${1#Deleting }" ;;
    Removing\ *) printf 'Removed %s' "${1#Removing }" ;;
    Deactivating\ *) printf 'Deactivated %s' "${1#Deactivating }" ;;
    *) printf '%s' "$1" ;;
  esac
}

cleanup_target() {
  case "$1" in
    Deleting\ *) printf '%s' "${1#Deleting }" ;;
    Removing\ *) printf '%s' "${1#Removing }" ;;
    Deactivating\ *) printf '%s' "${1#Deactivating }" ;;
    *) printf '%s' "$1" ;;
  esac
}

record_completed() {
  CLEANUP_COMPLETED+=("$(cleanup_label "$1")")
}

record_not_completed() {
  CLEANUP_NOT_COMPLETED+=("$1")
}

run_cleanup_cmd() {
  local description="$1"
  shift
  local command_output status oci_status detail next_step

  echo -ne "${CYAN}${description}... ${NC}"
  if command_output=$("$@" 2>&1); then
    echo -e "${CYAN}  OK${NC}"
    record_completed "$description"
  else
    status=$?
    oci_status=$(printf '%s\n' "$command_output" | sed -nE 's/^[[:space:]]*"status": ([0-9]+),?$/\1/p' | head -n 1)
    detail=$(printf '%s\n' "$command_output" | sed -nE 's/^[[:space:]]*"detail": "(.*)",?$/\1/p' | head -n 1)
    detail="${detail:-${command_output##*$'\n'}}"
    detail="${detail:-Command failed without a detailed error message.}"

    if [ "$oci_status" = "404" ]; then
      echo -e "${YELLOW}already absent (OCI status 404)${NC}"
      record_not_completed "$(cleanup_target "$description") — already absent"
      return 0
    fi

    case "$oci_status" in
      400)
        next_step="Verify the resource state and required cleanup order, then retry."
        ;;
      401)
        next_step="Refresh your OCI session or API key credentials, then retry."
        ;;
      403)
        next_step="Ask an identity or tenancy administrator for the required permission, then retry."
        ;;
      *)
        next_step="Review the OCI CLI configuration and resource identifiers, then retry."
        ;;
    esac

    if [ -n "$oci_status" ]; then
      echo -e "${RED}ERROR (OCI status ${oci_status})${NC}"
    else
      echo -e "${RED}ERROR (command exit ${status})${NC}"
    fi
    echo "  Cause: ${detail}"
    echo "  Next: ${next_step}"
    record_cleanup_failure "${description} failed${oci_status:+ (OCI status ${oci_status})}"
    record_not_completed "$(cleanup_target "$description") — ${detail}"
  fi
}

delete_domain_app() {
  local app_id="${1:-}"
  local app_name="$2"
  local discovered_app_id

  if [ -z "${OCI_DOMAIN_URL:-}" ]; then
    echo -e "${YELLOW}Skipping ${app_name}; OCI_DOMAIN_URL is not set.${NC}"
    record_not_completed "OCI IAM app ${app_name} — OCI_DOMAIN_URL is not set"
    return 0
  fi

  if [ -z "$app_id" ] || [ "$app_id" = "null" ]; then
    discovered_app_id=$(oci_with_profile identity-domains apps list \
      --endpoint "$OCI_DOMAIN_URL" \
      --all \
      --attribute-sets all \
      --filter "displayName eq \"${app_name}\"" \
      --query 'data.Resources[0].id' \
      --raw-output 2>/dev/null || true)
    if [ -z "$discovered_app_id" ] || [ "$discovered_app_id" = "null" ]; then
      discovered_app_id=$(oci_with_profile identity-domains apps list \
        --endpoint "$OCI_DOMAIN_URL" \
        --all \
        --attribute-sets all \
        --filter "displayName eq \"${app_name}\"" \
        --query 'data.resources[0].id' \
        --raw-output 2>/dev/null || true)
    fi
    if [ -n "$discovered_app_id" ] && [ "$discovered_app_id" != "null" ]; then
      app_id="$discovered_app_id"
    fi
  fi

  if [ -z "$app_id" ] || [ "$app_id" = "null" ]; then
    echo -e "${YELLOW}Skipping ${app_name}; no matching application was found.${NC}"
    record_not_completed "OCI IAM app ${app_name} — already absent or not discoverable"
    return 0
  fi

  run_cleanup_cmd "Deactivating OCI IAM app ${app_name}" \
    oci_with_profile identity-domains app patch \
      --endpoint "$OCI_DOMAIN_URL" \
      --app-id "$app_id" \
      --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
      --operations '[{"op":"replace","path":"active","value":false}]'

  run_cleanup_cmd "Deleting OCI IAM app ${app_name}" \
    oci_with_profile identity-domains app delete \
      --endpoint "$OCI_DOMAIN_URL" \
      --app-id "$app_id" \
      --force-delete true \
      --force
}

list_domain_apps_matching() {
  local name_fragment="$1"
  local app_list

  if [ -z "${OCI_DOMAIN_URL:-}" ]; then
    echo "ERROR: OCI_DOMAIN_URL is not set; cannot list applications matching ${name_fragment}." >&2
    return 1
  fi

  if ! app_list=$(oci_with_profile identity-domains apps list \
    --endpoint "$OCI_DOMAIN_URL" \
    --all \
    --attribute-sets all \
    --filter "displayName co \"${name_fragment}\"" \
    --output json 2>/dev/null | APP_NAME_FRAGMENT="$name_fragment" python3 -c '
import json
import os
import sys

try:
    data = json.load(sys.stdin).get("data", {})
except (json.JSONDecodeError, AttributeError):
    raise SystemExit(1)

resources = data.get("Resources") or data.get("resources") or []
needle = os.environ["APP_NAME_FRAGMENT"]
for resource in resources:
    # OCI CLI JSON commonly uses kebab-case; retain the SCIM spellings too.
    name = (resource.get("display-name") or resource.get("displayName")
            or resource.get("display_name") or "")
    resource_id = resource.get("id") or ""
    if resource_id and needle in name:
        print("{}|{}".format(resource_id, name))
' 2>/dev/null); then
    echo "ERROR: Could not list OCI IAM applications matching ${name_fragment}." >&2
    record_cleanup_failure "Listing OCI IAM apps matching ${name_fragment} failed"
    record_not_completed "OCI IAM apps matching ${name_fragment} — could not list"
    return 1
  fi

  printf '%s' "$app_list"
}

show_domain_app_deletion_plan() {
  local app_list="$1"
  local app_id app_name app_count=0

  echo -e "${YELLOW}The following OCI IAM Integrated Applications will be deactivated, then deleted:${NC}"
  while IFS='|' read -r app_id app_name; do
    [ -z "$app_id" ] && continue
    app_count=$((app_count + 1))
    echo "  ${app_count}. ${app_name}"
    echo "     ${app_id}"
  done <<< "$app_list"
  [ "$app_count" -gt 0 ]
}

delete_domain_app_plan() {
  local app_list="$1"
  local app_id app_name

  while IFS='|' read -r app_id app_name; do
    [ -z "$app_id" ] && continue
    delete_domain_app "$app_id" "$app_name"
  done <<< "$app_list"
}

delete_domain_apps_matching() {
  local name_fragment="$1"
  local app_list

  if ! app_list=$(list_domain_apps_matching "$name_fragment"); then
    return 1
  fi

  if [ -z "$app_list" ]; then
    echo -e "${YELLOW}No OCI IAM applications matching ${name_fragment} were found.${NC}"
    record_not_completed "OCI IAM apps matching ${name_fragment} — already absent"
    return 0
  fi

  delete_domain_app_plan "$app_list"
}

preview_and_delete_domain_apps() {
  local prompt="$1"
  shift
  local fragment app_list combined_plan=""

  for fragment in "$@"; do
    if ! app_list=$(list_domain_apps_matching "$fragment"); then
      echo -e "${RED}ERROR: No deletion was attempted because the application inventory is incomplete.${NC}"
      return 1
    fi
    [ -z "$app_list" ] || combined_plan+="${combined_plan:+$'\n'}${app_list}"
  done

  if [ -z "$combined_plan" ]; then
    echo -e "${YELLOW}No matching OCI IAM lab Integrated Applications were found.${NC}"
    record_not_completed "OCI IAM applications — already absent"
    return 0
  fi

  show_domain_app_deletion_plan "$combined_plan"
  echo
  if confirm "$prompt"; then
    delete_domain_app_plan "$combined_plan"
  else
    echo -e "${YELLOW}Skipped OCI IAM application deletion.${NC}"
    record_not_completed "OCI IAM applications — deletion was not confirmed"
  fi
}

delete_domain_user() {
  local user_id="${1:-}"
  local user_name="$2"

  if [ -z "${OCI_DOMAIN_URL:-}" ]; then
    echo -e "${YELLOW}Skipping OCI IAM user ${user_name}; OCI_DOMAIN_URL is not set.${NC}"
    record_not_completed "OCI IAM user ${user_name} — OCI_DOMAIN_URL is not set"
    return 0
  fi
  if [ -z "$user_id" ] || [ "$user_id" = "null" ]; then
    echo -e "${YELLOW}Skipping OCI IAM user ${user_name}; user OCID is not set.${NC}"
    record_not_completed "OCI IAM user ${user_name} — user OCID is not set"
    return 0
  fi

  run_cleanup_cmd "Deleting OCI IAM user ${user_name}" \
    oci_with_profile identity-domains user delete \
      --endpoint "$OCI_DOMAIN_URL" \
      --user-id "$user_id" \
      --force-delete true \
      --force
}

delete_domain_group() {
  local group_id="${1:-}"
  local group_name="$2"

  if [ -z "${OCI_DOMAIN_URL:-}" ]; then
    echo -e "${YELLOW}Skipping OCI IAM group ${group_name}; OCI_DOMAIN_URL is not set.${NC}"
    record_not_completed "OCI IAM group ${group_name} — OCI_DOMAIN_URL is not set"
    return 0
  fi
  if [ -z "$group_id" ] || [ "$group_id" = "null" ]; then
    echo -e "${YELLOW}Skipping OCI IAM group ${group_name}; group OCID is not set.${NC}"
    record_not_completed "OCI IAM group ${group_name} — group OCID is not set"
    return 0
  fi

  run_cleanup_cmd "Deleting OCI IAM group ${group_name}" \
    oci_with_profile identity-domains group delete \
      --endpoint "$OCI_DOMAIN_URL" \
      --group-id "$group_id" \
      --force-delete true \
      --force
}

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 6: Clean Up ADB OCI IAM Data Grants Lab                          ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}ADB_SERVICE = ${ADB_SERVICE:-not required}${NC}"
echo -e "${CYAN}ADB_OCID    = ${ADB_OCID:-not set}${NC}"
echo -e "${CYAN}REMOVE_ALL  = ${REMOVE_ALL}${NC}"
echo -e "${CYAN}DELETE_DB_OBJECTS  = ${DELETE_DB_OBJECTS}${NC}"
echo -e "${CYAN}DELETE_ADB          = ${DELETE_ADB}${NC}"
echo -e "${CYAN}DELETE_IAM_USERS    = ${DELETE_IAM_USERS}${NC}"
echo -e "${CYAN}DELETE_IAM_GROUPS   = ${DELETE_IAM_GROUPS}${NC}"
echo -e "${CYAN}DELETE_IAM_APPS     = ${DELETE_IAM_APPS}${NC}"
echo -e "${CYAN}DELETE_ALL_LAB_APPS = ${DELETE_ALL_LAB_APPS}${NC}"
echo -e "${CYAN}DELETE_LOCAL_FILES  = ${DELETE_LOCAL_FILES}${NC}"
echo

if [ "$DELETE_DB_OBJECTS" = true ]; then
  echo -e "${YELLOW}The following database objects will be removed from ${ADB_SERVICE}:${NC}"
  echo "  - DATA GRANT hr.HRAPP_MANAGER_ACCESS"
  echo "  - DATA GRANT hr.EMPLOYEE_CONTEXT_GRANT"
  echo "  - DATA GRANT hr.HRAPP_EMPLOYEES_ACCESS"
  echo "  - DATA ROLE hrapp_managers"
  echo "  - DATA ROLE hrapp_employees"
  echo "  - ROLE direct_logon_role"
  echo "  - ROLE employee_context_admin"
  echo "  - USER hr CASCADE (HR schema and remaining dependent objects)"
  echo
  if confirm "This removes HR, data roles, and local lab roles."; then
  echo -e "${CYAN}Cleaning up database objects...${NC}"
  echo -e "${CYAN}SQL*Plus command:${NC}"
  show_cmd sqlplus -L -s "admin/<hidden>@${ADB_SERVICE}"
  echo -e "${CYAN}SQL block: drop lab data grants, data roles, local roles, and HR schema.${NC}"
  if db_cleanup_output=$(admin_sqlplus <<'SQL'
set echo off
set serveroutput on
set feedback off
set heading off
whenever sqlerror continue

DECLARE
  TYPE step_list IS TABLE OF VARCHAR2(4000);
  steps step_list := step_list(
    'DROP DATA GRANT hr.HRAPP_MANAGER_ACCESS',
    'DROP DATA GRANT hr.EMPLOYEE_CONTEXT_GRANT',
    'DROP DATA GRANT hr.HRAPP_EMPLOYEES_ACCESS',
    'DROP DATA ROLE hrapp_managers',
    'DROP DATA ROLE hrapp_employees',
    'DROP ROLE direct_logon_role',
    'DROP ROLE employee_context_admin',
    'DROP USER hr CASCADE'
  );
  failures SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST();

  PROCEDURE record_failure(statement_text VARCHAR2, err VARCHAR2) IS
  BEGIN
    failures.EXTEND;
    failures(failures.COUNT) := statement_text || ' -> ' || err;
  END;
BEGIN
  FOR i IN 1 .. steps.COUNT LOOP
    BEGIN
      EXECUTE IMMEDIATE steps(i);
      DBMS_OUTPUT.PUT_LINE('RESULT|DELETED|' || steps(i));
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLCODE IN (-1918, -1919, -1924, -904, -942, -950) THEN
          DBMS_OUTPUT.PUT_LINE('RESULT|NOT_DELETED|' || steps(i) || '|already absent');
        ELSE
          DBMS_OUTPUT.PUT_LINE('RESULT|NOT_DELETED|' || steps(i) || '|Oracle error ' || SQLCODE);
          record_failure(steps(i), SQLERRM);
        END IF;
    END;
  END LOOP;
END;
/

exit;
SQL
  ); then
    db_cleanup_status=0
  else
    db_cleanup_status=$?
  fi
  db_results=0
  while IFS='|' read -r marker outcome object reason; do
    [ "$marker" = "RESULT" ] || continue
    db_results=$((db_results + 1))
    if [ "$outcome" = "DELETED" ]; then
      echo -e "${CYAN}  Deleted: ${object}${NC}"
      record_completed "Deleted ${object}"
    else
      echo -e "${YELLOW}  Not deleted: ${object} (${reason})${NC}"
      record_not_completed "Database object ${object} — ${reason}"
    fi
  done <<< "$db_cleanup_output"
  if [ "$db_cleanup_status" -ne 0 ] || [ "$db_results" -eq 0 ]; then
    echo -e "${RED}ERROR: Database cleanup did not return object results.${NC}"
    echo "  Next: Verify SQL*Plus connectivity and the ADMIN credentials, then retry."
    record_cleanup_failure "Database object cleanup did not return object results"
    record_not_completed "Database objects — cleanup command did not complete"
  fi
  else
    echo -e "${YELLOW}Skipped database object cleanup.${NC}"
    record_not_completed "Database objects — deletion was not confirmed"
  fi
fi

if [ "$DELETE_ADB" = true ]; then
  echo -e "${YELLOW}The following Autonomous AI Database will be deleted:${NC}"
  echo "  - Name: ${DB_NAME}"
  echo "    OCID: ${ADB_OCID}"
  echo
  if confirm "This deletes the Autonomous AI Database ${DB_NAME}."; then
    run_cleanup_cmd "Deleting ADB ${DB_NAME}" \
      oci_with_profile db autonomous-database delete \
      --autonomous-database-id "$ADB_OCID" \
      --force \
      --wait-for-state SUCCEEDED
  else
    echo -e "${YELLOW}Skipped ADB deletion.${NC}"
    record_not_completed "ADB ${DB_NAME} — deletion was not confirmed"
  fi
fi

if [ "$DELETE_IAM_USERS" = true ]; then
  echo -e "${YELLOW}The following OCI IAM users will be deleted:${NC}"
  echo "  - ${MARVIN_USERNAME:-marvin} (${MARVIN_ID:-ID not set; will be skipped})"
  echo "  - ${EMMA_USERNAME:-emma} (${EMMA_ID:-ID not set; will be skipped})"
  echo
  if confirm "This deletes OCI IAM users ${MARVIN_USERNAME:-marvin} and ${EMMA_USERNAME:-emma}."; then
    echo
    echo -e "${YELLOW}Deleting lab OCI IAM users...${NC}"
    delete_domain_user "${MARVIN_ID:-}" "${MARVIN_USERNAME:-marvin}"
    delete_domain_user "${EMMA_ID:-}" "${EMMA_USERNAME:-emma}"
  else
    echo -e "${YELLOW}Skipped OCI IAM user deletion.${NC}"
    record_not_completed "OCI IAM users — deletion was not confirmed"
  fi
fi

if [ "$DELETE_IAM_GROUPS" = true ]; then
  echo -e "${YELLOW}The following OCI IAM groups will be deleted:${NC}"
  echo "  - ${OCI_IAM_EMPLOYEE_GROUP:-EMPLOYEES} (${EMPLOYEES_OCID:-ID not set; will be skipped})"
  echo "  - ${OCI_IAM_MANAGER_GROUP:-MANAGERS} (${MANAGERS_OCID:-ID not set; will be skipped})"
  echo
  if confirm "This deletes OCI IAM groups ${OCI_IAM_EMPLOYEE_GROUP:-EMPLOYEES} and ${OCI_IAM_MANAGER_GROUP:-MANAGERS}."; then
    echo
    echo -e "${YELLOW}Deleting lab OCI IAM groups...${NC}"
    # Delete users first with --delete-iam-users when group membership exists.
    delete_domain_group "${EMPLOYEES_OCID:-}" "${OCI_IAM_EMPLOYEE_GROUP:-EMPLOYEES}"
    delete_domain_group "${MANAGERS_OCID:-}" "${OCI_IAM_MANAGER_GROUP:-MANAGERS}"
  else
    echo -e "${YELLOW}Skipped OCI IAM group deletion.${NC}"
    record_not_completed "OCI IAM groups — deletion was not confirmed"
  fi
fi

if [ "$DELETE_IAM_APPS" = true ]; then
  echo
  echo -e "${YELLOW}Planning lab OCI IAM OAuth application deletion...${NC}"
  if [ -n "${DB_NAME:-}" ]; then
    # Public clients reference resource-app scopes, so remove them first.
    preview_and_delete_domain_apps \
      "This deactivates and deletes exactly the applications listed above." \
      "${DB_NAME} ADB OCI IAM Public Client" \
      "${DB_NAME} ADB OCI IAM DB Resource"
  else
    echo -e "${RED}ERROR: DB_NAME is required to inventory lab OAuth applications before deletion.${NC}"
    record_not_completed "OCI IAM applications — DB_NAME is not set"
  fi
fi

if [ "$DELETE_ALL_LAB_APPS" = true ]; then
  echo
  echo -e "${YELLOW}Planning deletion of all ADB OCI IAM lab Integrated Applications...${NC}"
  # This order removes allowedScopes references before the resource apps/scopes.
  preview_and_delete_domain_apps \
    "This deactivates and deletes exactly the applications listed above." \
    "ADB OCI IAM Public Client" \
    "ADB OCI IAM DB Resource"
fi

if [ "$DELETE_LOCAL_FILES" = true ]; then
  echo -e "${YELLOW}The following local paths will be removed:${NC}"
  if [ -n "${WALLET_DIR:-}" ]; then
    echo "  - ${WALLET_DIR}"
  else
    echo "  - Wallet directory: not set; will be skipped"
  fi
  echo "  - ${SCRIPT_DIR}/.adb-oci-iam.env"
  echo "  - ${SCRIPT_DIR}/.oci-iam-setup"
  echo "  - ${OCI_TOKEN_DIR:-$HOME/.oci/adb-oci-iam}"
  echo
  if confirm "This removes the local ADB wallet, lab environment, setup work directory, and OAuth token cache."; then
    echo
    echo -e "${YELLOW}Removing local generated files...${NC}"
    if [ -n "${WALLET_DIR:-}" ]; then
      run_cleanup_cmd "Removing wallet directory ${WALLET_DIR}" rm -rf "$WALLET_DIR"
    else
      echo -e "${YELLOW}Skipping wallet directory; WALLET_DIR is not set.${NC}"
      record_not_completed "Wallet directory — WALLET_DIR is not set"
    fi
    run_cleanup_cmd "Removing environment file ${SCRIPT_DIR}/.adb-oci-iam.env" rm -f "${SCRIPT_DIR}/.adb-oci-iam.env"
    run_cleanup_cmd "Removing local OCI IAM setup work directory" rm -rf "${SCRIPT_DIR}/.oci-iam-setup"
    run_cleanup_cmd "Removing local OCI IAM OAuth2 token cache" rm -rf "${OCI_TOKEN_DIR:-$HOME/.oci/adb-oci-iam}"
  else
    echo -e "${YELLOW}Skipped local generated-file cleanup.${NC}"
    record_not_completed "Local generated files — deletion was not confirmed"
  fi
fi

echo
echo -e "${GREEN}Cleanup summary${NC}"
if [ "${#CLEANUP_COMPLETED[@]}" -gt 0 ]; then
  echo "  Completed:"
  for item in "${CLEANUP_COMPLETED[@]}"; do
    echo "    - ${item}"
  done
fi
if [ "${#CLEANUP_NOT_COMPLETED[@]}" -gt 0 ]; then
  echo "  Not completed:"
  for item in "${CLEANUP_NOT_COMPLETED[@]}"; do
    echo "    - ${item}"
  done
fi
if [ "${#CLEANUP_FAILURES[@]}" -gt 0 ]; then
  echo -e "${YELLOW}Errors requiring attention:${NC}"
  for failure in "${CLEANUP_FAILURES[@]}"; do
    echo "  - ${failure}"
  done
  echo
fi
echo -e "${GREEN}Task 6 completed.${NC}"
echo
