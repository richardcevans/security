#!/usr/bin/env bash
# Create a minimal OCI Always Free VM for the DeepSec MCP lab.
#
# Creates a new VCN, public subnet, and an Oracle Linux VM.Standard.E2.1.Micro
# instance (1/8 OCPU, 1 GB RAM). All inbound protocols are limited to the
# specified trusted home/public client CIDR.
#
# Prerequisites: OCI CLI configured for an account allowed to create Compute,
# Networking, and boot-volume resources in COMPARTMENT_ID.
#
# Required environment variables:
#   COMPARTMENT_ID    Target compartment OCID
#   SSH_SOURCE_CIDR   Your trusted home/public IP in CIDR form, for example 203.0.113.4/32
#
# Optional environment variables:
#   LAB_ENV_FILE      Lab environment file. Default: ./.deep-sec-mcp.env beside this script.
#   VM_NAME           Default: deepsec-jupyter
#   SHAPE             Default: VM.Standard.E2.1.Micro
#                     Use VM.Standard.A1.Flex with A1_OCPUS=1 and A1_MEMORY_GB=6
#                     if 1 GB is too tight for your notebook workload.
#   A1_OCPUS          Default: 1
#   A1_MEMORY_GB      Default: 6
#   IMAGE_ID          Use a specific compatible Oracle Linux image OCID.
#   BOOT_VOLUME_GB    Default: 50
#
# Example:
#   export COMPARTMENT_ID=ocid1.compartment.oc1..example
#   export SSH_PUBLIC_KEY_FILE=$HOME/.ssh/id_ed25519.pub
#   export SSH_SOURCE_CIDR=203.0.113.4/32
#   ./create_free_tier_jupyter_vm.sh

set -euo pipefail

