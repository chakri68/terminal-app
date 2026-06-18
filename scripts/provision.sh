#!/usr/bin/env bash
#
# provision.sh — push setup.sh to the VPS and run it (one-time bootstrap).
# Run locally (repo root):   make provision
#
# Uses the same .env.deploy config as deploy.sh. On a brand-new VPS admin
# sshd is still on port 22, so for the very first run set VPS_SSH_PORT=22:
#   VPS_SSH_PORT=22 make provision
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -f .env.deploy ]]; then
  set -a; source .env.deploy; set +a
fi

: "${VPS_HOST:?Set VPS_HOST in .env.deploy or env (the VPS hostname/IP)}"
VPS_USER="${VPS_USER:-root}"
VPS_SSH_PORT="${VPS_SSH_PORT:-2222}"

REMOTE="${VPS_USER}@${VPS_HOST}"
if [[ "$VPS_USER" == "root" ]]; then SUDO=""; else SUDO="sudo"; fi

echo "==> Copying setup.sh + move-admin-sshd.sh to ${REMOTE}"
scp -P "${VPS_SSH_PORT}" scripts/setup.sh scripts/move-admin-sshd.sh "${REMOTE}:/tmp/"

echo "==> Running setup.sh on the VPS"
ssh -p "${VPS_SSH_PORT}" "${REMOTE}" "${SUDO} bash /tmp/setup.sh"

echo "==> Provisioned. move-admin-sshd.sh is at /tmp on the VPS if you need it."
