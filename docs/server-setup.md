# Server Setup Guide

Complete operator guide for preparing a production server to run Taniwha via Docker and systemd.

---

## Automated setup (recommended)

A script automates all steps below. Run it once from the project root on your local machine:

```bash
./deploy/setup-server.sh \
  --admin-user ubuntu \
  --server driky.lol \
  --port 7777
```

The script will:
1. Check local prerequisites (`ssh`, `scp`, `ssh-keyscan`, `openssl`)
2. Generate `~/.ssh/taniwha_deploy` (skipped if it already exists)
3. Create the `taniwha-deploy` user and sudoers entry on the server
4. Install the deploy public key
5. Prompt you for `PHX_HOST`, `RTORRENT_SOCKET`, and `PORT`, then write `.env`
6. Copy and enable the systemd unit
7. Print all GitHub secrets (`DEPLOY_SSH_KEY`, `DEPLOY_HOST_KEY`, etc.) ready to copy-paste

The manual steps below are kept for reference and troubleshooting.

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

Run this **from your local machine** via the admin user:

```bash
ssh <admin-user>@<server> -p <port> "printf 'taniwha-deploy ALL=(ALL) NOPASSWD: /bin/systemctl start taniwha\ntaniwha-deploy ALL=(ALL) NOPASSWD: /bin/systemctl stop taniwha\ntaniwha-deploy ALL=(ALL) NOPASSWD: /bin/systemctl restart taniwha\ntaniwha-deploy ALL=(ALL) NOPASSWD: /bin/systemctl status taniwha\ntaniwha-deploy ALL=(ALL) NOPASSWD: /bin/cp /tmp/taniwha.service /etc/systemd/system/taniwha.service\ntaniwha-deploy ALL=(ALL) NOPASSWD: /bin/systemctl daemon-reload\ntaniwha-deploy ALL=(ALL) NOPASSWD: /bin/systemctl enable taniwha\n' | sudo tee /etc/sudoers.d/taniwha-deploy && sudo chmod 440 /etc/sudoers.d/taniwha-deploy"
```

This grants exactly what is needed to complete the unit installation in section 3 and for CD deployments — nothing more.

Verify the file parses correctly (on the server):

```bash
sudo visudo -c -f /etc/sudoers.d/taniwha-deploy
```

---

## 3. Install the systemd unit

On your **local machine**, substitute the `{OWNER}` placeholder with your GitHub username or organisation:

```bash
sed -i 's/{OWNER}/your-github-username/g' deploy/taniwha.service
```

Copy the unit to the server and enable it (from your local machine):

```bash
scp -P <port> -i ~/.ssh/taniwha_deploy deploy/taniwha.service taniwha-deploy@<server>:/tmp/taniwha.service
ssh -i ~/.ssh/taniwha_deploy -p <port> taniwha-deploy@<server> "sudo cp /tmp/taniwha.service /etc/systemd/system/taniwha.service"
ssh -i ~/.ssh/taniwha_deploy -p <port> taniwha-deploy@<server> "sudo systemctl daemon-reload && sudo systemctl enable taniwha"
```

The service will start automatically on the next CD deployment (or you can start it manually after completing the steps below).

---

## 4. Environment file

Create `/home/taniwha-deploy/taniwha/.env` on the server. This file is read by `docker run --env-file` and must never be committed to version control.

First, generate a secret key (on any machine with Elixir or openssl):

```bash
# With Elixir:
mix phx.gen.secret
# Or with openssl:
openssl rand -base64 48
```

Then create the file on the server, substituting your actual values:

```bash
printf 'SECRET_KEY_BASE=REPLACE_WITH_64_CHARACTER_SECRET\nPHX_HOST=your.domain.example.com\nPORT=4000\nRTORRENT_SOCKET=/var/run/rtorrent/rpc.socket\n' | sudo -u taniwha-deploy tee /home/taniwha-deploy/taniwha/.env > /dev/null

# Restrict permissions — the file contains secrets
sudo chmod 600 /home/taniwha-deploy/taniwha/.env
sudo chown taniwha-deploy:taniwha-deploy /home/taniwha-deploy/taniwha/.env
```


---

## 4b. Observability (optional)

Taniwha ships with OpenTelemetry (OTel) auto-instrumentation. Traces are exported via OTLP to any compatible backend (SigNoz, Grafana Tempo, Jaeger, Datadog, etc.).

### Environment variables

Add the following to `/home/taniwha-deploy/taniwha/.env`:

