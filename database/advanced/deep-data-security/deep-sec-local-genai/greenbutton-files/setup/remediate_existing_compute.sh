#!/usr/bin/env bash
# Remediate selected Security Central findings on an existing Deep Sec compute VM.
#
# Run on each VM:
#   sudo bash remediate_existing_compute.sh
#
# This script addresses:
#   - QID 38909: SHA-1 algorithms offered by OpenSSH
#   - QID 11: RPC services, but only when the host has no detected NFS dependency
#   - QID 86729: password-form autocomplete in both Deep Sec applications
#   - Missing Falcon heartbeat caused by a stopped or disabled installed sensor
#
# This script cannot resolve QID 86728 while a password form remains reachable
# over plain HTTP. That finding requires HTTPS, removal of public access, stopping
# the web services, or an approved time-limited exception.

set -Eeuo pipefail

readonly customer_template=/opt/deep-sec-customer-sales/templates/index.html
readonly admin_template=/opt/deep-sec-admin-console/templates/login.html
readonly customer_service=deep-sec-customer-sales.service
readonly admin_service=deep-sec-admin-console.service

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
warnings=0

log() {
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"
}

warn() {
  printf '[%s] WARNING: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2
  warnings=$((warnings + 1))
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    printf 'ERROR: run this script with sudo.\n' >&2
    exit 1
  fi
}

unit_exists() {
  systemctl cat "$1" >/dev/null 2>&1
}

effective_sshd_algorithms() {
  sshd -T |
    grep -Ei '^(hostkeyalgorithms|pubkeyacceptedalgorithms|casignaturealgorithms|kexalgorithms|macs) '
}

sshd_offers_sha1() {
  effective_sshd_algorithms |
    grep -Eiq '(^|[=,[:space:]])(ssh-rsa|[^,[:space:]]*sha1[^,[:space:]]*)($|[,[:space:]])'
}

remediate_ssh() {
  log 'Checking the system cryptographic policy and effective SSH algorithms.'

  if ! command -v update-crypto-policies >/dev/null 2>&1; then
    warn 'update-crypto-policies is unavailable; SSH policy was not changed.'
    return
  fi

  local current_policy
  current_policy=$(update-crypto-policies --show)
  printf 'Current crypto policy: %s\n' "$current_policy"

  if ! update-crypto-policies --check; then
    warn 'The configured crypto policy does not match its generated policy.'
  fi

  if sshd_offers_sha1; then
    log 'SHA-1 is offered by sshd; applying DEFAULT:NO-SHA1.'
    update-crypto-policies --set DEFAULT:NO-SHA1

    if sshd_offers_sha1; then
      log 'The base policy still permits SHA-1 MACs; installing an sshd MAC override.'
      install -d -m 0755 /etc/ssh/sshd_config.d
      printf '%s\n' 'MACs hmac-sha2-256,umac-128@openssh.com,hmac-sha2-512' > /etc/ssh/sshd_config.d/00-deep-sec-no-sha1.conf
      chmod 0644 /etc/ssh/sshd_config.d/00-deep-sec-no-sha1.conf
    fi
  else
    log 'The effective sshd configuration does not offer SHA-1.'
  fi

  sshd -t
  systemctl restart sshd
  systemctl is-active --quiet sshd

  if sshd_offers_sha1; then
    warn 'SHA-1 is still present after restarting sshd; inspect sshd_config overrides.'
  else
    log 'SSH verification passed after restart.'
  fi

  effective_sshd_algorithms
  systemctl show sshd -p ActiveEnterTimestamp
}

has_nfs_dependency() {
  if findmnt -rn -t nfs,nfs4 | grep -q .; then
    return 0
  fi

  if [[ -r /etc/exports ]] &&
     awk '!/^[[:space:]]*(#|$)/ { found=1 } END { exit !found }' /etc/exports; then
    return 0
  fi

  if systemctl is-active --quiet nfs-server.service; then
    return 0
  fi

  return 1
}

