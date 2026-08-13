#!/usr/bin/env bash
# Run the student-facing web server with Gunicorn. The lab keeps database passwords
# only in process memory, so independent Gunicorn workers cannot share that store.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$script_dir"

[ -x "$script_dir/.venv/bin/python" ] || { echo 'ERROR: .venv is missing. Run bash setup_venv.sh first.' >&2; exit 1; }
exec "$script_dir/.venv/bin/python" -m gunicorn --bind "${FLASK_HOST:-0.0.0.0}:7777" --workers "${GUNICORN_WORKERS:-1}" --access-logfile - --error-logfile - app:app
