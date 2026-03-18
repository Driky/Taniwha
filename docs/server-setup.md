# Server Setup Guide

Complete operator guide for preparing a production server to run Taniwha via Docker and systemd.

---

## Prerequisites

- Debian 12 (Bookworm) or Ubuntu 22.04+ VPS
- Root or sudo access during setup
- Docker installed (`curl -fsSL https://get.docker.com | sh`)
- rtorrent already running and exposing a SCGI Unix socket (typically `/var/run/rtorrent/rpc.socket`)
- A GitHub repository with Actions enabled (CI workflow must pass before CD runs)

---

## 1. Create the deploy user

```bash
# Create a system user with no password login
sudo adduser --disabled-password --gecos "" taniwha-deploy

# Grant Docker access (allows managing containers without sudo)
sudo usermod -aG docker taniwha-deploy

# Create the directory that will hold the .env file
sudo mkdir -p /home/taniwha-deploy/taniwha
sudo chown taniwha-deploy:taniwha-deploy /home/taniwha-deploy/taniwha

# Prepare the SSH authorized_keys file on the server (run these on the server):
sudo -u taniwha-deploy mkdir -p /home/taniwha-deploy/.ssh
sudo -u taniwha-deploy chmod 700 /home/taniwha-deploy/.ssh
```

Then, **on your local machine** (not the server), generate the deploy key pair.
No passphrase — GitHub Actions loads it non-interactively and a passphrase would cause the deploy step to hang:

```bash
ssh-keygen -t ed25519 -C "taniwha-deploy@github-actions" -f ~/.ssh/taniwha_deploy

# Copy the public key to the server. Because taniwha-deploy has no password login yet,
# go via your admin user (e.g. ubuntu) using a one-liner:
cat ~/.ssh/taniwha_deploy.pub | ssh <admin-user>@<server> -p <port> "sudo tee /home/taniwha-deploy/.ssh/authorized_keys && sudo chmod 600 /home/taniwha-deploy/.ssh/authorized_keys && sudo chown taniwha-deploy:taniwha-deploy /home/taniwha-deploy/.ssh/authorized_keys"

# The private key (~/.ssh/taniwha_deploy) goes into the DEPLOY_SSH_KEY GitHub secret.
```

---

## 2. Sudoers configuration

The deploy user needs to restart the systemd unit without a password prompt.
Grant only the specific commands required — no wildcards.

```bash
sudo visudo -f /etc/sudoers.d/taniwha-deploy
```

Contents:

```
# Allows taniwha-deploy to manage the Taniwha service only
taniwha-deploy ALL=(ALL) NOPASSWD: /bin/systemctl start taniwha
taniwha-deploy ALL=(ALL) NOPASSWD: /bin/systemctl stop taniwha
taniwha-deploy ALL=(ALL) NOPASSWD: /bin/systemctl restart taniwha
taniwha-deploy ALL=(ALL) NOPASSWD: /bin/systemctl status taniwha
```

Verify the file parses correctly:

```bash
sudo visudo -c -f /etc/sudoers.d/taniwha-deploy
```

---

## 3. Install the systemd unit

On your **local machine**, substitute the `{OWNER}` placeholder with your GitHub username or organisation:

```bash
sed -i 's/{OWNER}/your-github-username/g' deploy/taniwha.service
```

Copy the unit to the server and enable it:

```bash
scp deploy/taniwha.service taniwha-deploy@<server>:/tmp/taniwha.service
ssh taniwha-deploy@<server> "sudo cp /tmp/taniwha.service /etc/systemd/system/taniwha.service"
ssh taniwha-deploy@<server> "sudo systemctl daemon-reload && sudo systemctl enable taniwha"
```

The service will start automatically on the next CD deployment (or you can start it manually after completing the steps below).

---

## 4. Environment file

Create `/home/taniwha-deploy/taniwha/.env` on the server. This file is read by `docker run --env-file` and must never be committed to version control.

```bash
sudo -u taniwha-deploy tee /home/taniwha-deploy/taniwha/.env > /dev/null << 'EOF'
# Generate with: mix phx.gen.secret
SECRET_KEY_BASE=REPLACE_WITH_64_CHARACTER_SECRET

# Public hostname of the server (used in URLs)
PHX_HOST=your.domain.example.com

# HTTP port inside the container (4000 is the default)
PORT=4000

# Path to the rtorrent SCGI socket inside the container
RTORRENT_SOCKET=/var/run/rtorrent/rpc.socket
EOF

# Restrict permissions — the file contains secrets
sudo chmod 600 /home/taniwha-deploy/taniwha/.env
sudo chown taniwha-deploy:taniwha-deploy /home/taniwha-deploy/taniwha/.env
```

Generate a secret key:

```bash
# On a machine with Elixir installed:
mix phx.gen.secret
# Or with openssl:
openssl rand -base64 48
```

---

## 5. rtorrent socket permissions

