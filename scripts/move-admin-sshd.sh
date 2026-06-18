#!/usr/bin/env bash
#
# move-admin-sshd.sh — relocate the system's admin OpenSSH daemon off port 22
# so the app can own it, WITHOUT locking yourself out. Run AS ROOT on the VPS.
#
#   sudo bash move-admin-sshd.sh add       # listen on BOTH 22 and ADMIN_PORT
#   # ---> open a NEW terminal and verify:  ssh -p 2222 user@vps  <---
#   sudo bash move-admin-sshd.sh finalize  # drop 22, freeing it for the app
#
# Handles BOTH setups:
#   * socket-activated ssh (modern Ubuntu) — edits ssh.socket's ListenStream
#   * traditional sshd                      — edits sshd_config's Port
# It auto-detects which one your box uses.
set -euo pipefail

ADMIN_PORT="${ADMIN_PORT:-2222}"
SSHD_DROPIN="/etc/ssh/sshd_config.d/10-admin-port.conf"
SOCKET_DROPIN_DIR="/etc/systemd/system/ssh.socket.d"
SOCKET_DROPIN="${SOCKET_DROPIN_DIR}/10-admin-port.conf"

if [[ $EUID -ne 0 ]]; then echo "ERROR: run as root" >&2; exit 1; fi

# Service name: ssh on Debian/Ubuntu, sshd on RHEL.
SVC="ssh"; systemctl list-unit-files 2>/dev/null | grep -q '^sshd\.service' && SVC="sshd"

# Socket-activated? Then systemd owns the listening socket and sshd_config's
# Port lines are IGNORED — we must set ListenStream on ssh.socket instead.
socket_mode() { systemctl is-active --quiet ssh.socket 2>/dev/null; }

open_fw() { command -v ufw &>/dev/null && ufw allow "${ADMIN_PORT}/tcp" >/dev/null || true; }

# apply_ports PORT...  — make the admin daemon listen on exactly these ports.
apply_ports() {
  if socket_mode; then
    echo "==> Detected socket activation — configuring ssh.socket"
    mkdir -p "${SOCKET_DROPIN_DIR}"
    {
      echo "# Managed by move-admin-sshd.sh"
      echo "[Socket]"
      echo "ListenStream="            # reset systemd's default (port 22)
      # Bind each family explicitly: on boxes with bindv6only set, a bare
      # "ListenStream=<port>" yields an IPv6-only socket and IPv4 clients get
      # "connection refused". BindIPv6Only=ipv6-only stops the [::] sockets
      # from also claiming IPv4 (which would collide with the 0.0.0.0 ones).
      for p in "$@"; do
        echo "ListenStream=0.0.0.0:${p}"
        echo "ListenStream=[::]:${p}"
      done
      echo "BindIPv6Only=ipv6-only"
    } > "${SOCKET_DROPIN}"
    rm -f "${SSHD_DROPIN}"            # clear any stale (ignored) Port drop-in
    systemctl daemon-reload
    systemctl restart ssh.socket
    systemctl restart "${SVC}" 2>/dev/null || true
  else
    echo "==> Traditional sshd — configuring sshd_config"
    mkdir -p "$(dirname "${SSHD_DROPIN}")"
    {
      echo "# Managed by move-admin-sshd.sh"
      for p in "$@"; do echo "Port ${p}"; done
    } > "${SSHD_DROPIN}"
    rm -f "${SOCKET_DROPIN}"
    sshd -t                          # validate before applying
    systemctl reload "${SVC}" || systemctl restart "${SVC}"
  fi
}

listening() { ss -tlnH "( sport = :$1 )" 2>/dev/null | grep -q .; }

case "${1:-}" in
  add)
    open_fw
    apply_ports 22 "${ADMIN_PORT}"
    echo
    if listening "${ADMIN_PORT}"; then
      echo ">>> OK: admin SSH now listens on 22 AND ${ADMIN_PORT}."
    else
      echo "!!  ${ADMIN_PORT} is NOT listening yet — check 'systemctl status ssh.socket'."
    fi
    echo ">>> In a NEW terminal, verify:  ssh -p ${ADMIN_PORT} <user>@<vps>"
    echo ">>> Only once that works, run:  sudo bash $0 finalize"
    ;;
  finalize)
    apply_ports "${ADMIN_PORT}"
    echo
    echo ">>> Admin SSH now listens on ${ADMIN_PORT} only. Port 22 is free for the app."
    echo ">>> Set VPS_SSH_PORT=${ADMIN_PORT} in .env.deploy, then:  make deploy"
    ;;
  status)
    echo "socket_mode: $(socket_mode && echo yes || echo no)"
    echo "listeners:"; ss -tlnp 2>/dev/null | grep -E ':(22|'"${ADMIN_PORT}"')\b' || echo "  (none on 22/${ADMIN_PORT})"
    ;;
  *)
    echo "usage: $0 {add|finalize|status}   (ADMIN_PORT=${ADMIN_PORT})" >&2
    exit 2
    ;;
esac
