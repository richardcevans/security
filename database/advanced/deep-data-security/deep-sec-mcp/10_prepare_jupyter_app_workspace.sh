#!/usr/bin/env bash
# Prepare an Oracle Linux Compute VM for a future DeepSec MCP Python app.
# Run this on the VM after copying and extracting deep-sec-mcp-cloudshell.zip.
# JupyterLab is intentionally bound to 127.0.0.1; use an SSH tunnel to reach it.

set -euo pipefail

APP_USER="${APP_USER:-${SUDO_USER:-$USER}}"
APP_HOME="$(getent passwd "$APP_USER" | cut -d: -f6)"
APP_DIR="${APP_DIR:-$APP_HOME/deepsec-mcp-app}"
VENV_DIR="${VENV_DIR:-$APP_HOME/deepsec-venv}"

[[ -n "$APP_HOME" && -d "$APP_HOME" ]] || {
  echo "Could not find a home directory for APP_USER=$APP_USER." >&2
  exit 1
}

if (( EUID != 0 )); then
  exec sudo APP_USER="$APP_USER" APP_DIR="$APP_DIR" VENV_DIR="$VENV_DIR" "$0" "$@"
fi

dnf -y install git python3 python3-pip policycoreutils-python-utils

# OCI network rules remain in force. This only disables the guest OS firewall
# for the public Jupyter setup requested by this lab variant.
systemctl disable --now firewalld || true

# A 1 GB E2 Micro benefits from swap while installing and running Jupyter.
if ! swapon --show=NAME --noheadings | grep -qx /swapfile; then
  if [[ ! -e /swapfile ]]; then
    dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
    chmod 600 /swapfile
    mkswap /swapfile
  fi
  grep -qE '^/swapfile[[:space:]]' /etc/fstab || echo '/swapfile none swap defaults 0 0' >> /etc/fstab
  swapon /swapfile
fi

python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install --upgrade \
  jupyterlab oci oracledb fastapi uvicorn python-dotenv httpx

install -d -o "$APP_USER" -g "$APP_USER" -m 0750 \
  "$APP_DIR" "$APP_DIR/notebooks" "$APP_DIR/src" "$APP_DIR/tests"

cat >"$APP_DIR/requirements.txt" <<'EOF'
jupyterlab
oci
oracledb
fastapi
uvicorn
python-dotenv
httpx
EOF

cat >"$APP_DIR/.env.example" <<'EOF'
# Keep credentials out of notebooks and source control.
# The OCI IAM OAuth settings can be copied from .deep-sec-mcp.env when the app is built.
OCI_DOMAIN_URL=
OCI_CLIENT_ID=
OCI_SCOPE=
OCI_REDIRECT_URI=http://localhost:8888/callback
MCP_SERVER_ENDPOINT=
EOF

cat >"$APP_DIR/.gitignore" <<'EOF'
.env
.venv/
__pycache__/
*.py[cod]
.ipynb_checkpoints/
wallet/
EOF

cat >"$APP_DIR/README.md" <<EOF
# DeepSec MCP application workspace

This is an intentionally empty workspace for the application built in the next step.

JupyterLab is available only through an SSH tunnel:

\`\`\`bash
ssh -L 8888:127.0.0.1:8888 ${APP_USER}@<VM_PUBLIC_IP>
\`\`\`

Then retrieve the token URL and open it locally:

\`\`\`bash
sudo journalctl -u jupyter-lab --no-pager | grep -m1 -E 'http://127.0.0.1:8888/lab\\?token='
\`\`\`

The lab's OCI IAM OAuth values should remain in the protected \`.deep-sec-mcp.env\`
file. When we build the app, copy only the needed non-secret settings into \`.env\`.
EOF

chown -R "$APP_USER:$APP_USER" "$APP_DIR" "$VENV_DIR"

# SELinux blocks systemd from executing programs labelled user_home_t, even
# when the service runs as opc. Persist a bin_t label for this trusted venv.
if ! semanage fcontext -a -t bin_t "${VENV_DIR}(/.*)?" 2>/dev/null; then
  semanage fcontext -m -t bin_t "${VENV_DIR}(/.*)?"
fi
restorecon -RFv "$VENV_DIR"

cat >/etc/systemd/system/jupyter-lab.service <<EOF
[Unit]
Description=JupyterLab for the DeepSec MCP application workspace (loopback only)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$APP_USER
WorkingDirectory=$APP_DIR
ExecStart=$VENV_DIR/bin/jupyter lab --ip=127.0.0.1 --port=8888 --no-browser
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now jupyter-lab.service

cat <<EOF

Ready: $APP_DIR
JupyterLab is listening only on 127.0.0.1:8888.

From your workstation:
  ssh -L 8888:127.0.0.1:8888 $APP_USER@<VM_PUBLIC_IP>

Then get the Jupyter token URL:
  sudo journalctl -u jupyter-lab --no-pager | grep -m1 -E 'http://127.0.0.1:8888/lab\\?token='
EOF
