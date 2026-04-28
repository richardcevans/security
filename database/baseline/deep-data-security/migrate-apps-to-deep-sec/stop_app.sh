#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

STOPPED=0
for APP in sample-app-springboot sample-app-django; do
    PIDFILE="$SCRIPT_DIR/apps/$APP/app.pid"
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        kill "$PID" 2>/dev/null
        rm -f "$PIDFILE"
        echo -e "${GREEN}Stopped $APP (PID $PID).${NC}"
        STOPPED=1
    fi
done

if [ "$STOPPED" -eq 0 ]; then
    echo -e "${YELLOW}No running app found.${NC}"
fi
