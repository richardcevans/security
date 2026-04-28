#!/bin/bash
# =========================================================================================
# Script Name : 07_show_app_migration.sh
#
# Parameter   : None
#
# Notes       : Task 7 - Show the application-code migration (before vs after).
#               The database side is done. Now the app needs one small change:
#               stop connecting as a shared service account; start connecting as
#               the end user who is actually making the request.
#
#               The "BEFORE" snippets are illustrative — they show what the code
#               would look like in a traditional shared-account app. The "AFTER"
#               snippets are the real code in apps/sample-app-*.
#
# Modified by         Date         Change
# Oracle DB Security  04/14/2026   Creation
# =========================================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 7: The Application-Code Migration — Before vs After              ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${PURPLE}The database enforces the policy. The app only has to do ONE thing:${NC}"
echo -e "${PURPLE}  connect as the end user (marvin@domain.com / emma@domain.com) instead of a shared account (hr).${NC}"
echo
echo -e "${PURPLE}That's the entire code change. No filtering logic. No row-level checks.${NC}"
echo -e "${PURPLE}No SSN redaction. The database returns only what the user is allowed to see.${NC}"
echo

# =====================================================================
# Spring Boot
# =====================================================================
echo -e "${YELLOW}--------------------------------------------------------------------------${NC}"
echo -e "${YELLOW}Spring Boot: DataSourceConfig.java${NC}"
echo -e "${YELLOW}--------------------------------------------------------------------------${NC}"
echo
echo -e "${RED}BEFORE (traditional — shared service account):${NC}"
cat <<'EOF'
  @Bean
  public DataSource dataSource() {
      OracleDataSource ds = new OracleDataSource();
      ds.setURL(url);
      ds.setUser("hr");                 // <-- hardcoded service account
      ds.setPassword("Oracle123");
      return ds;                        // <-- one pool, shared by every request
  }
EOF
echo
echo -e "${GREEN}AFTER (migrated — per-user connection):${NC}"
echo -e "${CYAN}  File: apps/sample-app-springboot/src/main/java/com/example/sampleapp/DataSourceConfig.java${NC}"
echo
sed -n '27,39p' "$SCRIPT_DIR/apps/sample-app-springboot/src/main/java/com/example/sampleapp/DataSourceConfig.java" | sed 's/^/  /'
echo
echo -e "${PURPLE}Key change: getConnection(username, password) is called per-request with${NC}"
echo -e "${PURPLE}the LOGGED-IN user's credentials. Oracle authenticates them, activates${NC}"
echo -e "${PURPLE}their data roles, and the data grants filter rows and columns in the kernel.${NC}"
echo

# =====================================================================
# Django
# =====================================================================
echo -e "${YELLOW}--------------------------------------------------------------------------${NC}"
echo -e "${YELLOW}Django: employees/views.py${NC}"
echo -e "${YELLOW}--------------------------------------------------------------------------${NC}"
echo
echo -e "${RED}BEFORE (traditional — shared service account):${NC}"
cat <<'EOF'
  def _get_connection():
      return oracledb.connect(
          user="hr",                    # <-- hardcoded service account
          password="Oracle123",
          dsn=settings.ORACLE_DSN,
      )
EOF
echo
echo -e "${GREEN}AFTER (migrated — per-user connection):${NC}"
echo -e "${CYAN}  File: apps/sample-app-django/employees/views.py${NC}"
echo
sed -n '9,15p' "$SCRIPT_DIR/apps/sample-app-django/employees/views.py" | sed 's/^/  /'
echo
echo -e "${PURPLE}Same idea: _get_connection(username, password) takes the end-user's${NC}"
echo -e "${PURPLE}credentials (captured at login and stored in the session). Every query${NC}"
echo -e "${PURPLE}runs on a connection that Oracle knows belongs to that specific user.${NC}"
echo

# =====================================================================
# Summary
# =====================================================================
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}  What changed in application code:                                         ${NC}"
echo -e "${GREEN}    - Replace shared-pool datasource with per-request getConnection(u, p).  ${NC}"
echo -e "${GREEN}    - Capture username/password at login; use them for every DB call.       ${NC}"
echo -e "${GREEN}                                                                            ${NC}"
echo -e "${GREEN}  What did NOT change:                                                      ${NC}"
echo -e "${GREEN}    - The SQL. Still 'SELECT * FROM hr.employees'.                          ${NC}"
echo -e "${GREEN}    - The views/controllers. No user-aware filtering code.                  ${NC}"
echo -e "${GREEN}    - The schema. Same table, same columns.                                 ${NC}"
echo -e "${GREEN}                                                                            ${NC}"
echo -e "${GREEN}  Next: run ./08_start_app.sh to start one of the apps and test it.         ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
