#!/usr/bin/env bash
#
# move-admin-sshd.sh — relocate the system's admin OpenSSH daemon off port 22
# so the app can own it, WITHOUT locking yourself out. Run AS ROOT on the VPS.
#
#   sudo bash move-admin-sshd.sh add       # listen on BOTH 22 and ADMIN_PORT
#   # ---> open a NEW terminal and verify:  ssh -p 2222 user@vps  <---
#   sudo bash move-admin-sshd.sh finalize  # drop 22, freeing it for the app
#
# Every change is validated with `sshd -t` before the daemon is reloaded.
set -euo pipefail

ADMIN_PORT="${ADMIN_PORT:-2222}"
DROPIN_DIR="/etc/ssh/sshd_config.d"
DROPIN="${DROPIN_DIR}/10-admin-port.conf"

if [[ $EUID -ne 0 ]]; then echo "ERROR: run as root" >&2; exit 1; fi

# Pick the right service name (ssh on Debian/Ubuntu, sshd on RHEL).
SVC="ssh"; systemctl list-unit-files 2>/dev/null | grep -q '^sshd\.service' && SVC="sshd"

reload() {
  echo "==> Validating sshd config"
  sshd -t
  echo "==> Reloading ${SVC}"
  systemctl reload "${SVC}" || systemctl restart "${SVC}"
}

case "${1:-}" in
  add)
    mkdir -p "${DROPIN_DIR}"
    cat > "${DROPIN}" <<EOF
# Managed by move-admin-sshd.sh — admin SSH on both 22 and ${ADMIN_PORT}.
Port 22
Port ${ADMIN_PORT}
EOF
    if command -v ufw &>/dev/null; then ufw allow "${ADMIN_PORT}/tcp" || true; fi
    reload
    echo
    echo ">>> sshd now listens on 22 AND ${ADMIN_PORT}."
    echo ">>> In a NEW terminal, verify:  ssh -p ${ADMIN_PORT} <user>@<vps>"
    echo ">>> Once that works, run:        sudo bash $0 finalize"
    ;;
  finalize)
    cat > "${DROPIN}" <<EOF
# Managed by move-admin-sshd.sh — admin SSH on ${ADMIN_PORT} only.
Port ${ADMIN_PORT}
EOF
    reload
    echo
    echo ">>> Admin sshd now listens on ${ADMIN_PORT} only. Port 22 is free for the app."
    echo ">>> Deploy locally:  VPS_SSH_PORT=${ADMIN_PORT} make deploy"
    ;;
  *)
    echo "usage: $0 {add|finalize}   (ADMIN_PORT=${ADMIN_PORT})" >&2
    exit 2
    ;;
esac
