#!/usr/bin/env bash
# Database-client selection boundary. Connection behavior is added later.

# shellcheck disable=SC1091 # Resolved from this script's directory at runtime.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

selected_sql_client() {
  sql_client || die 'Neither SQLcl (sql) nor SQL*Plus (sqlplus) is available.'
}
