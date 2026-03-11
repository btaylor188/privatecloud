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
git clone https://github.com/btaylor188/MediaServer3.git
cd MediaServer3
chmod +x install.sh
./install.sh
```

---

## How It Works

1. **Service selection menu** — toggle individual services on/off, then type `go` to proceed
2. **Credential prompts** — only asks for what the selected services actually need
3. **Saved config** — paths and domain name are remembered in `~/.mediaserver3` for future runs; press Enter to accept saved values or type to override
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
| 1 | Portainer | 9000 | Docker management UI |
| 2 | WUD | 3000 | Container update notifications |
| 3 | Netdata | 19999 | System monitoring |
| 4 | DuckDNS | — | Dynamic DNS; requires token |
| 5 | Uptime Kuma | 3001 | Uptime monitoring |
| 6 | Cloudflared | — | Cloudflare Tunnel; requires connection token |
| 7 | Speedtest | 8223 | Self-hosted network speed test |

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

---

## Default Selections

On/off by default:

| On | Off |
|----|-----|
| Portainer, WUD, Cloudflared | Netdata, DuckDNS, Uptime Kuma, Speedtest |
| NZBGet, Prowlarr, Sonarr, Radarr | qBittorrent+VPN |
| Plex | Tdarr, Seerr, Nextcloud, oCIS |

---

## Notes

### qBittorrent+VPN (Gluetun)
Uses [Gluetun](https://github.com/qdm12/gluetun) as a VPN sidecar — works with any WireGuard-compatible provider (Mullvad, ProtonVPN, NordVPN, etc.). Before starting:

1. Download a WireGuard `.conf` file from your VPN provider's dashboard
2. Place it at `${DOCKERPATH}/gluetun/wireguard/wg0.conf`
3. Start the stack — qBittorrent routes all traffic through the tunnel with a killswitch

### Seerr
Unified successor to Overseerr and Jellyseerr (merged February 2026). Config is fully compatible — existing Overseerr data migrates automatically on first start.

### Immich
Self-hosted Google Photos alternative. Deploys four containers: `immich-server`, `immich-machine-learning`, `immich-postgres` (pgvecto-rs), and `immich-redis`. The photo library path is prompted during install and can be any local or mounted path.

### Seafile
Self-hosted Dropbox alternative. Deploys three containers: `seafile`, `seafile-db` (MariaDB), and `seafile-memcached`. The server hostname is used to generate download links — set it to your domain or server IP.

### Saved Config
Paths and domain name are saved to `~/.mediaserver3` after each run. Type `c` in the service menu to clear it and start fresh.

### Networks
Two Docker bridge networks are created automatically:

| Network | Subnet |
|---------|--------|
| `internal` | 172.19.0.0/24 |
| `external` | 172.20.0.0/24 |

---

## Project Structure

```
mediaserver3/
├── install.sh               # Main installer
├── docker.sh                # Docker engine installer
└── docker-compose.yaml      # All services (profile-gated)
```
