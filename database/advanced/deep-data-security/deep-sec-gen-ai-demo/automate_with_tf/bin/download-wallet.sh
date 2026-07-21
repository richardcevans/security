#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${script_dir}/../lib/common.sh"

handoff_file="${LAB_STATE_DIR}/terraform.env"
test -f "$handoff_file" || die 'Terraform handoff is missing. Run capture-terraform-outputs.sh first.'
# shellcheck disable=SC1090
source "$handoff_file"
require_command oci
require_command unzip

oci_region="${OCI_REGION:-}"
[[ -n "$oci_region" ]] || die 'OCI_REGION is required, for example: OCI_REGION=us-chicago-1 ./bin/download-wallet.sh'

wallet_dir="${WALLET_DIR:-${LAB_STATE_DIR}/wallet}"
wallet_password="${WALLET_PWD:-}"
if [[ -z "$wallet_password" ]]; then
  read -r -s -p 'New wallet password: ' wallet_password
  printf '\n'
fi
[[ -n "$wallet_password" ]] || die 'Wallet password cannot be empty.'

[[ "${LAB_DRY_RUN:-0}" == 1 ]] && { echo "DRY RUN: generate wallet for ${ADB_OCID} in ${wallet_dir}"; exit 0; }
mkdir -p "$wallet_dir"
wallet_zip="${wallet_dir}/${DB_NAME}_wallet.zip"
oci db autonomous-database generate-wallet --region "$oci_region" --autonomous-database-id "$ADB_OCID" --password "$wallet_password" --file "$wallet_zip"
unzip -oq "$wallet_zip" -d "$wallet_dir"
chmod 700 "$wallet_dir"
chmod 600 "$wallet_zip" "$wallet_dir"/*.sso "$wallet_dir"/*.p12 2>/dev/null || true

if [[ -f "${wallet_dir}/sqlnet.ora" ]]; then
  sed -i.bak-lab-wallet -E "s#DIRECTORY=\"\\?/network/admin\"#DIRECTORY=\"${wallet_dir}\"#g" "${wallet_dir}/sqlnet.ora"
fi

printf "export TNS_ADMIN='%s'\nexport ADB_SERVICE='%s_low'\n" "$wallet_dir" "$DB_NAME" >"${LAB_STATE_DIR}/adb.env"
chmod 600 "${LAB_STATE_DIR}/adb.env"
echo "Wallet ready: ${wallet_dir}"
echo "Load connection settings: source ${LAB_STATE_DIR}/adb.env"
