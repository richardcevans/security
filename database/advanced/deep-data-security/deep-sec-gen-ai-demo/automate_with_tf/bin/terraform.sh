#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "${script_dir}/../lib/common.sh"

terraform_dir="${LAB_ROOT}/terraform"
operation=${1:-}
shift || true

require_command terraform

case "$operation" in
  init) exec terraform -chdir="$terraform_dir" init -backend=false "$@" ;;
  fmt) exec terraform -chdir="$terraform_dir" fmt -check -recursive "$@" ;;
  validate) exec terraform -chdir="$terraform_dir" validate "$@" ;;
  plan) exec terraform -chdir="$terraform_dir" plan "$@" ;;
  apply)
    [[ "${1:-}" == "--yes" ]] || die 'Terraform apply requires: ./bin/labctl infra apply --yes [terraform options]'
    shift
    exec terraform -chdir="$terraform_dir" apply -auto-approve "$@"
    ;;
  *) die 'Usage: ./bin/terraform.sh <init|fmt|validate|plan|apply> [options]' ;;
esac
