#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
stage_dir=$(mktemp -d)
trap 'rm -rf "$stage_dir"' EXIT

cp -a "$script_dir/terraform-william-livelab" "$stage_dir/deep-data-security"
find "$stage_dir/deep-data-security" -name '.DS_Store' -delete
rm -rf "$stage_dir/deep-data-security/.terraform"
rm -f "$stage_dir/deep-data-security/artifacts/deep-data-security-flask-app-GreenButton.zip"

archive="$script_dir/deep-sec-local-genai-terraform-WilliamLiveLab.zip"
rm -f "$archive"
(cd "$stage_dir" && zip -qr "$archive" deep-data-security)
unzip -tq "$archive"
if unzip -Z1 "$archive" | grep -q 'deep-data-security/artifacts/deep-data-security-flask-app'; then
  echo 'ERROR: WilliamLiveLab Terraform archive unexpectedly contains an embedded application archive.' >&2
  exit 1
fi
echo "Created deep-sec-local-genai-terraform-WilliamLiveLab.zip"
