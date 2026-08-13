#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
stage_dir=$(mktemp -d)
trap 'rm -rfv "$stage_dir"' EXIT
mkdir -vp "$script_dir/dist"
cp -av "$script_dir/flask-app" "$stage_dir/flask-app"
cp -av "$script_dir/database" "$stage_dir/database"
rm -rfv "$stage_dir/flask-app/.venv" "$stage_dir/flask-app/__pycache__" "$stage_dir/flask-app/logs"
rm -fv "$stage_dir/flask-app/.env"
find "$stage_dir/flask-app" -name '__pycache__' -type d -prune -exec rm -rfv {} +
( ! find "$stage_dir" -type f \( -name '.env' -o -name '*.pem' -o -name 'cwallet.sso' -o -name 'ewallet.p12' \) -print -quit | grep -q . ) || {
  echo 'ERROR: refusing to package credentials or wallet material' >&2
  exit 1
}
rm -fv "$script_dir/dist/deep-data-security-flask-app.zip"
(cd "$stage_dir" && zip -qr "$script_dir/dist/deep-data-security-flask-app.zip" flask-app database)
sha256sum "$script_dir/dist/deep-data-security-flask-app.zip" > "$script_dir/dist/deep-data-security-flask-app.zip.sha256"
echo "Created dist/deep-data-security-flask-app.zip and its SHA-256 file."
