#!/usr/bin/env bash
# Run only the currently proven non-persona stages in their legacy order.
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ $# -gt 0 ]]; then
  printf 'ERROR: Usage: ./bin/all.sh\n' >&2
  exit 1
fi

"${script_dir}/configure-identity-domain.sh"
"${script_dir}/configure-database.sh"
"${script_dir}/verify-lab.sh" --persona admin

if [[ "${LAB_DRY_RUN:-0}" == "1" ]]; then
  printf '%s\n' 'Core direct-login setup: DRY RUN complete'
else
  printf '%s\n' 'Core direct-login setup: PASS'
fi
printf '%s\n' 'Next: obtain a fresh token, then run verify --persona marvin and verify --persona emma.'
