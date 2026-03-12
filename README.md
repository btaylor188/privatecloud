# Private Cloud

A modular, menu-driven Docker media server installer. Select only the services you need — the script handles credentials, networking, and deployment automatically.

---

## Requirements

- Linux host with `bash` and `sudo`
- Docker (installed automatically by the script via `docker.sh`)
- Git

---

## Quick Start

```bash
git clone https://github.com/btaylor188/privatecloud.git
cd privatecloud
chmod +x install.sh
./install.sh
```

---

## How It Works

1. **Service selection menu** — toggle individual services on/off, then type `go` to proceed
2. **Credential prompts** — only asks for what the selected services actually need
3. **Saved config** — paths and domain name are remembered in `~/.privatecloud` for future runs; press Enter to accept saved values or type to override
4. **Deployment** — writes `.env` files, installs Docker, creates networks, and starts containers
5. **Summary** — prints URLs and default credentials for every installed service

---

## Menu Controls

| Input | Action |
|-------|--------|
| `1`, `2 5 7` | Toggle service(s) on/off |
| `a` | Select all |
| `n` | Deselect all |
| `c` | Clear saved config (paths/domain) |
| `go` | Confirm and begin install |

---

## Services

### Infrastructure
| # | Service | Port | Notes |
|---|---------|------|-------|
| — | Cloudflared | — | **Always installed.** Cloudflare Tunnel; requires connection token |
| 1 | Portainer | 9000 | Docker management UI |
| 2 | WUD | 3000 | Container update notifications |
| 3 | Netdata | 19999 | System monitoring |
| 4 | DuckDNS | — | Dynamic DNS; requires token |
| 5 | Uptime Kuma | 3001 | Uptime monitoring |
| 6 | Speedtest | 8223 | Self-hosted network speed test |

### Downloaders
| # | Service | Port | Notes |
|---|---------|------|-------|
| 8 | NZBGet | 6789 | Usenet downloader. Default login: `nzbget` / `tegbzn6789` |
| 9 | qBittorrent+VPN | 8080 | Torrent client via Gluetun; **any WireGuard/OpenVPN provider** — see note below |

### *ARR!
| # | Service | Port | Notes |
|---|---------|------|-------|
| 10 | Prowlarr | 9696 | Indexer manager |
| 11 | Sonarr | 8989 | TV show automation |
| 12 | Radarr | 7878 | Movie automation |
| 13 | Tdarr | 8265 | Media transcoding |

### Media Server
| # | Service | Port | Notes |
|---|---------|------|-------|
| 14 | Plex | 32400 | Media server; claim token from plex.tv/claim |
| 15 | Seerr | 5055 | Media request manager (replaces deprecated Overseerr) |

### Private Cloud
| # | Service | Port | Notes |
|---|---------|------|-------|
| 16 | Nextcloud | 8087 | Self-hosted file storage; DB credentials required |
| 17 | oCIS | 9200 | ownCloud Infinite Scale; URL required |
| 18 | Immich | 2283 | Self-hosted photo & video backup; DB credentials required |
| 19 | Seafile | 8090 | Self-hosted file sync & share; DB and admin credentials required |
| 20 | Vaultwarden | 8222 | Bitwarden-compatible password manager |

### Backup
| # | Service | Notes |
|---|---------|-------|
| 20 | Backup | Backrest web UI (port 9898) + restic CLI + container hook scripts |

---

## Backup

