#!/usr/bin/env bash
# Prove OCI Generative AI access in Chicago with a fixed harmless prompt.

set -Eeuo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${script_dir}/lab_common.sh"
load_adb_lab_environment
load_oci_profile

region=${GENAI_REGION:-us-chicago-1}
model_id=${GENAI_MODEL_ID:-meta.llama-3.3-70b-instruct}
compartment_id=$(genai_compartment_id)
connection_timeout=${OCI_CONNECTION_TIMEOUT:-10}
read_timeout=${OCI_READ_TIMEOUT:-60}
request='{"apiFormat":"GENERIC","messages":[{"role":"USER","content":[{"type":"TEXT","text":"Reply with exactly: OCI Generative AI smoke test passed."}]}],"maxTokens":20,"temperature":0}'
serving_mode=$(printf '{"servingType":"ON_DEMAND","modelId":"%s"}' "$model_id")

printf 'OCI Generative AI smoke test\n  region      : %s\n  model       : %s\n  compartment: %s\n  connect timeout: %ss\n  read timeout   : %ss\n\n' "$region" "$model_id" "$compartment_id" "$connection_timeout" "$read_timeout"
printf 'Calling OCI Generative AI now; the command will fail instead of waiting indefinitely.\n\n'
oci_with_profile generative-ai-inference chat-result chat \
  --region "$region" \
  --connection-timeout "$connection_timeout" \
  --read-timeout "$read_timeout" \
  --compartment-id "$compartment_id" \
  --serving-mode "$serving_mode" \
  --chat-request "$request" \
  --output json
