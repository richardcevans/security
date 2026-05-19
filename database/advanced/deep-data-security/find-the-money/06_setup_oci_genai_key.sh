#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${FIND_MONEY_ENV:-${SCRIPT_DIR}/.find-the-money.env}"
LOG_DIR="${SCRIPT_DIR}/logs"

OCI_GENAI_REGION="${OCI_GENAI_REGION:-us-chicago-1}"
OCI_GENAI_COMPARTMENT_NAME="${OCI_GENAI_COMPARTMENT_NAME:-DBSec_Rich}"
OCI_GENAI_COMPARTMENT_ID="${OCI_GENAI_COMPARTMENT_ID:-}"
OCI_GENAI_API_KEY_DISPLAY_NAME="${OCI_GENAI_API_KEY_DISPLAY_NAME:-find-the-money-demo}"
OCI_GENAI_API_KEY_NAME="${OCI_GENAI_API_KEY_NAME:-find_money_key_one}"
OCI_GENAI_MODEL="${OCI_GENAI_MODEL:-openai.gpt-oss-120b}"
OCI_GENAI_KEY_EXPIRY="${OCI_GENAI_KEY_EXPIRY:-$(date -u -d '+90 days' '+%Y-%m-%dT00:00:00+00:00')}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

if ! command -v oci >/dev/null 2>&1; then
  echo -e "${RED}ERROR: OCI CLI is required.${NC}"
  exit 1
fi

if ! oci iam region-subscription list >/dev/null 2>&1; then
  echo -e "${RED}ERROR: OCI CLI is not authenticated or cannot reach OCI.${NC}"
  echo -e "${YELLOW}Configure OCI CLI first, then rerun this script.${NC}"
  exit 1
fi

mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR"

resolve_compartment_id() {
  if [ -n "$OCI_GENAI_COMPARTMENT_ID" ]; then
    printf '%s' "$OCI_GENAI_COMPARTMENT_ID"
    return
  fi

  oci iam compartment list \
    --all \
    --include-root \
    --compartment-id-in-subtree true \
    --access-level ANY \
    --name "$OCI_GENAI_COMPARTMENT_NAME" \
    --query "data[?\"lifecycle-state\"=='ACTIVE'].id | [0]" \
    --raw-output
}

compartment_id="$(resolve_compartment_id)"
if [ -z "$compartment_id" ] || [ "$compartment_id" = "null" ]; then
  echo -e "${RED}ERROR: Could not find active compartment named ${OCI_GENAI_COMPARTMENT_NAME}.${NC}"
  echo -e "${YELLOW}Set OCI_GENAI_COMPARTMENT_ID=<compartment_ocid> and rerun.${NC}"
  exit 1
fi

key_details_file="$(mktemp)"
create_output_file="${LOG_DIR}/oci-genai-api-key-create.json"

python3 - <<PY > "$key_details_file"
import json
print(json.dumps([{
    "keyName": "${OCI_GENAI_API_KEY_NAME}",
    "timeExpiry": "${OCI_GENAI_KEY_EXPIRY}",
}]))
PY

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 6: Create OCI Generative AI API Key for Find the Money           ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}  Region           = ${OCI_GENAI_REGION}${NC}"
echo -e "${CYAN}  Compartment name = ${OCI_GENAI_COMPARTMENT_NAME}${NC}"
echo -e "${CYAN}  Compartment OCID = ${compartment_id}${NC}"
echo -e "${CYAN}  Model            = ${OCI_GENAI_MODEL}${NC}"
echo -e "${CYAN}  Key display name = ${OCI_GENAI_API_KEY_DISPLAY_NAME}${NC}"
echo -e "${CYAN}  Key name         = ${OCI_GENAI_API_KEY_NAME}${NC}"
echo -e "${CYAN}  Key expiry       = ${OCI_GENAI_KEY_EXPIRY}${NC}"
echo

oci generative-ai api-key create \
  --region "$OCI_GENAI_REGION" \
  --compartment-id "$compartment_id" \
  --display-name "$OCI_GENAI_API_KEY_DISPLAY_NAME" \
  --description "Find the Money demo OCI Generative AI API key" \
  --key-details "file://${key_details_file}" \
  --wait-for-state ACTIVE \
  --output json > "$create_output_file"
chmod 600 "$create_output_file"
rm -f "$key_details_file"

api_key_secret="$(python3 - "$create_output_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)

candidates = []

def walk(value, path=""):
    if isinstance(value, dict):
        for key, item in value.items():
            walk(item, f"{path}.{key}" if path else key)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            walk(item, f"{path}[{index}]")
    elif isinstance(value, str):
        key = path.rsplit(".", 1)[-1].lower()
        looks_secret = (
            "secret" in key
            or key in {"key", "apikey", "api-key", "api_key", "keyvalue", "key-value", "value"}
        )
        if looks_secret and len(value) > 20 and not value.startswith("ocid1.") and " " not in value:
            candidates.append(value)

walk(payload)
print(candidates[0] if candidates else "")
PY
)"

{
  echo ""
  echo "# OCI Generative AI OpenAI-compatible chat API"
  echo "export FIND_MONEY_OCI_GENAI_BASE_URL='https://inference.generativeai.${OCI_GENAI_REGION}.oci.oraclecloud.com/openai/v1'"
  echo "export FIND_MONEY_OCI_GENAI_MODEL='${OCI_GENAI_MODEL}'"
  echo "export FIND_MONEY_OCI_COMPARTMENT_ID='${compartment_id}'"
  if [ -n "$api_key_secret" ]; then
    echo "export FIND_MONEY_OCI_GENAI_API_KEY='${api_key_secret}'"
  else
    echo "export FIND_MONEY_OCI_GENAI_API_KEY='<paste_generated_key_secret_from_${create_output_file}>'"
  fi
} >> "$ENV_FILE"
chmod 600 "$ENV_FILE"

echo -e "${GREEN}OCI Generative AI API key created.${NC}"
echo -e "${CYAN}Full create response saved securely to:${NC}"
echo -e "${CYAN}  ${create_output_file}${NC}"
echo -e "${CYAN}Find the Money env updated:${NC}"
echo -e "${CYAN}  ${ENV_FILE}${NC}"
if [ -z "$api_key_secret" ]; then
  echo
  echo -e "${YELLOW}WARNING: Could not auto-extract the generated key secret from the OCI CLI response.${NC}"
  echo -e "${YELLOW}Open ${create_output_file}, copy the generated key secret, and replace the placeholder in ${ENV_FILE}.${NC}"
fi
echo
echo "Restart the app:"
echo "  ./stop.sh"
echo "  ./start.sh"
echo
