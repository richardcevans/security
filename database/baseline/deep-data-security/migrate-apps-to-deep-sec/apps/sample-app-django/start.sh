#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$SCRIPT_DIR/.venv" ]; then
    echo "Creating virtual environment..."
    python3.12 -m venv "$SCRIPT_DIR/.venv"
    source "$SCRIPT_DIR/.venv/bin/activate"
    echo "Installing dependencies from local wheelhouse (offline)..."
    python -m ensurepip --upgrade >/dev/null 2>&1
    pip install -q --no-index --find-links "$SCRIPT_DIR/wheelhouse" -r "$SCRIPT_DIR/requirements.txt"
else
    source "$SCRIPT_DIR/.venv/bin/activate"
fi

echo "Starting sample-app-django on port 8091..."
python "$SCRIPT_DIR/manage.py" runserver 0.0.0.0:8091 &
echo $! > "$SCRIPT_DIR/app.pid"
echo "PID: $(cat "$SCRIPT_DIR/app.pid")"
