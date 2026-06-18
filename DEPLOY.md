# Deploy runbook

How `terminal.chakri.me` is deployed. Read this when you've forgotten everything.

## The mental model (read this first)

There are **two SSH ports** and they are NOT the same thing:

| Port     | Who uses it     | What's listening                                         |
| -------- | --------------- | -------------------------------------------------------- |
| **22**   | your **users**  | the **app** (Wish/Bubble Tea) → `ssh terminal.chakri.me` |
| **2222** | **you** (admin) | the OS **sshd** → `ssh -p 2222 root@terminal.chakri.me`  |

Only one program can listen on a port. The app gets the nice one (22) so users
type a clean `ssh terminal.chakri.me`. Your admin login moves to 2222.

`VPS_SSH_PORT` in `.env.deploy` = the port **you** use to admin/deploy = **2222**
(after the one-time move below). It is _not_ the app's port.

---

## One-time setup (do this once, ever)

Your `.env.deploy` to start:

```sh
VPS_HOST=terminal.chakri.me
VPS_USER=root
VPS_SSH_PORT=22          # admin sshd is still on 22 at this point
```

### Step 1 — install the app service + copy the move-helper onto the box

```sh
make provision
```

Installs the systemd service (set to run the app on **port 22**) and drops
`move-admin-sshd.sh` at `/tmp` on the server. The service won't start yet —
there's no binary and port 22 is still busy. That's expected.

### Step 2 — open a SECOND admin door (port 2222), keep 22 for now

```sh
ssh root@terminal.chakri.me
sudo bash /tmp/move-admin-sshd.sh add
sudo bash /tmp/move-admin-sshd.sh status   # sanity-check what's listening
```

Now sshd listens on **both** 22 and 2222. Your current session stays alive.

> **Ubuntu socket activation gotcha.** Modern Ubuntu runs ssh via `ssh.socket`
> (systemd owns the listening socket and hands it to sshd). On those boxes the
> `Port` lines in `sshd_config` are **ignored** — the ports live in
> `ssh.socket`'s `ListenStream`. `move-admin-sshd.sh` auto-detects this; check
> with `status`. If you're ever doing it by hand, edit
> `/etc/systemd/system/ssh.socket.d/10-admin-port.conf` (a leading empty
> `ListenStream=` resets the default 22), then
> `systemctl daemon-reload && systemctl restart ssh.socket`. Tell-tale sign:
> `lsof -i :22` shows `systemd` (pid 1) holding the socket.
>
> **IPv4 gotcha (within socket activation).** On some images a bare
> `ListenStream=<port>` binds **IPv6 only**, so IPv4 clients get "connection
> refused" even though `lsof` shows it listening. Diagnose by testing the
> loopback _on the box_: `ssh -p 2222 root@127.0.0.1` — if that's also refused,
> it's a bind problem, not a firewall. Fix: bind both families explicitly with
> `ListenStream=0.0.0.0:<port>` + `ListenStream=[::]:<port>` and
> `BindIPv6Only=ipv6-only`. The current `move-admin-sshd.sh` does this for you.
>
> **If it's refused only from _outside_ (loopback works):** it's a firewall.
> Check the **DigitalOcean Cloud Firewall** in the dashboard (it's outside the
> box, so `ufw` can't see it) and add an inbound TCP rule for 2222; also
> `ufw allow 2222/tcp` if `ufw` is active.

### Step 3 — PROVE 2222 works before you burn any bridges

In a **new terminal** (leave the Step 2 session open as a safety net):

```sh
ssh -p 2222 root@terminal.chakri.me
```

If this logs you in, you're safe to continue. If it doesn't — stop, fix it,
do NOT do Step 4. (Worst case: recover via the DigitalOcean web **Console**,
which doesn't use SSH at all.)

### Step 4 — drop port 22 from sshd, freeing it for the app

```sh
# in the verified 2222 session:
sudo bash /tmp/move-admin-sshd.sh finalize
```

Admin sshd is now on **2222 only**. Port 22 is empty and waiting for the app.

### Step 5 — point deploys at the new admin port + ship the app

Edit `.env.deploy`:

```sh
VPS_SSH_PORT=2222        # <-- changed from 22
```

Then:

```sh
make deploy
```

The app binary lands on the box and claims port 22.

### Step 6 — confirm

```sh
ssh terminal.chakri.me              # users: the app TUI
ssh -p 2222 root@terminal.chakri.me # you: admin shell
```

Done. You never touch Steps 1–5 again.

---

## Ongoing: every code change

```sh
make deploy
```

That's it. Builds a static binary locally, ships it over port 2222, swaps it
atomically, restarts the service. Uses `VPS_SSH_PORT=2222` from `.env.deploy`.

---

## Cheat sheet

```sh
# deploy a new version
make deploy

# admin the box
ssh -p 2222 root@terminal.chakri.me

# watch app logs
ssh -p 2222 root@terminal.chakri.me 'journalctl -u terminal-app -f'

# restart / status
ssh -p 2222 root@terminal.chakri.me 'systemctl restart terminal-app'
ssh -p 2222 root@terminal.chakri.me 'systemctl status terminal-app'
```

## If you're locked out

The port move can't lock you out if you did Step 3. If something else goes
wrong, use the **DigitalOcean dashboard → your Droplet → Console** — it's an
out-of-band terminal that bypasses SSH and port 22 entirely. From there you can
fix `/etc/ssh/sshd_config.d/10-admin-port.conf` and `systemctl restart ssh`.
