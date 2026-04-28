#!/bin/bash
# =========================================================================================
# Script Name : 08_start_app.sh
#
# Parameter   : Optional: "springboot" or "django". If omitted, prompts.
#
# Notes       : Task 8 - Start one of the migrated sample apps and verify end-user login.
#               Starts the selected app in the background, waits for it to come up,
#               and curls the login endpoint as Marvin and Emma to confirm that the
#               database returns each user's filtered view.
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
APPS_DIR="$SCRIPT_DIR/apps"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 8: Start the Migrated App and Test End-User Login                ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

CHOICE="${1:-}"
if [ -z "$CHOICE" ]; then
    echo -e "${PURPLE}Which app would you like to run?${NC}"
    echo "  1) Spring Boot (Java 17, port 8090)"
    echo "  2) Django     (Python 3.12, port 8091)"
    echo
    read -p "Enter 1 or 2: " N
    case "$N" in
        1) CHOICE=springboot ;;
        2) CHOICE=django ;;
        *) echo -e "${RED}Invalid choice. Exiting.${NC}"; exit 1 ;;
    esac
fi

case "$CHOICE" in
    springboot)
        APP_DIR="$APPS_DIR/sample-app-springboot"
        PORT=8090
        ;;
    django)
        APP_DIR="$APPS_DIR/sample-app-django"
        PORT=8091
        ;;
    *)
        echo -e "${RED}Unknown app: $CHOICE (expected springboot or django)${NC}"
        exit 1
        ;;
esac

if [ ! -d "$APP_DIR" ]; then
    echo -e "${RED}App directory not found: $APP_DIR${NC}"
    exit 1
fi

# Preflight: verify the required runtime is available
case "$CHOICE" in
    springboot)
        JAVA_OK=0
        for candidate in \
            "${JAVA_HOME:+$JAVA_HOME/bin/java}" \
            /usr/lib/jvm/java-17-openjdk/bin/java \
            /usr/lib/jvm/java-17/bin/java \
            "$(command -v java 2>/dev/null)"; do
            [ -x "$candidate" ] || continue
            ver=$("$candidate" -version 2>&1 | awk -F '"' '/version/{print $2}' | cut -d. -f1)
            [ "${ver:-0}" -ge 17 ] 2>/dev/null && JAVA_OK=1 && break
        done
        if [ "$JAVA_OK" -eq 0 ]; then
            echo -e "${RED}ERROR: Java 17 or later is required for the Spring Boot app.${NC}"
            echo -e "${RED}       Install it with: sudo dnf install java-17-openjdk${NC}"
            exit 1
        fi
        ;;
    django)
        PYTHON_BIN=""
        for candidate in python3.12 python3.13 python3.14 python3; do
            command -v "$candidate" >/dev/null 2>&1 || continue
            _ver=$("$candidate" --version 2>&1 | awk '{print $2}')
            _maj=$(echo "$_ver" | cut -d. -f1)
            _min=$(echo "$_ver" | cut -d. -f2)
            { [ "$_maj" -eq 3 ] && [ "$_min" -ge 12 ]; } 2>/dev/null && PYTHON_BIN=$(command -v "$candidate") && break
        done
        if [ -z "$PYTHON_BIN" ]; then
            echo -e "${RED}ERROR: Python 3.12 or later is required for the Django app.${NC}"
            echo -e "${RED}       Install it with: sudo dnf install python3.12${NC}"
            exit 1
        fi
        ;;
esac

# Stop any prior instance
if [ -f "$APP_DIR/app.pid" ]; then
    echo -e "${YELLOW}Stopping previous instance...${NC}"
    kill "$(cat "$APP_DIR/app.pid")" 2>/dev/null
    rm -f "$APP_DIR/app.pid"
    sleep 2
fi

echo -e "${YELLOW}Starting $CHOICE on port $PORT...${NC}"
echo -e "${CYAN}Executing: $APP_DIR/start.sh${NC}"
echo
(cd "$APP_DIR" && ./start.sh) >/tmp/${CHOICE}-sample.log 2>&1 &
sleep 1

echo -e "${YELLOW}Waiting for app to accept HTTP requests...${NC}"
UP=0
for i in $(seq 1 60); do
    if curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/login" 2>/dev/null | grep -q '200'; then
        UP=1
        break
    fi
    sleep 1
done

if [ "$UP" -ne 1 ]; then
    echo -e "${RED}App did not start within 60 seconds. Last log lines:${NC}"
    tail -30 /tmp/${CHOICE}-sample.log
    exit 1
fi

echo -e "${GREEN}App is running at http://localhost:$PORT${NC}"
echo

# Helper: login and return employee count via the JSON API
_login_and_count() {
    local user="$1" pass="$2" jar="/tmp/cookies_${user}.txt"
    rm -f "$jar"
    # Step 1: GET login page → set CSRF cookie
    curl -s -c "$jar" "http://localhost:$PORT/login" > /dev/null
    local csrf
    csrf=$(awk '/csrftoken/{print $7}' "$jar")
    # Step 2: POST credentials + CSRF token → set session cookie
    curl -s -b "$jar" -c "$jar" \
        -H "Referer: http://localhost:$PORT/login" \
        -d "username=${user}&password=${pass}&csrfmiddlewaretoken=${csrf}" \
        -L "http://localhost:$PORT/login" > /dev/null
    # Step 3: GET JSON API with session cookie → count rows
    curl -s -b "$jar" "http://localhost:$PORT/api/employees" | grep -c '"employee_id"'
    rm -f "$jar"
}

# ---- Test Marvin ----
echo -e "${YELLOW}Test 1: Login as Marvin (manager + employee)...${NC}"
MARVIN_ROWS=$(_login_and_count marvin Oracle123)
echo -e "  Marvin sees ${GREEN}${MARVIN_ROWS} row(s)${NC} (expected: 4 — self + 3 direct reports)"
echo

# ---- Test Emma ----
echo -e "${YELLOW}Test 2: Login as Emma (employee only)...${NC}"
EMMA_ROWS=$(_login_and_count emma Oracle123)
echo -e "  Emma sees ${GREEN}${EMMA_ROWS} row(s)${NC} (expected: 1 — only herself)"
echo

echo -e "${PURPLE}Open http://localhost:$PORT in your browser and log in as marvin/Oracle123${NC}"
echo -e "${PURPLE}or emma/Oracle123 to see the filtered views yourself.${NC}"
echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 8 Completed: App Running — Next: ./09_verify_security_boundary.sh${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
