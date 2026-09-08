#!/bin/bash
# Verify OCI IAM policy statements needed by the DeepSec MCP authenticated-principal path.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"

usage() {
  cat <<'EOF'
Usage:
  ./verify_oci_policies.sh [--group <identity-domain/group-name>] [--scope tenancy|compartment|both]

Examples:
  ./verify_oci_policies.sh
  ./verify_oci_policies.sh --group Default/deepsec-employees-022b5f
  ./verify_oci_policies.sh --scope tenancy

The script searches OCI IAM policies for statements required by Database Tools
MCP authenticated-principal access. It validates policy text, not a full OCI
authorization decision.
EOF
}

GROUP_NAME=""
SCOPE="both"

while [ $# -gt 0 ]; do
  case "$1" in
    --group)
      GROUP_NAME="${2:-}"
      shift 2
      ;;
    --scope)
      SCOPE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo -e "${RED}ERROR: Unknown argument: $1${NC}" >&2
      usage
      exit 1
      ;;
  esac
done

if [ "$SCOPE" != "tenancy" ] && [ "$SCOPE" != "compartment" ] && [ "$SCOPE" != "both" ]; then
  echo -e "${RED}ERROR: --scope must be tenancy, compartment, or both.${NC}" >&2
  exit 1
fi

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo -e "${RED}ERROR: .deep-sec-mcp.env not found. Run ./00_configure_lab_env.sh first.${NC}" >&2
  exit 1
fi
source "${SCRIPT_DIR}/lib_oci_profile.sh"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: $1 is required but is not available in PATH.${NC}" >&2
    exit 1
  fi
}

oci_query() {
  PYTHONWARNINGS="${PYTHONWARNINGS:+${PYTHONWARNINGS},}ignore::FutureWarning:urllib3.poolmanager" \
    oci_with_profile "$@"
}

require_cmd oci
require_cmd python3

GROUP_NAME="${GROUP_NAME:-${OCI_IAM_EMPLOYEE_GROUP:-}}"
if [ -z "$GROUP_NAME" ] && [ -n "${OCI_IAM_EMPLOYEE_GROUP_DISPLAY_NAME:-}" ]; then
  GROUP_NAME="Default/${OCI_IAM_EMPLOYEE_GROUP_DISPLAY_NAME}"
fi

if [ -z "${TENANCY_OCID:-}" ]; then
  echo -e "${RED}ERROR: TENANCY_OCID is not set in .deep-sec-mcp.env.${NC}" >&2
  exit 1
fi
if [ -z "$GROUP_NAME" ]; then
  echo -e "${RED}ERROR: Could not determine group. Set OCI_IAM_EMPLOYEE_GROUP or pass --group.${NC}" >&2
  exit 1
fi

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/deepsec-mcp-policies.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT

POLICY_JSON="${WORK_DIR}/policies.json"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Verify DeepSec MCP OCI IAM Policies                                   ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}TENANCY_OCID          = ${TENANCY_OCID}${NC}"
echo -e "${CYAN}MCP_COMPARTMENT_OCID  = ${MCP_COMPARTMENT_OCID:-}${NC}"
echo -e "${CYAN}GROUP_NAME            = ${GROUP_NAME}${NC}"
echo -e "${CYAN}SCOPE                 = ${SCOPE}${NC}"
echo

policy_compartments=("$TENANCY_OCID")
if [ -n "${MCP_COMPARTMENT_OCID:-}" ] && [ "$MCP_COMPARTMENT_OCID" != "$TENANCY_OCID" ]; then
  policy_compartments+=("$MCP_COMPARTMENT_OCID")
fi

printf '{"policies":[]}\n' > "$POLICY_JSON"
for compartment_id in "${policy_compartments[@]}"; do
  tmp_json="${WORK_DIR}/policies-${compartment_id##*.}.json"
  echo -e "${YELLOW}Loading policies in compartment: ${compartment_id}${NC}"
  if oci_query iam policy list \
    --compartment-id "$compartment_id" \
    --all \
    --output json > "$tmp_json"; then
    POLICY_JSON="$POLICY_JSON" TMP_JSON="$tmp_json" python3 - <<'PY'
import json
import os

with open(os.environ["POLICY_JSON"], encoding="utf-8") as f:
    combined = json.load(f)
with open(os.environ["TMP_JSON"], encoding="utf-8") as f:
    raw = json.load(f)

