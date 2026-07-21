#!/usr/bin/env bash
# Static guard for the direct-login lab's documented setup/cleanup symmetry.
set -Eeuo pipefail

lab_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
legacy_root="${lab_root}/../adb-oci-iam"
setup="${legacy_root}/00_setup_adb.sh"
cleanup="${legacy_root}/07_cleanup_adb_lab.sh"

require_text() {
  local file=$1
  local expected=$2
  grep -Fq -- "$expected" "$file" || {
    printf 'Missing expected marker in %s: %s\n' "$file" "$expected" >&2
    exit 1
  }
}

require_text "$setup" 'oci db autonomous-database create'
require_text "$cleanup" 'db autonomous-database delete'
require_text "$setup" 'create_or_reuse_domain_group'
require_text "$cleanup" 'delete_domain_group'
require_text "$setup" 'create_or_reuse_domain_user'
require_text "$cleanup" 'delete_domain_user'
require_text "$setup" 'setup_oauth_apps'
require_text "$cleanup" 'delete_domain_apps_matching'
require_text "$setup" 'generate-wallet'
require_text "$cleanup" 'Removing wallet directory'
require_text "${legacy_root}/03_create_data_roles_and_grants.sh" 'CREATE OR REPLACE DATA GRANT'
require_text "$cleanup" 'DROP DATA GRANT'

printf 'Legacy setup/cleanup symmetry contract: PASS\n'