| Variable | Required | Default | Description |
|---|---|---|---|
| `OTEL_SERVICE_NAME` | no | `taniwha` | Service name in traces |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | yes (prod) | `http://localhost:4318` | OTLP collector endpoint |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | no | `http_protobuf` | `http_protobuf` or `grpc` |
| `OTEL_EXPORTER_OTLP_HEADERS` | no | — | Auth headers (e.g. `signoz-ingestion-key=<key>` for SigNoz Cloud) |
| `OTEL_TRACES_SAMPLER` | no | `parentbased_always_on` | Set `always_off` to disable tracing entirely |

Leave `OTEL_EXPORTER_OTLP_ENDPOINT` empty to disable export (the app still starts normally).

### SigNoz Cloud example

```
OTEL_EXPORTER_OTLP_ENDPOINT=https://ingest.{region}.signoz.cloud:443
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
OTEL_EXPORTER_OTLP_HEADERS=signoz-ingestion-key=<your-key>
```

### Self-hosted SigNoz / Jaeger / Grafana Tempo

```
OTEL_EXPORTER_OTLP_ENDPOINT=http://<collector-host>:4318
```

### OpenTelemetry Collector sidecar pattern

Instead of pointing directly at the backend, you can run an OTel Collector on the same host and forward from there — useful for batching, filtering, or multi-backend fanout:

```
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318   # Collector HTTP receiver
```

The Collector forwards to your backend(s) per its own pipeline config.

---

## 4c. Data volume (credential store)

Taniwha stores encrypted user credentials at `TANIWHA_DATA_DIR/credentials.enc`
(default `/data/taniwha`). Mount a persistent host directory so credentials
survive container restarts and image upgrades.

### Create the host directory

```bash
sudo mkdir -p /srv/taniwha/data
sudo chown 1001:1001 /srv/taniwha/data   # uid/gid of the taniwha runtime user
```

### Add the volume mount to your `docker run` command

Edit `/home/taniwha-deploy/taniwha/taniwha.service` and add this flag to the
`ExecStart` line (alongside the existing `--volume` flags):

```
--volume /srv/taniwha/data:/data/taniwha \
```

### Add `TANIWHA_DATA_DIR` to `.env`

```
TANIWHA_DATA_DIR=/data/taniwha
```

### Reload systemd

```bash
sudo systemctl daemon-reload
sudo systemctl restart taniwha
```

### Key rotation warning

The credential file is encrypted with a key derived from `SECRET_KEY_BASE`.
**If `SECRET_KEY_BASE` is rotated**, the credential file becomes permanently
unreadable — there is no automatic migration. After rotating the key:

1. Delete `/srv/taniwha/data/credentials.enc`.
2. Restart the container — Taniwha starts with no users.
3. Navigate to the setup page to create the admin account again.

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
| `DEPLOY_HOST_KEY` | Output of `ssh-keyscan -H -p <port> <server>` (see below) |
| `DEPLOY_USER` | `taniwha-deploy` |
| `DEPLOY_HOST` | Server IP address or hostname |
| `DEPLOY_PORT` | SSH port (e.g. `7777`) |

Getting the host key (run on your local machine):

```bash
ssh-keyscan -H -p <port> <server>
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

---

## OpenTelemetry configuration

Taniwha ships with built-in OTel tracing, metrics, and structured logging. In production the OTLP exporter is active; in development the stdout exporter is used.

### Environment variables

Add these to your `.env` file:

```bash
# Required — URL of your OTLP collector (HTTP/protobuf endpoint)
OTEL_EXPORTER_OTLP_ENDPOINT=http://your-collector:4318

# Optional
OTEL_SERVICE_NAME=taniwha
OTEL_EXPORTER_OTLP_PROTOCOL=http_protobuf   # or grpc
OTEL_EXPORTER_OTLP_HEADERS=signoz-ingestion-key=<key>   # for SigNoz Cloud
OTEL_TRACES_SAMPLER=always_off              # to disable tracing
```

If `OTEL_EXPORTER_OTLP_ENDPOINT` is not set, Taniwha will warn at startup and default to `http://localhost:4318` (which will silently drop spans if no collector is running there).

### SigNoz Cloud example

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://ingest.us.signoz.cloud:443
OTEL_EXPORTER_OTLP_HEADERS=signoz-ingestion-key=<your-key>
OTEL_EXPORTER_OTLP_PROTOCOL=http_protobuf
```

### Verifying traces arrive

1. Start the app and make a request (e.g., `curl http://your-server:4000/health`).
2. In your backend UI (SigNoz → Traces, Jaeger UI, Grafana Explore), search for service `taniwha`.
3. You should see an HTTP span for `GET /health` with a child `taniwha.commands.system_pid` span.

For the full catalogue of custom spans and metrics see [`docs/observability.md`](observability.md).