combined.setdefault("policies", []).extend(raw.get("data") or [])
with open(os.environ["POLICY_JSON"], "w", encoding="utf-8") as f:
    json.dump(combined, f)
PY
  else
    echo -e "${YELLOW}WARN: Could not list policies in ${compartment_id}.${NC}" >&2
  fi
done

POLICY_JSON="$POLICY_JSON" \
TENANCY_OCID="$TENANCY_OCID" \
MCP_COMPARTMENT_OCID="${MCP_COMPARTMENT_OCID:-}" \
GROUP_NAME="$GROUP_NAME" \
SCOPE="$SCOPE" \
python3 - <<'PY'
import json
import os
import re
import sys

policy_path = os.environ["POLICY_JSON"]
tenancy_ocid = os.environ["TENANCY_OCID"]
mcp_compartment_ocid = os.environ.get("MCP_COMPARTMENT_OCID") or tenancy_ocid
group_name = os.environ["GROUP_NAME"]
scope = os.environ["SCOPE"]
quoted_group_name = "'" + group_name.replace("/", "'/'") + "'"

with open(policy_path, encoding="utf-8") as f:
    policies = json.load(f).get("policies") or []

def normalize(text):
    text = text.lower()
    text = text.replace('"', "'")
    text = re.sub(r"\s+", " ", text).strip()
    return text

def group_variants(name):
    name = name.strip().strip("'").strip('"')
    variants = {name}
    if "/" in name:
        domain, group = name.split("/", 1)
        variants.add(f"{domain}/{group}")
        variants.add(f"'{domain}'/'{group}'")
        variants.add(f'"{domain}"/"{group}"')
    else:
        variants.add(name)
        variants.add(f"'{name}'")
        variants.add(f'"{name}"')
    return {normalize(v) for v in variants}

group_refs = group_variants(group_name)

required = [
    ("use", "database-tools-mcp-servers-invocation"),
    ("use", "database-connections"),
    ("use", "database-tools-connections"),
    ("use", "database-tools-runtime-work-requests"),
    ("read", "secret-bundles"),
    ("use", "buckets"),
    ("manage", "objects"),
    ("manage", "generative-ai-nl2sql"),
]

statements = []
for policy in policies:
    for statement in policy.get("statements") or []:
        statements.append({
            "policy_name": policy.get("name") or "",
            "policy_id": policy.get("id") or "",
            "policy_compartment_id": policy.get("compartment-id") or policy.get("compartmentId") or "",
            "statement": statement,
            "normalized": normalize(statement),
        })

print()
print("Policies containing the target group")
matching_policy_count = 0
for item in statements:
    if any(ref in item["normalized"] for ref in group_refs):
        matching_policy_count += 1
        print(f"  {item['policy_name']} ({item['policy_id']})")
        print(f"    {item['statement']}")
if matching_policy_count == 0:
    print("  No policy statements found for this group.")

def statement_matches(item, verb, resource, location):
    s = item["normalized"]
    if not any(ref in s for ref in group_refs):
        return False
    if f" to {verb} {resource} " not in f" {s} ":
        return False
    if location == "tenancy":
        return " in tenancy" in s
    if location == "compartment":
        return (
            f" in compartment id {mcp_compartment_ocid.lower()}" in s
            or " in compartment " in s
        )
    return False

locations = []
if scope in ("tenancy", "both"):
    locations.append("tenancy")
if scope in ("compartment", "both"):
    locations.append("compartment")

print()
print("Required policy statements")
failures = 0
for verb, resource in required:
    matched = []
    for location in locations:
        matched.extend(item for item in statements if statement_matches(item, verb, resource, location))
    label = f"{verb} {resource}"
    if matched:
        print(f"  PASS: {label}")
        for item in matched[:3]:
            print(f"    {item['policy_name']}: {item['statement']}")
    else:
        failures += 1
        print(f"  FAIL: {label}")
        if scope == "tenancy" or (scope == "both" and mcp_compartment_ocid == tenancy_ocid):
            print(f"    Expected: Allow group {quoted_group_name} to {verb} {resource} in tenancy")
        else:
            print(f"    Expected one of: ... in tenancy OR ... in compartment id {mcp_compartment_ocid}")

print()
if failures:
    print(f"OCI policy verification failed: {failures} missing statement(s).")
    sys.exit(1)

print("OCI policy verification passed.")
PY
