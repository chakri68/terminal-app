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

**Full step-by-step is in [`DEPLOY.md`](./DEPLOY.md) — read that.** Short version:

The model: **build a static binary locally → ship it → run as a hardened
`systemd` service** on port 22 (users connect with a bare `ssh terminal.chakri.me`),
with your admin `sshd` moved to port 2222. No Go toolchain on the VPS.

```sh
cp .env.deploy.example .env.deploy   # set VPS_HOST / VPS_USER / VPS_SSH_PORT
make provision                       # one-time: install the service + move-helper
# ...do the port move (see DEPLOY.md), then set VPS_SSH_PORT=2222...
make deploy                          # every update after that
```

### Useful VPS commands (admin is on port 2222)

```sh
ssh -p 2222 root@terminal.chakri.me 'systemctl status terminal-app'
ssh -p 2222 root@terminal.chakri.me 'journalctl -u terminal-app -f'   # live logs
ssh -p 2222 root@terminal.chakri.me 'systemctl restart terminal-app'
```

## How it fits together

| File                         | Purpose                                              |
| ---------------------------- | ---------------------------------------------------- |
| `DEPLOY.md`                  | The deploy runbook — the port move + update loop     |
| `main.go`                    | Wish SSH server + Bubble Tea TUI                     |
| `scripts/setup.sh`           | Provisions the service on the VPS (run by provision) |
| `scripts/provision.sh`       | Pushes & runs `setup.sh` on the VPS                  |
| `scripts/deploy.sh`          | Build → ship → swap → restart                        |
| `scripts/move-admin-sshd.sh` | Safely relocate admin sshd off port 22               |
| `Makefile`                   | `run` / `build` / `provision` / `deploy`             |
| `.env.deploy`                | VPS connection details (gitignored)                  |
