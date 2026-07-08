# terminal.chakri.me

My website, but you `ssh` into it. Shameless nod to
[terminal.shop](https://terminal.shop) — they proved the bit works, so.
You run `ssh terminal.chakri.me` and get a terminal UI instead of a web
page. Built on [Wish](https://github.com/charmbracelet/wish) +
[Bubble Tea](https://github.com/charmbracelet/bubbletea): Wish speaks SSH, Bubble
Tea draws the screen.

## Local development

```sh
make run                 # starts on 0.0.0.0:2222
ssh -p 2222 localhost    # connect (requires a PTY)
```

First run generates the SSH host key at `.ssh/ssh_host_ed25519` (gitignored), so
you don't have to.

Everything's configured through env vars: `HOST` (default `0.0.0.0`), `PORT`
(default `2222`), `HOST_KEY_PATH` (default `.ssh/ssh_host_ed25519`).

## Deploying to a VPS

**The real step-by-step lives in [`DEPLOY.md`](./DEPLOY.md) — go read that.** The
short version:

Build a static binary locally, ship it, run it as a hardened `systemd` service on
port 22 — so people connect with a bare `ssh terminal.chakri.me`, no port to
remember. Your own admin `sshd` gets shoved to port 2222 to make room. No Go
toolchain touches the VPS; it only ever sees the finished binary.

```sh
cp .env.deploy.example .env.deploy   # set VPS_HOST / VPS_USER / VPS_SSH_PORT
make provision                       # one-time: install the service + move-helper
# ...do the port move (see DEPLOY.md), then set VPS_SSH_PORT=2222...
make deploy                          # every update after that
```

### Poking at the VPS (admin's on port 2222, remember)

```sh
ssh -p 2222 root@terminal.chakri.me 'systemctl status terminal-app'
ssh -p 2222 root@terminal.chakri.me 'journalctl -u terminal-app -f'   # live logs
ssh -p 2222 root@terminal.chakri.me 'systemctl restart terminal-app'
```

## What's where

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
