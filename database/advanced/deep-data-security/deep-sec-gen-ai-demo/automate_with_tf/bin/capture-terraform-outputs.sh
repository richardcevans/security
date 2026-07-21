#!/usr/bin/env bash
set -Eeuo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${script_dir}/../lib/common.sh"
require_command terraform
mkdir -p "${LAB_STATE_DIR}"
terraform -chdir="${LAB_ROOT}/terraform" output -json >"${LAB_STATE_DIR}/terraform-outputs.json"
python3 - "${LAB_STATE_DIR}/terraform-outputs.json" "${LAB_STATE_DIR}/terraform.env" <<'PY'
import json, sys
outputs=json.load(open(sys.argv[1], encoding='utf-8'))
def value(name): return outputs.get(name, {}).get('value')
required=['autonomous_database_id','autonomous_database_name']
missing=[name for name in required if not value(name)]
if missing: raise SystemExit('Missing Terraform outputs: '+', '.join(missing))
with open(sys.argv[2], 'w', encoding='utf-8') as out:
    for name, env in [('autonomous_database_id','ADB_OCID'),('autonomous_database_name','DB_NAME'),('demo_bucket_name','DEMO_BUCKET_NAME'),('object_storage_namespace','OBJECT_STORAGE_NAMESPACE')]:
        item=value(name)
        if item: out.write(f"export {env}='{item}'\n")
PY
chmod 600 "${LAB_STATE_DIR}/terraform.env"
echo "Terraform handoff written to ${LAB_STATE_DIR}/terraform.env"