command -v oci >/dev/null || { echo "OCI CLI is required." >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ENV_FILE="${LAB_ENV_FILE:-$SCRIPT_DIR/.deep-sec-mcp.env}"

# The MCP environment file imports non-secret tenancy and compartment values
# from the ADB OCI IAM prerequisite lab.
read_lab_env_value() {
  local key="$1" value
  value="$(awk -v key="$key" '
    $0 ~ "^[[:space:]]*export[[:space:]]+" key "=" {
      sub(/^[^=]*=/, ""); print; exit
    }
  ' "$LAB_ENV_FILE")"
  value="${value#\'}"
  value="${value%\'}"
  value="${value#\"}"
  value="${value%\"}"
  printf '%s' "$value"
}

if [[ -r "$LAB_ENV_FILE" ]]; then
  saved_tenancy_id="$(read_lab_env_value TENANCY_ID)"
  saved_tenancy_id="${saved_tenancy_id:-$(read_lab_env_value TENANCY_OCID)}"
  saved_compartment_id="$(read_lab_env_value COMPARTMENT_ID)"
  saved_compartment_id="${saved_compartment_id:-$(read_lab_env_value MCP_COMPARTMENT_OCID)}"
  saved_compartment_id="${saved_compartment_id:-$(read_lab_env_value ROOT_COMP_ID)}"
  TENANCY_ID="${TENANCY_ID:-$saved_tenancy_id}"
  COMPARTMENT_ID="${COMPARTMENT_ID:-$saved_compartment_id}"
  OCI_PROFILE_NAME="${OCI_PROFILE_NAME:-$(read_lab_env_value OCI_PROFILE_NAME)}"
fi
source "${SCRIPT_DIR}/../lib_oci_profile.sh"

# OCI CLI profiles record the tenancy OCID.  Read the active profile directly:
# OCI CLI 3.x no longer exposes the older `oci configure list` command.
# An explicit value still takes precedence.
if [[ -z "${TENANCY_ID:-}" ]]; then
  OCI_CONFIG_PATH="${OCI_CLI_CONFIG_FILE:-$HOME/.oci/config}"
  OCI_PROFILE_CONFIG_NAME="${OCI_PROFILE_SELECTED:-DEFAULT}"
  if [[ -r "$OCI_CONFIG_PATH" ]]; then
    TENANCY_ID="$(awk -v profile="$OCI_PROFILE_CONFIG_NAME" '
      /^\[/{ active = (substr($0, 2, length($0) - 2) == profile); next }
      active && /^[[:space:]]*tenancy[[:space:]]*=/ {
        sub(/^[^=]*=/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit
      }
    ' "$OCI_CONFIG_PATH")"
  fi
fi
: "${TENANCY_ID:?Could not discover TENANCY_ID. Set it explicitly to the root-tenancy OCID.}"
: "${COMPARTMENT_ID:?Could not find MCP_COMPARTMENT_OCID in $LAB_ENV_FILE. Run 00_configure_lab_env.sh first, or set COMPARTMENT_ID explicitly.}"
if [[ -z "${SSH_SOURCE_CIDR:-}" ]]; then
  command -v curl >/dev/null || { echo "Set SSH_SOURCE_CIDR to your public IP/CIDR; curl is unavailable for auto-detection." >&2; exit 1; }
  detected_ssh_ip="$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)"
  if [[ "$detected_ssh_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    SSH_SOURCE_CIDR="${detected_ssh_ip}/32"
    echo "Using detected SSH source: $SSH_SOURCE_CIDR"
  else
    echo "Could not detect a public IP. Set SSH_SOURCE_CIDR to your public IP/CIDR." >&2
    exit 1
  fi
fi

if [[ -z "${SSH_PUBLIC_KEY_FILE:-}" ]]; then
  for candidate in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
    if [[ -r "$candidate" ]]; then
      SSH_PUBLIC_KEY_FILE="$candidate"
      break
    fi
  done
fi
if [[ -z "${SSH_PUBLIC_KEY_FILE:-}" ]]; then
  command -v ssh-keygen >/dev/null || { echo "ssh-keygen is required to create an SSH key." >&2; exit 1; }
  mkdir -p "$HOME/.ssh"
  if ! ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/deepsec-jupyter"; then
    echo "Ed25519 is unavailable (for example, FIPS mode); creating an RSA 3072-bit key instead."
    ssh-keygen -q -t rsa -b 3072 -N '' -f "$HOME/.ssh/deepsec-jupyter"
  fi
  SSH_PUBLIC_KEY_FILE="$HOME/.ssh/deepsec-jupyter.pub"
  echo "Created SSH key pair: $HOME/.ssh/deepsec-jupyter(.pub)"
fi
[[ -r "$SSH_PUBLIC_KEY_FILE" ]] || { echo "Cannot read $SSH_PUBLIC_KEY_FILE" >&2; exit 1; }

VM_NAME="${VM_NAME:-deepsec-jupyter}"
SHAPE="${SHAPE:-VM.Standard.E2.1.Micro}"
A1_OCPUS="${A1_OCPUS:-1}"
A1_MEMORY_GB="${A1_MEMORY_GB:-6}"
BOOT_VOLUME_GB="${BOOT_VOLUME_GB:-50}"
DNS_LABEL="$(tr -cd '[:alnum:]' <<<"${VM_NAME,,}" | cut -c1-12)"
DNS_LABEL="${DNS_LABEL:-deepsec}"
NETWORK_NAME="${VM_NAME}-network"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "Checking CLI authentication..."
oci_with_profile iam region-subscription list --tenancy-id "$TENANCY_ID" >/dev/null

echo "Creating VCN and public subnet (all inbound protocols limited to $SSH_SOURCE_CIDR)..."
VCN_ID="$(oci_with_profile network vcn create \
  --compartment-id "$COMPARTMENT_ID" --display-name "$NETWORK_NAME" \
  --cidr-block 10.42.0.0/16 --dns-label "$DNS_LABEL" \
  --wait-for-state AVAILABLE --query 'data.id' --raw-output)"

IGW_ID="$(oci_with_profile network internet-gateway create \
  --compartment-id "$COMPARTMENT_ID" --vcn-id "$VCN_ID" \
  --display-name "${VM_NAME}-igw" --is-enabled true --query 'data.id' --raw-output)"

cat >"$tmpdir/route-rules.json" <<EOF
[{"cidrBlock":"0.0.0.0/0","networkEntityId":"$IGW_ID"}]
EOF
ROUTE_TABLE_ID="$(oci_with_profile network route-table create \
  --compartment-id "$COMPARTMENT_ID" --vcn-id "$VCN_ID" \
  --display-name "${VM_NAME}-public-rt" --route-rules "file://$tmpdir/route-rules.json" \
  --query 'data.id' --raw-output)"

cat >"$tmpdir/security-rules.json" <<EOF
[{"source":"$SSH_SOURCE_CIDR","protocol":"all","isStateless":false,"description":"All inbound protocols from trusted home/client network"}]
EOF
cat >"$tmpdir/egress-rules.json" <<'EOF'
[{"destination":"0.0.0.0/0","protocol":"all","isStateless":false,"description":"Required outbound access for OS and Python package installation"}]
EOF
SECURITY_LIST_ID="$(oci_with_profile network security-list create \
  --compartment-id "$COMPARTMENT_ID" --vcn-id "$VCN_ID" \
  --display-name "${VM_NAME}-trusted-client" --ingress-security-rules "file://$tmpdir/security-rules.json" \
  --egress-security-rules "file://$tmpdir/egress-rules.json" \
  --query 'data.id' --raw-output)"

SUBNET_ID="$(oci_with_profile network subnet create \
  --compartment-id "$COMPARTMENT_ID" --vcn-id "$VCN_ID" \
  --display-name "${VM_NAME}-public-subnet" --cidr-block 10.42.0.0/24 \
  --dns-label "pub" --route-table-id "$ROUTE_TABLE_ID" --security-list-ids "[\"$SECURITY_LIST_ID\"]" \
  --query 'data.id' --raw-output)"

AD="$(oci_with_profile iam availability-domain list --compartment-id "$TENANCY_ID" --query 'data[0].name' --raw-output)"
if [[ -n "${IMAGE_ID:-}" ]]; then
  image_id="$IMAGE_ID"
else
  image_id="$(oci_with_profile compute image list --compartment-id "$COMPARTMENT_ID" --shape "$SHAPE" \
    --operating-system 'Oracle Linux' --operating-system-version 9 --sort-by TIMECREATED --sort-order DESC \
    --query 'data[0].id' --raw-output)"
fi
[[ "$image_id" != "null" && -n "$image_id" ]] || { echo "No compatible Oracle Linux 9 image was found; set IMAGE_ID explicitly." >&2; exit 1; }

cat >"$tmpdir/cloud-init.yaml" <<'EOF'
#cloud-config
package_update: true
packages:
  - git
  - python3
  - python3-pip
  - policycoreutils-python-utils
runcmd:
  - [ bash, -lc, 'systemctl disable --now firewalld || true' ]
  - [ bash, -lc, 'dd if=/dev/zero of=/swapfile bs=1M count=2048 && chmod 600 /swapfile && mkswap /swapfile && echo /swapfile none swap defaults 0 0 >> /etc/fstab && swapon /swapfile' ]
  - [ bash, -lc, 'python3 -m venv /home/opc/deepsec-venv' ]
  - [ bash, -lc, '/home/opc/deepsec-venv/bin/pip install --upgrade pip jupyterlab oci oracledb fastapi uvicorn python-dotenv' ]
  - [ bash, -lc, 'chown -R opc:opc /home/opc/deepsec-venv' ]
  - [ bash, -lc, 'semanage fcontext -a -t bin_t "/home/opc/deepsec-venv(/.*)?" 2>/dev/null || semanage fcontext -m -t bin_t "/home/opc/deepsec-venv(/.*)?"; restorecon -RFv /home/opc/deepsec-venv' ]
  - [ bash, -lc, 'printf "[Unit]\\nDescription=JupyterLab (loopback only)\\nAfter=network-online.target\\n\\n[Service]\\nUser=opc\\nWorkingDirectory=/home/opc\\nExecStart=/home/opc/deepsec-venv/bin/jupyter lab --ip=127.0.0.1 --port=8888 --no-browser\\nRestart=on-failure\\n\\n[Install]\\nWantedBy=multi-user.target\\n" > /etc/systemd/system/jupyter-lab.service' ]
  - [ systemctl, daemon-reload ]
  - [ systemctl, enable, --now, jupyter-lab.service ]
EOF

launch_args=(
  --availability-domain "$AD"
  --compartment-id "$COMPARTMENT_ID"
  --display-name "$VM_NAME"
  --shape "$SHAPE"
  --image-id "$image_id"
  --subnet-id "$SUBNET_ID"
  --assign-public-ip true
  --ssh-authorized-keys-file "$SSH_PUBLIC_KEY_FILE"
  --user-data-file "$tmpdir/cloud-init.yaml"
  --boot-volume-size-in-gbs "$BOOT_VOLUME_GB"
  --wait-for-state RUNNING
)
if [[ "$SHAPE" == "VM.Standard.A1.Flex" ]]; then
  launch_args+=(--shape-config "{\"ocpus\": $A1_OCPUS, \"memoryInGBs\": $A1_MEMORY_GB}")
fi

echo "Launching $SHAPE in $AD..."
INSTANCE_ID="$(oci_with_profile compute instance launch "${launch_args[@]}" --query 'data.id' --raw-output)"
VNIC_ID="$(oci_with_profile compute vnic-attachment list --compartment-id "$COMPARTMENT_ID" --instance-id "$INSTANCE_ID" \
  --query 'data[0]."vnic-id"' --raw-output)"
PUBLIC_IP="$(oci_with_profile network vnic get --vnic-id "$VNIC_ID" --query 'data."public-ip"' --raw-output)"

cat <<EOF

Created instance: $INSTANCE_ID
Public IP:        $PUBLIC_IP

Wait a few minutes for cloud-init, then connect:
  ssh -L 8888:127.0.0.1:8888 opc@$PUBLIC_IP

Open the Jupyter URL printed by:
  ssh opc@$PUBLIC_IP 'sudo journalctl -u jupyter-lab --no-pager | grep -m1 -E "http://127.0.0.1:8888/lab\?token="'

Jupyter has no public ingress rule.  Use the SSH tunnel above.

After you copy and extract this workshop ZIP on the VM, run this idempotent
preparation script to recreate the Jupyter setup and create an empty app workspace:
  sudo ./10_prepare_jupyter_app_workspace.sh

To let code on this VM call OCI APIs without an API key, create an IAM dynamic group
whose matching rule is:
  ALL {instance.id = '$INSTANCE_ID'}

Then grant only the permissions the app needs to that dynamic group.  For example,
the OCI CLI on the VM can use instance principal authentication with:
  OCI_CLI_AUTH=instance_principal oci os ns get
EOF
