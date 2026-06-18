# terminal.chakri.me

An SSH-accessible TUI app, like [terminal.shop](https://terminal.shop). Built
with [Wish](https://github.com/charmbracelet/wish) +
[Bubble Tea](https://github.com/charmbracelet/bubbletea). Users connect with a
plain `ssh terminal.chakri.me` and get a terminal UI.

## Local development

```sh
make run                 # starts on 0.0.0.0:2222
ssh -p 2222 localhost    # connect (requires a PTY)
```

The SSH host key is generated on first run at `.ssh/ssh_host_ed25519` (gitignored).

Configuration is via env vars: `HOST` (default `0.0.0.0`), `PORT` (default
`2222`), `HOST_KEY_PATH` (default `.ssh/ssh_host_ed25519`).

## Deploying to a VPS

The model: **build a static binary locally → ship it → run as a hardened
`systemd` service** that binds port 22 (so users connect with a bare
`ssh terminal.chakri.me`). No Go toolchain on the VPS. Updates are one command.

### 1. Configure

```sh
cp .env.deploy.example .env.deploy
# edit VPS_HOST / VPS_USER / VPS_SSH_PORT
```

### 2. Move admin SSH off port 22 (so the app can use it)

The app wants port 22, but that's where normal `sshd` lives. Move it
**safely** (no lockout) with the helper — on the VPS, as root:

```sh
# (provision in step 3 copies this script to /tmp on the VPS)
sudo bash /tmp/move-admin-sshd.sh add        # admin sshd now on BOTH 22 and 2222
# open a NEW terminal and confirm:  ssh -p 2222 <user>@<vps>
sudo bash /tmp/move-admin-sshd.sh finalize    # drop 22 — now free for the app
```

After this, admin port is `2222`; keep `VPS_SSH_PORT=2222` in `.env.deploy`.

> On a brand-new box admin sshd is still on 22, so run the first provision
> with `VPS_SSH_PORT=22 make provision`, then do the move above.

### 3. Provision (one time)

```sh
make provision    # installs the service user, data dir, and systemd unit
```

### 4. Deploy (every update)

```sh
make deploy       # cross-compiles, uploads, atomic-swaps the binary, restarts
```

That's the whole update loop: commit changes, then `make deploy`. The
script builds `linux/amd64`, ships it, swaps the binary atomically (no
`ETXTBSY`), and restarts the service.

### Useful VPS commands

```sh
systemctl status terminal-app
journalctl -u terminal-app -f          # live logs
systemctl restart terminal-app
```

## How it fits together

| File                         | Purpose                                              |
| ---------------------------- | ---------------------------------------------------- |
| `main.go`                    | Wish SSH server + Bubble Tea TUI                     |
| `scripts/setup.sh`           | Provisions the service on the VPS (run by provision) |
| `scripts/provision.sh`       | Pushes & runs `setup.sh` on the VPS                  |
| `scripts/deploy.sh`          | Build → ship → swap → restart                        |
| `scripts/move-admin-sshd.sh` | Safely relocate admin sshd off port 22               |
| `Makefile`                   | `run` / `build` / `provision` / `deploy`             |
| `.env.deploy`                | VPS connection details (gitignored)                  |
