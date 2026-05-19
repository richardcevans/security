#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${FIND_MONEY_ENV:-${SCRIPT_DIR}/.find-the-money.env}"

REGION="${OCI_REGION:-us-chicago-1}"
COMPARTMENT_NAME="${GENAI_COMPARTMENT_NAME:-DBSec_Rich}"
COMPARTMENT_ID="${GENAI_COMPARTMENT_OCID:-}"
DISPLAY_NAME="${GENAI_API_KEY_DISPLAY_NAME:-find-the-money-demo}"
KEY_ONE_NAME="${GENAI_API_KEY_ONE_NAME:-find_money_key_one}"
KEY_TWO_NAME="${GENAI_API_KEY_TWO_NAME:-find_money_key_two}"
MODEL="${FIND_MONEY_OCI_GENAI_MODEL:-openai.gpt-oss-120b}"
BASE_URL="${FIND_MONEY_OCI_GENAI_BASE_URL:-https://inference.generativeai.us-chicago-1.oci.oraclecloud.com/openai/v1}"
OUTPUT_JSON="${GENAI_API_KEY_OUTPUT_JSON:-${SCRIPT_DIR}/.find-the-money-genai-api-key.json}"
UPDATE_ENV="${UPDATE_FIND_MONEY_ENV:-1}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
  cat <<'EOF'
Usage:
  ./06_setup_oci_genai_api_key.sh

Environment overrides:
  OCI_REGION                    Default: us-chicago-1
  GENAI_COMPARTMENT_NAME        Default: DBSec_Rich
  GENAI_COMPARTMENT_OCID        Use this when you already know the compartment OCID.
  FIND_MONEY_OCI_GENAI_MODEL    Default: openai.gpt-oss-120b
  FIND_MONEY_OCI_GENAI_BASE_URL Default: Chicago OpenAI-compatible endpoint.
  UPDATE_FIND_MONEY_ENV         Default: 1. Set to 0 to avoid editing .find-the-money.env.

The script creates an OCI Generative AI API key and writes the response to
.find-the-money-genai-api-key.json. OCI returns API key secret material only
when the key is created, so keep that file secure and do not commit it.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo -e "${RED}ERROR: Unknown option: $1${NC}"
      usage
      exit 1
      ;;
  esac
done

if ! command -v oci >/dev/null 2>&1; then
  echo -e "${RED}ERROR: OCI CLI is required.${NC}"
  exit 1
fi

if ! oci iam region list --region "$REGION" >/dev/null 2>&1; then
  echo -e "${RED}ERROR: OCI CLI is not configured or cannot call OCI.${NC}"
  echo -e "${YELLOW}Run oci setup config, refresh your security token, or verify instance principal auth.${NC}"
  exit 1
fi

discover_compartment_id() {
  local name="$1"
  oci iam compartment list \
    --region "$REGION" \
    --all \
    --access-level ACCESSIBLE \
    --compartment-id-in-subtree true \
    --include-root \
    --name "$name" \
    --query "data[?name=='${name}' && \"lifecycle-state\"!='DELETED'].id | [0]" \
    --raw-output 2>/dev/null || true
}

if [ -z "$COMPARTMENT_ID" ]; then
  COMPARTMENT_ID="$(discover_compartment_id "$COMPARTMENT_NAME")"
fi

if [ -z "$COMPARTMENT_ID" ] || [ "$COMPARTMENT_ID" = "null" ]; then
  echo -e "${RED}ERROR: Could not find compartment ${COMPARTMENT_NAME}.${NC}"
  echo -e "${YELLOW}Set GENAI_COMPARTMENT_OCID explicitly and rerun.${NC}"
  exit 1
fi

if ! printf '%s' "$COMPARTMENT_ID" | grep -q '^ocid1\.compartment\.'; then
  echo -e "${RED}ERROR: Resolved compartment value is not a compartment OCID: ${COMPARTMENT_ID}${NC}"
  exit 1
fi

expiry_one="$(date -u -d '+90 days' '+%Y-%m-%dT00:00:00+00:00')"
expiry_two="$(date -u -d '+180 days' '+%Y-%m-%dT00:00:00+00:00')"
key_details="$(mktemp)"
python3 - <<PY > "$key_details"
import json
print(json.dumps([
    {"keyName": "${KEY_ONE_NAME}", "timeExpiry": "${expiry_one}"},
    {"keyName": "${KEY_TWO_NAME}", "timeExpiry": "${expiry_two}"},
]))
PY

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 6: Create OCI Generative AI API Key for Find the Money           ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}  REGION         = ${REGION}${NC}"
echo -e "${CYAN}  COMPARTMENT    = ${COMPARTMENT_NAME}${NC}"
echo -e "${CYAN}  COMPARTMENT_ID = ${COMPARTMENT_ID}${NC}"
echo -e "${CYAN}  MODEL          = ${MODEL}${NC}"
echo -e "${CYAN}  BASE_URL       = ${BASE_URL}${NC}"
echo

oci generative-ai api-key create \
  --region "$REGION" \
  --compartment-id "$COMPARTMENT_ID" \
  --display-name "$DISPLAY_NAME" \
  --description "Find the Money demo OCI Generative AI OpenAI-compatible API key" \
  --key-details "file://${key_details}" \
  --wait-for-state ACTIVE \
  > "$OUTPUT_JSON"
rm -f "$key_details"
chmod 600 "$OUTPUT_JSON"

extract_secret() {
  python3 - "$OUTPUT_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    payload = json.load(fh)

candidate_names = {
    "secret",
    "secret-key",
    "secretKey",
    "key",
    "key-value",
    "keyValue",
    "value",
}

def walk(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if key in candidate_names and isinstance(item, str) and len(item) > 20:
                print(item)
                return True
        for item in value.values():
            if walk(item):
                return True
    elif isinstance(value, list):
        for item in value:
            if walk(item):
                return True
    return False

walk(payload)
PY
}

secret="$(extract_secret || true)"

if [ "$UPDATE_ENV" = "1" ]; then
  {
    echo
    echo "# OCI Generative AI OpenAI-compatible chat API."
    echo "export FIND_MONEY_OCI_GENAI_BASE_URL='${BASE_URL}'"
    echo "export FIND_MONEY_OCI_GENAI_MODEL='${MODEL}'"
    echo "export FIND_MONEY_OCI_COMPARTMENT_ID='${COMPARTMENT_ID}'"
    if [ -n "$secret" ]; then
      echo "export FIND_MONEY_OCI_GENAI_API_KEY='${secret}'"
    else
      echo "# OCI CLI returned only masked key values. Paste the full sk-... secret from OCI Console."
      echo "# export FIND_MONEY_OCI_GENAI_API_KEY='<paste_full_genai_api_key_secret>'"
    fi
  } >> "$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi

echo -e "${CYAN}Created API key response: ${OUTPUT_JSON}${NC}"
if [ -n "$secret" ]; then
  echo -e "${CYAN}Updated ${ENV_FILE} with the generated key secret.${NC}"
else
  echo -e "${YELLOW}Could not automatically identify the key secret field in the response.${NC}"
  echo -e "${YELLOW}Open ${OUTPUT_JSON}, copy the generated key secret, and replace the placeholder in ${ENV_FILE}.${NC}"
fi

echo
echo -e "${YELLOW}Required IAM policy if it is not already present:${NC}"
echo "allow any-user to use generative-ai-chat in compartment ${COMPARTMENT_NAME}"
echo "where ALL {request.principal.type='generativeaiapikey'}"
echo
echo "Restart the app after updating the key:"
echo "  ./stop.sh"
echo "  ./start.sh"
echo