Backups use **[Backrest](https://github.com/garethgeorge/backrest)** as the primary interface to **[restic](https://restic.net/)**. Backrest handles everything restic-related: repo configuration, scheduling, retention policies, snapshot browsing, and restores. The installer only generates lightweight hook scripts that Backrest calls before and after each backup to stop containers and dump databases.

### Architecture

```
Backrest (web UI) → pre hook → restic backup → post hook
                        ↓                           ↓
                 stop containers            restart containers
                 dump databases
```

### Backup groups

| Group | Containers |
|-------|-----------|
| Cloud | Immich, Seafile, Nextcloud, oCIS, Vaultwarden |
| ARR | Sonarr, Radarr, Prowlarr, NZBGet, qBittorrent, Tdarr, Uptime Kuma |
| Media | Plex, Seerr |

Schedules, retention policies, source paths, and repos are all configured in the Backrest web UI after install.

### Hook scripts

Installed to `${DOCKERPATH}/backup/` and mounted into the Backrest container at `/hooks/`:

| Script | Purpose |
|--------|---------|
| `${DOCKERPATH}/backup/pre-cloud.sh` | Dump DBs, stop Cloud containers |
| `${DOCKERPATH}/backup/post-cloud.sh` | Restart Cloud containers in dependency order |
| `${DOCKERPATH}/backup/pre-arr.sh` | Stop ARR containers |
| `${DOCKERPATH}/backup/post-arr.sh` | Restart ARR containers |
| `${DOCKERPATH}/backup/pre-media.sh` | Stop Media containers |
| `${DOCKERPATH}/backup/post-media.sh` | Restart Media containers |

DB dumps are written to `${DOCKERPATH}/cloud/backup/dumps/` — they are automatically included when Backrest snapshots `${DOCKERPATH}/cloud`.

`backup.conf` (mode 600) holds only the DB passwords needed by `pre-cloud.sh`.

### Backrest setup (post-install)

1. Open `http://server:9898`
2. Add a repo (B2, local path, or both) with your credentials and restic password
3. Create a plan for each group with the following source paths and schedule:
   - **Cloud plan:** `${DOCKERPATH}/cloud`
   - **ARR plan:** `${DOCKERPATH}/arr`
   - **Media plan:** `${DOCKERPATH}/media`
4. Add hook commands:
   - **Before backup:** `${DOCKERPATH}/backup/pre-<group>.sh`
   - **After backup:** `${DOCKERPATH}/backup/post-<group>.sh`

### Recovery

Use the Backrest UI to browse snapshots and trigger restores, or use the restic CLI directly:

```bash
export B2_ACCOUNT_ID="your-key-id"
export B2_ACCOUNT_KEY="your-app-key"
export RESTIC_PASSWORD="your-repo-password"

restic -r b2:mybucket:/cloud snapshots
restic -r b2:mybucket:/cloud restore latest --target /tmp/restore
restic -r b2:mybucket:/cloud restore latest --target /tmp/restore \
    --include /opt/docker/cloud/immich
```

Restore DB dumps:

```bash
docker exec -i immich_postgres psql -U immich < /tmp/restore/.../immich_db_TIMESTAMP.sql
docker exec -i seafile-db mysql -uroot -p < /tmp/restore/.../seafile_db_TIMESTAMP.sql
```

> Bulk storage paths (Immich upload, Seafile storage) are not included in snapshots — back those up separately via your NAS backup solution.

---

## Default Selections

All services start unchecked — select only what you need. Cloudflared is always installed and does not appear in the menu.

---

## Notes

### qBittorrent+VPN (Gluetun)
Uses [Gluetun](https://github.com/qdm12/gluetun) as a VPN sidecar — works with any WireGuard-compatible provider (Mullvad, ProtonVPN, NordVPN, etc.). Before starting:

1. Download a WireGuard `.conf` file from your VPN provider's dashboard
2. Place it at `${DOCKERPATH}/arr/gluetun/wireguard/wg0.conf`
3. Start the stack — qBittorrent routes all traffic through the tunnel with a killswitch

### Seerr
Unified successor to Overseerr and Jellyseerr (merged February 2026). Config is fully compatible — existing Overseerr data migrates automatically on first start.

### Immich
Self-hosted Google Photos alternative. Deploys four containers: `immich-server`, `immich-machine-learning`, `immich-postgres` (pgvecto-rs), and `immich-redis`. The photo library path is prompted during install and can be any local or mounted path.

### Seafile
Self-hosted Dropbox alternative. Deploys three containers: `seafile`, `seafile-db` (MariaDB), and `seafile-memcached`. The server hostname is used to generate download links — set it to your domain or server IP.

#### Post-install: HTTPS configuration
If Seafile is served over HTTPS (e.g. behind a Cloudflare Tunnel), two config files need to be updated after the first run. They live at `${DOCKERPATH}/cloud/seafile/data/seafile/conf/`.

**`seahub_settings.py`** — change `http` to `https` on the SERVICE_URL and FILE_SERVER_ROOT lines, and add the CSRF line if it isn't there:

```python
SERVICE_URL = 'https://subdomain.yourdomain.com'
FILE_SERVER_ROOT = 'https://subdomain.yourdomain.com/seafhttp'
CSRF_TRUSTED_ORIGINS = ['https://subdomain.yourdomain.com']
```

**`ccnet.conf`** — add or update `SERVICE_URL` in the `[General]` section:

```ini
[General]
SERVICE_URL = https://subdomain.yourdomain.com
```

After saving both files, restart the container:

```bash
docker restart seafile
```

### Saved Config
Paths and domain name are saved to `~/.privatecloud` after each run. Type `c` in the service menu to clear it and start fresh.

### Networks
Two Docker bridge networks are created automatically:

| Network | Subnet |
|---------|--------|
| `internal` | 172.19.0.0/24 |
| `external` | 172.20.0.0/24 |

---

## Project Structure

```
privatecloud/
├── install.sh               # Main installer
├── docker.sh                # Docker engine installer
└── docker-compose.yaml      # All services (profile-gated)
```