The `taniwha-deploy` user (who runs the Docker daemon client) must be able to read/write the rtorrent socket that is bind-mounted into the container.

**Option A — group membership** (preferred):

```bash
# Find the group that owns the socket
ls -la /var/run/rtorrent/rpc.socket

# Add taniwha-deploy to that group (e.g., "rtorrent")
sudo usermod -aG rtorrent taniwha-deploy
# Log out and back in, or: newgrp rtorrent
```

**Option B — ACL** (if the socket group cannot be changed):

```bash
sudo setfacl -m u:taniwha-deploy:rw /var/run/rtorrent/rpc.socket
```

---

## 6. Configure GitHub secrets

In your repository: **Settings → Secrets and variables → Actions → New repository secret**.

| Secret name | Value |
|---|---|
| `DEPLOY_SSH_KEY` | Contents of `~/.ssh/taniwha_deploy` (the private key) |
| `DEPLOY_HOST_KEY` | Output of `ssh-keyscan -H <server>` (see below) |
| `DEPLOY_USER` | `taniwha-deploy` |
| `DEPLOY_HOST` | Server IP address or hostname |

Getting the host key (run on your local machine):

```bash
ssh-keyscan -H <server>
# Copy the full output (one or more lines beginning with the hashed hostname)
# and paste it as the DEPLOY_HOST_KEY secret value.
```

> **Why not `StrictHostKeyChecking=no`?**
> Disabling host key verification exposes deployments to MITM attacks.
> The `DEPLOY_HOST_KEY` secret pins the server's public key in `known_hosts` so
> SSH will reject unexpected keys.

> **Permissions note:** The CD workflow uses `packages: write` to push to GHCR.
> Ensure your repository's workflow permissions allow this:
> **Settings → Actions → General → Workflow permissions → Read and write permissions**.

---

## 7. Rollback procedure

Each deployment tags the image with both `:latest` and the commit SHA.
To roll back to a specific version:

1. Edit the systemd unit on the server to pin a specific SHA:
   ```bash
   sudo nano /etc/systemd/system/taniwha.service
   # Change: ghcr.io/driky/taniwha:latest
   # To:     ghcr.io/driky/taniwha:<sha>
   ```

2. Reload and restart:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart taniwha
   ```

3. Verify the container started with the pinned image:
   ```bash
   docker inspect taniwha | grep Image
   ```

To resume automatic deployments, revert the unit to `:latest` and repeat steps 2–3.

---

## 8. Verification checklist

After completing setup, verify each item:

- [ ] `systemctl status taniwha` shows `active (running)` after first CD push
- [ ] `docker ps` shows the `taniwha` container running
- [ ] `curl -s http://localhost:4000` returns an HTTP response (likely a redirect to HTTPS)
- [ ] `docker logs taniwha` shows no startup errors
- [ ] `docker images ghcr.io/driky/taniwha` shows both `:latest` and SHA tags
- [ ] Push a commit to `main` → CI passes → CD triggers → new image deployed without manual intervention
- [ ] Test rollback: pin a previous SHA, restart, verify, then restore `:latest`

---

## Troubleshooting

### Container fails to start: "cannot bind to address"

**Symptom:** `docker logs taniwha` shows an error binding the HTTP port.

**Cause:** `runtime.exs` configures `ip: {0, 0, 0, 0, 0, 0, 0, 0}` (IPv6 all-interfaces) for production.
Standard Docker bridge networks may not have IPv6 enabled, causing Bandit to fail binding.

**Resolution:**

Option A — Enable IPv6 on the Docker bridge (recommended for full IPv6 support):
```bash
# Edit /etc/docker/daemon.json to add:
# { "ipv6": true, "fixed-cidr-v6": "fd00::/80" }
sudo systemctl restart docker
```

Option B — Override with an IPv4 binding by adding to `.env`:
```
IP=0.0.0.0
```
Then update `runtime.exs` to read:
```elixir
ip_string = System.get_env("IP", "::")
ip = ip_string |> String.split(".") |> Enum.map(&String.to_integer/1) |> List.to_tuple()
```
(This requires a code change and redeployment.)

### Pull fails, container already removed

**Symptom:** `docker pull` fails (network error, auth error, image not found), and there is no cached image.

**Effect:** The `docker run` in `ExecStart` also fails. systemd retries 3 times over 60 seconds, then the unit enters `failed` state.

**Resolution:**
```bash
# Check what went wrong
sudo systemctl status taniwha
journalctl -u taniwha -n 50

# After fixing the root cause (network, GHCR auth, image name), restart:
sudo systemctl restart taniwha
# If the unit is in 'failed' state, reset it first:
sudo systemctl reset-failed taniwha
sudo systemctl start taniwha
```

### Deployment downtime

During a deployment the sequence is: stop → remove → pull → start.
This causes a brief downtime of approximately 2–10 seconds (depending on network speed and startup time).
This is acceptable for v1. Zero-downtime deployments (e.g., blue/green) can be added in a future iteration.
