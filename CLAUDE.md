# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

A modular, menu-driven Docker media server installer. Users run `install.sh`, select services from an interactive menu, and the script handles Docker installation, network setup, credential collection, config generation, and `docker-compose` deployment — all from a single shell script.

## Running the Installer

```bash
# Initial install or re-run to add/remove services
./install.sh

# Clear saved configuration and start fresh
# Type 'c' in the menu, or:
rm ~/.privatecloud
```

The installer saves state to `~/.privatecloud` between runs so users can press Enter to accept existing values.

## Common Docker Operations (after install)

```bash
# Check running containers
docker compose ps

# Logs for a specific service
docker compose logs -f sonarr

# Restart a service
docker compose restart radarr

# Bring down all containers
docker compose down

# Manually bring up specific profiles (profiles match service names)
docker compose --profile sonarr --profile radarr up -d
```

## Architecture

### install.sh (main entry point, ~1200 lines)

The script is structured sequentially:

1. **Menu loop** — 20 services in 5 categories (Infrastructure, Downloaders, ARR Stack, Media Server, Private Cloud). Toggles via numbers; `go` to proceed.
2. **Configuration prompts** — Asks for paths (DOCKERPATH, MEDIAPATH, PROCESSPATH, BOOKSPATH) and service-specific credentials. Persists answers to `~/.privatecloud`.
3. **Docker installation** — Calls `docker.sh`, detects Debian vs RHEL, installs Docker CE.
4. **Network creation** — Creates two custom bridge networks: `internal` (172.19.0.0/24) and `external` (172.20.0.0/24).
5. **Pre-configuration** — Generates initial config files (XML configs for Sonarr/Radarr/Prowlarr/Bookshelf, qBittorrent auth whitelist) before first container start.
6. **Environment file** — Writes `.env` in the repo directory with all variables for docker-compose. `.env` is git-ignored and cleaned up on exit.
7. **Docker deploy** — Runs `docker compose up -d` with `--profile` flags built by `profile_args()`.
8. **Summary** — Prints URLs and default credentials.

Key functions:
- `ask()` — Prompt with saved default; saves answer to `~/.privatecloud`
- `save_config()` — Persists paths and domain to `~/.privatecloud`; credentials are **not** saved and must be re-entered each run (exception: Cloudflare token is reused from the running container via `docker inspect`)
- `make_dir()` — Create directory and set ownership to PUID:PGID
- `is_selected()` — Check if a service number is in SELECTED array
- `profile_args()` — Build `--profile service1 --profile service2 ...` string

The values in the `SERVICES` array are the exact profile names used in `docker-compose.yaml`. The menu number (1–20) is the 1-based index into this array. Key non-obvious names: `qbittorrentvpn` (not `qbittorrent`), `backup` (not `backrest`), `uptime-kuma` (hyphenated), `grimmory` (2 containers: app + MariaDB sidecar).

### docker-compose.yaml (~675 lines)

Single file for all 20+ services. Every optional service has a `profiles:` tag matching its service name. Two services are always deployed (no profile): Portainer and Cloudflared.

Multi-container services:
- **Immich**: 4 containers (server, machine-learning, postgres/pgvecto-rs, redis)
- **Seafile**: 3 containers (app, mariadb, memcached)
- **qBittorrent+VPN**: 2 containers (gluetun VPN sidecar + qbittorrent using its network)

### backup/ directory

Pre/post hook scripts for Backrest (restic UI). Three groups: `cloudservices`, `mediaserver`, `infrastructure`. Pre-scripts stop containers and dump databases; post-scripts restart them. These are mounted into the Backrest container and configured in its UI.

### Data layout (created at install time, not in repo)

```
DOCKERPATH/
├── infrastructure/   # portainer, wud, netdata, duckdns, uptime-kuma, speedtest, backrest
├── mediaserver/      # sonarr, radarr, prowlarr, nzbget, qbittorrent, gluetun, tdarr, plex, seerr, audiobookshelf
└── cloudservices/    # immich/, seafile/, vaultwarden/, backrest/
```

## Service Categories and Ports

| Category | Service | Port |
|---|---|---|
| Infrastructure | Portainer | 9000 |
| Infrastructure | WUD | 3000 |
| Infrastructure | Netdata | 19999 |
| Infrastructure | Uptime Kuma | 3001 |
| Infrastructure | Speedtest | 8223 |
| Infrastructure | Backrest | 9898 |
| Downloaders | NZBGet | 6789 |
| Downloaders | qBittorrent | 8080 |
| ARR Stack | Prowlarr | 9696 |
| ARR Stack | Sonarr | 8989 |
| ARR Stack | Radarr | 7878 |
| ARR Stack | Tdarr | 8265 |
| Media Server | Plex | 32400 |
| Media Server | Seerr | 5055 |
| Books | Audiobookshelf | 13378 |
| Books | Grimmory | 6069 |
| Books | Shelfmark | 8084 |
| Private Cloud | Immich | 2283 |
| Private Cloud | Seafile | 8090 |
| Private Cloud | Vaultwarden | 8222 |

## Key Environment Variables

The `.env` file (generated, not committed) supplies all values to docker-compose:

- `DOCKERPATH`, `MEDIAPATH`, `PROCESSPATH`, `BOOKSPATH` — data directories
- `PUID`, `PGID` — user/group IDs (auto-detected)
- `TZ`, `DOMAINNAME` — timezone and domain
- `CF_TUNNEL_TOKEN` — Cloudflare Tunnel (required; always deployed)
- `PLEXCLAIM` — Plex claim token from plex.tv/claim
- `DUCKDNSTOKEN` — DuckDNS API token
- `QBIT_SUBNET` — Local subnet CIDR for qBittorrent auth bypass (auto-detected)
- `GLUETUN_VPN_TYPE`, `OPENVPN_USER`, `OPENVPN_PASSWORD` — VPN config for qBittorrent
- `IMMICH_UPLOAD_LOCATION`, `IMMICH_DB_PASSWORD` — Immich photo library path and DB credentials
- `VAULTWARDEN_DOMAIN` — public URL for Vaultwarden (e.g. `https://vault.yourdomain.com`)
- `SEAFILE_HOSTNAME`, `SEAFILE_STORAGE_PATH`, `SEAFILE_DB_ROOT_PASSWORD`, `SEAFILE_ADMIN_EMAIL`, `SEAFILE_ADMIN_PASSWORD` — Seafile config

## Making Changes

- **Adding a new service**: Add a menu entry to `SERVICES`/`LABELS` arrays in `install.sh`, add pre-configuration block if needed, add service to `docker-compose.yaml` with matching `profiles:` tag, add URL to the summary section.
- **install.sh uses `set -eu`** — all commands must succeed and variables must be set.
- **Idempotency matters** — the installer is re-run to modify deployments; don't assume a fresh system.
- **`.env` is ephemeral** — generated fresh each run and deleted on exit via `trap`.
