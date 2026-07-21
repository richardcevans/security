#!/usr/bin/env bash
set -Eeuo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
terraform_dir="${root_dir}/terraform"
resource_manager_dir="${root_dir}/resource-manager"
output_dir="${resource_manager_dir}/generated"
stage_dir=$(mktemp -d)
trap 'rm -rf "${stage_dir}"' EXIT

command -v terraform >/dev/null 2>&1 || { echo 'ERROR: terraform is required.' >&2; exit 1; }
command -v zip >/dev/null 2>&1 || { echo 'ERROR: zip is required.' >&2; exit 1; }

terraform -chdir="${terraform_dir}" fmt -check -recursive
terraform -chdir="${terraform_dir}" init -backend=false
terraform -chdir="${terraform_dir}" validate

while IFS= read -r -d '' file; do
  [[ "$(basename "$file")" == "providers.tf" ]] && continue
  cp "$file" "${stage_dir}/$(basename "$file")"
done < <(find "${terraform_dir}" -maxdepth 1 -type f \( -name '*.tf' -o -name '.terraform.lock.hcl' \) -print0)
cp "${resource_manager_dir}/providers.tf" "${stage_dir}/providers.tf"
cp "${resource_manager_dir}/schema.yaml" "${stage_dir}/schema.yaml"

find "${stage_dir}" -type f -exec touch -t 198001010000 {} +
mkdir -p "${output_dir}"
zip_path="${output_dir}/deep-sec-gen-ai-demo-stack.zip"
(
  cd "${stage_dir}"
  find . -type f -print | LC_ALL=C sort | zip -X -q "${zip_path}" -@
)
printf 'Stack ZIP: %s\n' "${zip_path}"
sha256sum "${zip_path}"