remediate_rpc() {
  log 'Checking for NFS dependencies before changing RPC services.'

  if has_nfs_dependency; then
    warn 'An NFS mount, export, or active NFS server was detected; RPC was left unchanged.'
    findmnt -rn -t nfs,nfs4 || true
    return
  fi

  if command -v rpcinfo >/dev/null 2>&1; then
    local registered_rpc
    registered_rpc=$({ rpcinfo -p localhost 2>/dev/null || true; } |
      awk 'NR > 1 && $1 != 100000 { print }')
    if [[ -n $registered_rpc ]]; then
      warn 'A non-portmapper RPC program is registered; RPC was left unchanged for review.'
      printf '%s\n' "$registered_rpc"
      return
    fi
  fi

  if ! unit_exists rpcbind.service && ! unit_exists rpcbind.socket; then
    log 'rpcbind is not installed as a systemd service.'
    return
  fi

  log 'No NFS dependency was detected; disabling rpcbind.'
  systemctl disable --now rpcbind.socket 2>/dev/null || true
  systemctl disable --now rpcbind.service 2>/dev/null || true
  systemctl mask rpcbind.socket rpcbind.service >/dev/null

  if systemctl is-active --quiet rpcbind.socket ||
     systemctl is-active --quiet rpcbind.service; then
    warn 'rpcbind remains active.'
  else
    log 'rpcbind is disabled, stopped, and masked.'
  fi

  if command -v rpcinfo >/dev/null 2>&1 && rpcinfo -p localhost >/dev/null 2>&1; then
    warn 'An RPC port mapper still responds locally; inspect rpcinfo -p and active services.'
    rpcinfo -p localhost || true
  fi
}

patch_login_template() {
  local path=$1
  local service=$2

  if [[ ! -f $path ]]; then
    warn "Login template not found: $path"
    return
  fi

  if grep -Eq '<form id="login-form"[^>]*autocomplete="off"' "$path" &&
     grep -Eq 'type="password"[^>]*autocomplete="off"' "$path"; then
    log "Password autocomplete is already disabled in $path."
    return
  fi

  cp -a "$path" "$path.security-central-$timestamp.bak"

  sed -i -E '/<form id="login-form"/ {
    /autocomplete=/! s/<form id="login-form"/<form id="login-form" autocomplete="off"/
  }' "$path"
  sed -i -E '/type="password"/ {
    s/autocomplete="[^"]*"/autocomplete="off"/
    /autocomplete=/! s/type="password"/type="password" autocomplete="off"/
  }' "$path"

  if ! grep -Eq '<form id="login-form"[^>]*autocomplete="off"' "$path" ||
     ! grep -Eq 'type="password"[^>]*autocomplete="off"' "$path"; then
    warn "Could not verify the autocomplete remediation in $path; restoring its backup."
    cp -a "$path.security-central-$timestamp.bak" "$path"
    return
  fi

  if unit_exists "$service"; then
    systemctl restart "$service"
    systemctl is-active --quiet "$service"
  else
    warn "Service unit not found after patching $path: $service"
  fi

  log "Password autocomplete remediation verified in $path."
}

remediate_password_forms() {
  log 'Disabling password autocomplete in the deployed Deep Sec applications.'
  patch_login_template "$customer_template" "$customer_service"
  patch_login_template "$admin_template" "$admin_service"

  for port in 7777 7778; do
    if curl -fsS --max-time 5 "http://127.0.0.1:$port/" |
       grep -Eq '<form id="login-form"[^>]*autocomplete="off"'; then
      log "Rendered login form verification passed on localhost:$port."
    else
      warn "Could not verify a rendered remediated login form on localhost:$port."
    fi
  done
}

check_falcon() {
  log 'Checking the installed Falcon sensor.'

  if ! unit_exists falcon-sensor.service; then
    warn 'falcon-sensor.service is not installed; use the approved internal installer.'
    return
  fi

  if ! systemctl enable falcon-sensor.service >/dev/null; then
    warn 'Falcon sensor could not be enabled at boot.'
  fi
  if ! systemctl is-active --quiet falcon-sensor.service; then
    systemctl restart falcon-sensor.service
  fi

  if systemctl is-active --quiet falcon-sensor.service; then
    log 'Falcon sensor is enabled and active.'
  else
    warn 'Falcon sensor is not active.'
  fi

  journalctl -u falcon-sensor.service --since '24 hours ago' --no-pager |
    grep -Ei 'connected|certificate verified|error|failed' |
    tail -30 || true
}

report_remaining_work() {
  printf '\n'
  printf '%s\n' '================ Remediation summary ================'
  printf 'Warnings requiring review: %d\n' "$warnings"
  printf '%s\n' 'QID 86728 remains unresolved while either password form is reachable over plain HTTP.'
  printf '%s\n' 'For intentionally short-lived training VMs, obtain a time-limited exception or terminate the VM before its compliance deadline.'
  printf '%s\n' 'Run an external SSH algorithm scan and recheck Security Central after 24 hours.'
}

main() {
  require_root
  remediate_ssh
  remediate_rpc
  remediate_password_forms
  check_falcon
  report_remaining_work
}

main "$@"
