#!/usr/bin/env bash
#
# deploy.sh — build a static binary locally and ship it to the VPS.
# Run locally (repo root):   make deploy   (or  bash scripts/deploy.sh)
#
# Config comes from .env.deploy (gitignored) or the environment:
#   VPS_HOST      (required)  hostname or IP of the VPS
#   VPS_USER      (root)      a user that can sudo on the VPS
#   VPS_SSH_PORT  (2222)      the ADMIN sshd port (not the app's port)
#   BIN_PATH      (/usr/local/bin/terminal-app)
#   SERVICE       (terminal-app)
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -f .env.deploy ]]; then
  set -a; source .env.deploy; set +a
fi

: "${VPS_HOST:?Set VPS_HOST in .env.deploy or env (the VPS hostname/IP)}"
VPS_USER="${VPS_USER:-root}"
VPS_SSH_PORT="${VPS_SSH_PORT:-2222}"
BIN_PATH="${BIN_PATH:-/usr/local/bin/terminal-app}"
SERVICE="${SERVICE:-terminal-app}"

REMOTE="${VPS_USER}@${VPS_HOST}"
SSH=(ssh -p "${VPS_SSH_PORT}" "${REMOTE}")
if [[ "$VPS_USER" == "root" ]]; then SUDO=""; else SUDO="sudo"; fi

echo "==> Building static linux/amd64 binary"
mkdir -p dist
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build -trimpath -ldflags="-s -w" -o dist/terminal-app .

echo "==> Uploading to ${REMOTE}:/tmp/terminal-app.new"
scp -P "${VPS_SSH_PORT}" dist/terminal-app "${REMOTE}:/tmp/terminal-app.new"

echo "==> Installing binary and restarting ${SERVICE}"
# install to a staging path on the target filesystem, then atomic rename over
# the (possibly running) binary — avoids ETXTBSY and gives a clean swap.
"${SSH[@]}" "
  set -e
  ${SUDO} install -m 0755 /tmp/terminal-app.new ${BIN_PATH}.new
  ${SUDO} mv -f ${BIN_PATH}.new ${BIN_PATH}
  ${SUDO} rm -f /tmp/terminal-app.new
  ${SUDO} systemctl restart ${SERVICE}
  ${SUDO} systemctl --no-pager --lines=0 status ${SERVICE} | head -n 5
"

echo "==> Deployed. Connect with:  ssh ${VPS_HOST}"
