#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "${script_dir}/../lib/manifest.sh"

case "${1:-}" in
  init) manifest_init ;;
  validate) manifest_validate ;;
  *) die 'Usage: ./bin/manifest.sh <init|validate>' ;;
esac
