#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Find Python 3.12+ (prefer 3.12 for offline wheelhouse compatibility)
PYTHON_BIN=""
for candidate in python3.12 python3.13 python3.14 python3; do
    command -v "$candidate" >/dev/null 2>&1 || continue
    _ver=$("$candidate" --version 2>&1 | awk '{print $2}')
    _min=$(echo "$_ver" | cut -d. -f2)
    { [ "$(echo "$_ver" | cut -d. -f1)" -eq 3 ] && [ "$_min" -ge 12 ]; } 2>/dev/null \
        && PYTHON_BIN=$(command -v "$candidate") && break
done

if [ -z "$PYTHON_BIN" ]; then
    echo "ERROR: Python 3.12 or later is required."
    echo "       Install it with: sudo dnf install python3.12"
    exit 1
fi

PYTHON_MINOR=$(echo "$("$PYTHON_BIN" --version 2>&1)" | awk '{print $2}' | cut -d. -f2)

if [ ! -d "$SCRIPT_DIR/.venv" ]; then
    echo "Creating virtual environment with $PYTHON_BIN..."
    "$PYTHON_BIN" -m venv "$SCRIPT_DIR/.venv"
    source "$SCRIPT_DIR/.venv/bin/activate"
    python -m ensurepip --upgrade >/dev/null 2>&1
    if [ "$PYTHON_MINOR" -eq 12 ]; then
        echo "Installing dependencies from local wheelhouse (offline)..."
        pip install -q --no-index --find-links "$SCRIPT_DIR/wheelhouse" -r "$SCRIPT_DIR/requirements.txt"
    else
        echo "Python 3.$PYTHON_MINOR detected — bundled wheels are for 3.12; installing from PyPI..."
        pip install -q -r "$SCRIPT_DIR/requirements.txt"
    fi
else
    source "$SCRIPT_DIR/.venv/bin/activate"
fi

echo "Starting sample-app-django on port 8091 (using $PYTHON_BIN)..."
python "$SCRIPT_DIR/manage.py" runserver 0.0.0.0:8091 &
echo $! > "$SCRIPT_DIR/app.pid"
echo "PID: $(cat "$SCRIPT_DIR/app.pid")"
