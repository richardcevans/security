#!/usr/bin/env bash
# Generated-resource manifest helpers. Phase 1 creates no resource records.

# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

manifest_path() {
  printf '%s/resource-manifest.json\n' "${LAB_STATE_DIR}"
}

manifest_init() {
  local path
  path=$(manifest_path)
  if [[ -e "$path" ]]; then
    info "Resource manifest already exists: ${path}"
    return 0
  fi

  mkdir -p "${LAB_STATE_DIR}"
  printf '{\n  "schema_version": 1,\n  "resources": []\n}\n' >"$path"
  chmod 600 "$path"
  info "Resource manifest initialized: ${path}"
}

manifest_validate() {
  local path
  path=$(manifest_path)
  test -f "$path" || die "Resource manifest does not exist: ${path}"
  python3 - "$path" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as manifest_file:
    document = json.load(manifest_file)

if document != {"schema_version": 1, "resources": []}:
    raise SystemExit("Unexpected Phase 1 resource manifest content")
PY
  info "Resource manifest is valid: ${path}"
}
