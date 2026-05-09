#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/app.pid" ]; then
    kill "$(cat "$SCRIPT_DIR/app.pid")" 2>/dev/null
    rm -f "$SCRIPT_DIR/app.pid"
    echo "Stopped."
else
    echo "No PID file found."
fi
