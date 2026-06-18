#!/usr/bin/env bash
#
# setup.sh — one-time provisioning for terminal.chakri.me on a VPS.
# Run AS ROOT on the VPS:   sudo bash setup.sh
#
# Idempotent: safe to re-run. It creates a service user, a data dir for the
# SSH host key, and a hardened systemd unit. It does NOT build or place the
# binary — that's `make deploy` locally. The service starts once the
# binary exists at BIN_PATH.
set -euo pipefail

APP_NAME="${APP_NAME:-terminal-app}"
SERVICE_USER="${SERVICE_USER:-terminal}"
BIN_PATH="${BIN_PATH:-/usr/local/bin/terminal-app}"
DATA_DIR="${DATA_DIR:-/var/lib/terminal-app}"
LISTEN_HOST="${LISTEN_HOST:-0.0.0.0}"
LISTEN_PORT="${LISTEN_PORT:-22}"

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root (e.g. sudo bash setup.sh)" >&2
  exit 1
fi

echo "==> Creating service user '${SERVICE_USER}' (if missing)"
if ! id "$SERVICE_USER" &>/dev/null; then
  useradd --system --home-dir "$DATA_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"
fi

echo "==> Creating data dir ${DATA_DIR} (holds the SSH host key)"
install -d -o "$SERVICE_USER" -g "$SERVICE_USER" -m 0750 "$DATA_DIR"

echo "==> Writing /etc/systemd/system/${APP_NAME}.service"
cat > "/etc/systemd/system/${APP_NAME}.service" <<EOF
[Unit]
Description=terminal.chakri.me SSH app
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${DATA_DIR}
Environment=HOST=${LISTEN_HOST}
Environment=PORT=${LISTEN_PORT}
Environment=HOST_KEY_PATH=${DATA_DIR}/ssh_host_ed25519
ExecStart=${BIN_PATH}
Restart=on-failure
RestartSec=2

# Bind to a privileged port (22) without running as root.
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

# Hardening.
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6
ReadWritePaths=${DATA_DIR}

[Install]
WantedBy=multi-user.target
EOF

echo "==> Enabling service (daemon-reload + enable)"
systemctl daemon-reload
systemctl enable "${APP_NAME}.service" >/dev/null

if command -v ufw &>/dev/null; then
  echo "==> Opening port ${LISTEN_PORT}/tcp in ufw"
  ufw allow "${LISTEN_PORT}/tcp" || true
fi

echo
echo "==> Setup complete."

# Warn if the admin sshd is sitting on the port we want for the app.
if [[ "$LISTEN_PORT" == "22" ]] && ss -tlnp 2>/dev/null | grep -qE ':22\b.*sshd'; then
  cat <<'WARN'

!!  WARNING: admin sshd is currently listening on port 22.
!!  The app cannot bind port 22 until sshd moves off it, or you'll lock
!!  yourself out. Run scripts/move-admin-sshd.sh FIRST (see README):
!!      sudo bash move-admin-sshd.sh add        # adds 2222, keeps 22
!!      # reconnect on 2222 to verify, THEN:
!!      sudo bash move-admin-sshd.sh finalize    # drops 22, frees it for the app
WARN
fi

echo
echo "Next: locally run 'make deploy' to ship the binary."
echo "The '${APP_NAME}' service starts automatically once ${BIN_PATH} exists."
