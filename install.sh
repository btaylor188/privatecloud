#!/bin/bash

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─────────────────────────────────────────────
#  Saved config (paths and domain name)
# ─────────────────────────────────────────────
CONFIG_FILE="${HOME}/.privatecloud"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Prompt with a saved/default value — press Enter to accept, or type to override
ask() {
    local prompt="$1" varname="$2" fallback="${3:-}" current="${!2:-}"
    local effective="${current:-$fallback}"
    if [[ -n "$effective" ]]; then
        read -r -p "$prompt [$effective]: " input
        if [[ -n "$input" ]]; then
            printf -v "$varname" '%s' "$input"
        else
            printf -v "$varname" '%s' "$effective"
        fi
    else
        read -r -p "$prompt: " "$varname"
    fi
}

make_dir() {
    sudo mkdir -p "$1"
    sudo chown "${PUID}:${PGID}" "$(dirname "$1")" "$1"
}

save_config() {
    cat > "$CONFIG_FILE" <<EOF
DOCKERPATH="${DOCKERPATH}"
TZ="${TZ}"
DOMAINNAME="${DOMAINNAME:-}"
PROCESSPATH="${PROCESSPATH:-}"
MEDIAPATH="${MEDIAPATH:-}"
GLUETUN_VPN_TYPE="${GLUETUN_VPN_TYPE:-wireguard}"
BACKUPPATH="${BACKUPPATH:-}"
BOOKSPATH="${BOOKSPATH:-}"
EOF
}

# Remove .env on exit (success or failure)
cleanup() {
    rm -f "$SCRIPT_DIR/.env"
}
trap cleanup EXIT

# ─────────────────────────────────────────────
#  Service selection menu
# ─────────────────────────────────────────────
SERVICES=(wud netdata duckdns uptime-kuma speedtest nzbget qbittorrentvpn prowlarr sonarr radarr tdarr listenarr plex seerr lazylibrarian calibre-server calibre-web bookshelf audiobookshelf nextcloud ocis immich seafile vaultwarden backup)

LABELS=(
    "WUD               Container update notifications"
    "Netdata           System monitoring"
    "DuckDNS           Dynamic DNS"
    "Uptime Kuma       Uptime monitoring"
    "Speedtest         Network speed test"
    "NZBGet            Usenet downloader"
    "qBittorrent+VPN   Torrent client"
    "Prowlarr          Indexer manager"
    "Sonarr            TV show automation"
    "Radarr            Movie automation"
    "Tdarr             Media transcoding"
    "Listenarr         Audiobook automation"
    "Plex              Media server"
    "Seerr             Media requests"
    "LazyLibrarian     Book & audiobook automation"
    "Calibre-Server    Calibre desktop + content server"
    "Calibre-Web       Ebook library & reader"
    "Bookshelf         Ebook automation (Readarr fork)"
    "Audiobookshelf    Audiobook & podcast server"
    "Nextcloud         File storage"
    "oCIS              ownCloud Infinite Scale"
    "Immich            Photo & video backup"
    "Seafile           File sync & share"
    "Vaultwarden       Password manager"
    "Backup            Backrest UI + restic + container hooks (port 9898)"
)

SVC_GROUPS=(
    "Infrastructure" "Infrastructure" "Infrastructure" "Infrastructure" "Infrastructure"
    "Downloaders" "Downloaders"
    "*ARR!" "*ARR!" "*ARR!" "*ARR!" "*ARR!"
    "Media Server" "Media Server" "Media Server" "Media Server" "Media Server" "Media Server" "Media Server"
    "Private Cloud" "Private Cloud" "Private Cloud" "Private Cloud" "Private Cloud"
    "Backup"
)

# Default: none selected — Cloudflared and Portainer are always required and not listed here
SELECTED=(0 0 0 0 0  0 0  0 0 0 0 0  0 0 0 0 0 0 0  0 0 0 0 0  0)

show_menu() {
    echo ""
    echo "┌──────────────────────────────────────────────────────────────┐"
    echo "│             Private Cloud — Select Services                  │"
    echo "├──────────────────────────────────────────────────────────────┤"
    local last_group=""
    for i in "${!SERVICES[@]}"; do
        local group="${SVC_GROUPS[$i]}"
        if [[ "$group" != "$last_group" ]]; then
            printf "│                                                              │\n"
            printf "│  ── %-55s  │\n" "$group"
            last_group="$group"
        fi
        local mark="[ ]"
        [[ "${SELECTED[$i]}" == "1" ]] && mark="[x]"
        printf "│  %2d) %s  %-50s │\n" "$((i+1))" "$mark" "${LABELS[$i]}"
    done
    echo "│                                                              │"
    echo "└──────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  Enter number(s) to toggle (e.g. '3' or '1 4 7')"
    echo "  'a' = select all  |  'n' = deselect all  |  'c' = clear saved config  |  'go' = confirm"
}

while true; do
    show_menu
    read -rp "  > " input
    case "$input" in
        go) break ;;
        a) SELECTED=(); for _ in "${SERVICES[@]}"; do SELECTED+=(1); done ;;
        n) SELECTED=(); for _ in "${SERVICES[@]}"; do SELECTED+=(0); done ;;
        c) rm -f "$CONFIG_FILE" && echo "  Saved config cleared." ;;
        *)
            for num in $input; do
                if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#SERVICES[@]} )); then
                    idx=$((num - 1))
                    [[ "${SELECTED[$idx]}" == "1" ]] && SELECTED[$idx]=0 || SELECTED[$idx]=1
                else
                    echo "  Invalid selection: $num (valid range: 1-${#SERVICES[@]})"
                fi
            done
            ;;
    esac
done

# Returns 0 (true) if the named service is selected
is_selected() {
    for i in "${!SERVICES[@]}"; do
        if [[ "${SERVICES[$i]}" == "$1" && "${SELECTED[$i]}" == "1" ]]; then
            return 0
        fi
    done
    return 1
}

# Builds --profile args for given service names
profile_args() {
    local args=""
    for svc in "$@"; do
        is_selected "$svc" && args="$args --profile $svc"
    done
    echo "$args"
}

# ─────────────────────────────────────────────
#  Collect credentials (only what's needed)
# ─────────────────────────────────────────────
PUID=$(id -u)
PGID=$(id -g)

echo ""
echo "── Required Settings ──"

ask "Path for Docker data" DOCKERPATH "/opt/docker"
make_dir "$DOCKERPATH"

ask "Timezone" TZ "America/Denver"

if is_selected duckdns || is_selected speedtest; then
    ask "Domain name" DOMAINNAME
fi

if is_selected nzbget || is_selected sonarr || is_selected radarr || is_selected tdarr || is_selected listenarr || is_selected qbittorrentvpn || is_selected lazylibrarian || is_selected bookshelf; then
    ask "Path for temp processing" PROCESSPATH "/opt/processing"
    make_dir "$PROCESSPATH"
fi

if is_selected nzbget || is_selected sonarr || is_selected radarr || is_selected tdarr || is_selected listenarr || is_selected plex || is_selected qbittorrentvpn || is_selected lazylibrarian || is_selected bookshelf; then
    ask "Path for media" MEDIAPATH "/mnt/media"
    make_dir "$MEDIAPATH"
fi

if is_selected lazylibrarian || is_selected calibre-server || is_selected calibre-web || is_selected bookshelf || is_selected audiobookshelf; then
    ask "Path for books & audiobooks" BOOKSPATH "${MEDIAPATH:-/mnt/media}/books"
    make_dir "$BOOKSPATH"
fi

save_config

if is_selected plex; then
    echo "Plex claim token (from plex.tv/claim):"
    read -r PLEXCLAIM
fi


if is_selected duckdns; then
    echo "DuckDNS token:"
    read -rs DUCKDNSTOKEN
    echo
fi

if is_selected qbittorrentvpn; then
    _detected_subnet=$(ip route | awk '/proto kernel/ && /src/ {split($1,a,"."); printf "%s.%s.%s.0/%s\n", a[1],a[2],a[3], substr($1,index($1,"/")+1)}' | head -1)
    ask "Local subnet for qBittorrent auth bypass (CIDR)" QBIT_SUBNET "${_detected_subnet}"
    ask "VPN type for qBittorrent+VPN (wireguard/openvpn)" GLUETUN_VPN_TYPE "wireguard"
    if [[ "$GLUETUN_VPN_TYPE" == "wireguard" ]]; then
        make_dir "${DOCKERPATH}/mediaserver/gluetun/wireguard"
    else
        make_dir "${DOCKERPATH}/mediaserver/gluetun"
        echo "OpenVPN username:"
        read -r OPENVPN_USER
        echo "OpenVPN password:"
        read -rs OPENVPN_PASSWORD
        echo
        echo "Paste your OpenVPN config file contents, then press Ctrl+D on a new line (config must use an IP address, not a hostname):"
        _ovpn_content=$(cat)
        if [[ -z "$_ovpn_content" ]]; then
            echo "Warning: OpenVPN config is empty. You must place a valid config at ${DOCKERPATH}/mediaserver/gluetun/custom.conf before starting gluetun."
        else
            printf '%s\n' "$_ovpn_content" > "${DOCKERPATH}/mediaserver/gluetun/custom.conf"
            echo "Config written to ${DOCKERPATH}/mediaserver/gluetun/custom.conf"
        fi
    fi
fi

# Cloudflared is always required — reuse token from running container if present
CF_TUNNEL_TOKEN=$(sudo docker inspect cloudflared --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
    | grep '^TUNNEL_TOKEN=' | cut -d= -f2- || true)
if [[ -z "$CF_TUNNEL_TOKEN" ]]; then
    echo "Cloudflare Tunnel connection token:"
    read -rs CF_TUNNEL_TOKEN
    echo
fi

if is_selected nextcloud; then
    echo "Nextcloud DB root password:"
    read -rs NCDBROOT
    echo
    echo "Nextcloud DB user password:"
    read -rs NCDBUSER
    echo
fi

if is_selected ocis; then
    echo "oCIS URL (e.g. https://files.yourdomain.com or https://localhost:9200):"
    read -r OCIS_URL
    make_dir "${DOCKERPATH}/cloudservices/ocis/config"
    make_dir "${DOCKERPATH}/cloudservices/ocis/data"
fi

if is_selected immich; then
    ask "Path for Immich photo library" IMMICH_UPLOAD_LOCATION "${DOCKERPATH}/cloudservices/immich/upload"
    make_dir "${IMMICH_UPLOAD_LOCATION}"
    make_dir "${DOCKERPATH}/cloudservices/immich/postgres"
    make_dir "${DOCKERPATH}/cloudservices/immich/model-cache"
    echo "Immich DB password:"
    read -rs IMMICH_DB_PASSWORD
    echo
fi

if is_selected seafile; then
    echo "Seafile server hostname (e.g. files.yourdomain.com or your server IP):"
    read -r SEAFILE_HOSTNAME
    ask "Path for Seafile bulk storage" SEAFILE_STORAGE_PATH "${DOCKERPATH}/cloudservices/seafile/storage"
    make_dir "${DOCKERPATH}/cloudservices/seafile/data"
    make_dir "${DOCKERPATH}/cloudservices/seafile/db"
    make_dir "${SEAFILE_STORAGE_PATH}"
    echo "Seafile DB root password:"
    read -rs SEAFILE_DB_ROOT_PASSWORD
    echo
    echo "Seafile admin email:"
    read -r SEAFILE_ADMIN_EMAIL
    echo "Seafile admin password:"
    read -rs SEAFILE_ADMIN_PASSWORD
    echo
fi

if is_selected backup; then
    echo ""
    echo "── Backup Settings ──"
    echo "  Hook scripts will be installed to ${DOCKERPATH}/backup/"
    echo "  Configure repos, schedules, retention, and paths in Backrest after install."
    save_config
fi

# ─────────────────────────────────────────────
#  Write .env file
# ─────────────────────────────────────────────
cat > "$SCRIPT_DIR/.env" <<EOF
DOMAINNAME=${DOMAINNAME:-}
DOCKERPATH=${DOCKERPATH}
PROCESSPATH=${PROCESSPATH:-/opt/processing}
MEDIAPATH=${MEDIAPATH:-/mnt/media}
PLEXCLAIM=${PLEXCLAIM:-}
QBIT_SUBNET=${QBIT_SUBNET:-}
DUCKDNSTOKEN=${DUCKDNSTOKEN:-}
CF_TUNNEL_TOKEN=${CF_TUNNEL_TOKEN:-}
GLUETUN_VPN_TYPE=${GLUETUN_VPN_TYPE:-wireguard}
OPENVPN_USER=${OPENVPN_USER:-}
OPENVPN_PASSWORD=${OPENVPN_PASSWORD:-}
OCIS_URL=${OCIS_URL:-}
NCDBROOT=${NCDBROOT:-}
NCDBUSER=${NCDBUSER:-}
IMMICH_UPLOAD_LOCATION=${IMMICH_UPLOAD_LOCATION:-/opt/docker/cloudservices/immich/upload}
IMMICH_DB_PASSWORD=${IMMICH_DB_PASSWORD:-}
SEAFILE_HOSTNAME=${SEAFILE_HOSTNAME:-}
SEAFILE_STORAGE_PATH=${SEAFILE_STORAGE_PATH:-${DOCKERPATH}/cloudservices/seafile/storage}
SEAFILE_DB_ROOT_PASSWORD=${SEAFILE_DB_ROOT_PASSWORD:-}
SEAFILE_ADMIN_EMAIL=${SEAFILE_ADMIN_EMAIL:-}
SEAFILE_ADMIN_PASSWORD=${SEAFILE_ADMIN_PASSWORD:-}
BOOKSPATH=${BOOKSPATH:-${MEDIAPATH:-/mnt/media}/books}
TZ=${TZ}
PUID=${PUID}
PGID=${PGID}
EOF

# ─────────────────────────────────────────────
#  Install Docker
# ─────────────────────────────────────────────
bash "$SCRIPT_DIR/docker.sh"

# ─────────────────────────────────────────────
#  Create Docker networks (idempotent)
# ─────────────────────────────────────────────
sudo docker network inspect internal >/dev/null 2>&1 || \
    sudo docker network create -d bridge --subnet=172.19.0.0/24 internal
sudo docker network inspect external >/dev/null 2>&1 || \
    sudo docker network create -d bridge --subnet=172.20.0.0/24 external

# ─────────────────────────────────────────────
#  Pre-configure services
# ─────────────────────────────────────────────
if is_selected sonarr && [[ ! -f "${DOCKERPATH}/mediaserver/sonarr/config.xml" ]]; then
    make_dir "${DOCKERPATH}/mediaserver/sonarr"
    SONARR_API_KEY=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 32)
    sudo tee "${DOCKERPATH}/mediaserver/sonarr/config.xml" > /dev/null <<EOF
<Config>
  <BindAddress>*</BindAddress>
  <Port>8989</Port>
  <SslPort>9898</SslPort>
  <EnableSsl>False</EnableSsl>
  <LaunchBrowser>True</LaunchBrowser>
  <ApiKey>${SONARR_API_KEY}</ApiKey>
  <AuthenticationMethod>External</AuthenticationMethod>
  <Branch>main</Branch>
  <LogLevel>info</LogLevel>
  <UrlBase></UrlBase>
  <UpdateMechanism>Docker</UpdateMechanism>
  <AnalyticsEnabled>True</AnalyticsEnabled>
  <InstanceName>Sonarr</InstanceName>
</Config>
EOF
    sudo chown "${PUID}:${PGID}" "${DOCKERPATH}/mediaserver/sonarr/config.xml"
fi

if is_selected radarr && [[ ! -f "${DOCKERPATH}/mediaserver/radarr/config.xml" ]]; then
    make_dir "${DOCKERPATH}/mediaserver/radarr"
    RADARR_API_KEY=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 32)
    sudo tee "${DOCKERPATH}/mediaserver/radarr/config.xml" > /dev/null <<EOF
<Config>
  <BindAddress>*</BindAddress>
  <Port>7878</Port>
  <SslPort>7879</SslPort>
  <EnableSsl>False</EnableSsl>
  <LaunchBrowser>True</LaunchBrowser>
  <ApiKey>${RADARR_API_KEY}</ApiKey>
  <AuthenticationMethod>External</AuthenticationMethod>
  <Branch>master</Branch>
  <LogLevel>info</LogLevel>
  <UrlBase></UrlBase>
  <UpdateMechanism>Docker</UpdateMechanism>
  <AnalyticsEnabled>True</AnalyticsEnabled>
  <InstanceName>Radarr</InstanceName>
</Config>
EOF
    sudo chown "${PUID}:${PGID}" "${DOCKERPATH}/mediaserver/radarr/config.xml"
fi

if is_selected bookshelf && [[ ! -f "${DOCKERPATH}/mediaserver/bookshelf/config.xml" ]]; then
    make_dir "${DOCKERPATH}/mediaserver/bookshelf"
    BOOKSHELF_API_KEY=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 32)
    sudo tee "${DOCKERPATH}/mediaserver/bookshelf/config.xml" > /dev/null <<EOF
<Config>
  <BindAddress>*</BindAddress>
  <Port>8787</Port>
  <SslPort>8788</SslPort>
  <EnableSsl>False</EnableSsl>
  <LaunchBrowser>True</LaunchBrowser>
  <ApiKey>${BOOKSHELF_API_KEY}</ApiKey>
  <AuthenticationMethod>External</AuthenticationMethod>
  <AuthenticationRequired>Disabled</AuthenticationRequired>
  <Branch>develop</Branch>
  <LogLevel>info</LogLevel>
  <UrlBase></UrlBase>
  <UpdateMechanism>Docker</UpdateMechanism>
  <AnalyticsEnabled>True</AnalyticsEnabled>
  <InstanceName>Bookshelf</InstanceName>
</Config>
EOF
    sudo chown "${PUID}:${PGID}" "${DOCKERPATH}/mediaserver/bookshelf/config.xml"
fi

if is_selected prowlarr && [[ ! -f "${DOCKERPATH}/mediaserver/prowlarr/config.xml" ]]; then
    make_dir "${DOCKERPATH}/mediaserver/prowlarr"
    PROWLARR_API_KEY=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 32)
    sudo tee "${DOCKERPATH}/mediaserver/prowlarr/config.xml" > /dev/null <<EOF
<Config>
  <BindAddress>*</BindAddress>
  <Port>9696</Port>
  <SslPort>6969</SslPort>
  <EnableSsl>False</EnableSsl>
  <LaunchBrowser>True</LaunchBrowser>
  <ApiKey>${PROWLARR_API_KEY}</ApiKey>
  <AuthenticationMethod>External</AuthenticationMethod>
  <Branch>master</Branch>
  <LogLevel>info</LogLevel>
  <UrlBase></UrlBase>
  <UpdateMechanism>Docker</UpdateMechanism>
  <AnalyticsEnabled>True</AnalyticsEnabled>
  <InstanceName>Prowlarr</InstanceName>
</Config>
EOF
    sudo chown "${PUID}:${PGID}" "${DOCKERPATH}/mediaserver/prowlarr/config.xml"
fi

if is_selected lazylibrarian; then
    make_dir "${DOCKERPATH}/mediaserver/lazylibrarian"
fi

if is_selected qbittorrentvpn && [[ ! -f "${DOCKERPATH}/mediaserver/qbittorrent/qBittorrent/qBittorrent.conf" ]]; then
    make_dir "${DOCKERPATH}/mediaserver/qbittorrent/qBittorrent"
    sudo tee "${DOCKERPATH}/mediaserver/qbittorrent/qBittorrent/qBittorrent.conf" > /dev/null <<EOF
[BitTorrent]
Session\DefaultSavePath=/downloads

[Preferences]
WebUI\AuthSubnetWhitelist=${QBIT_SUBNET}
WebUI\AuthSubnetWhitelistEnabled=true
EOF
    sudo chown -R "${PUID}:${PGID}" "${DOCKERPATH}/mediaserver/qbittorrent"
fi

# ─────────────────────────────────────────────
#  Write per-service compose files
# ─────────────────────────────────────────────
if is_selected wud; then
    make_dir "${DOCKERPATH}/infrastructure/wud"
    cat > "${DOCKERPATH}/infrastructure/wud/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  wud:
    container_name: wud
    image: getwud/wud
    ports:
      - 3000:3000
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ${DOCKERPATH}/infrastructure/wud:/store
    networks:
      - internal
    restart: unless-stopped
    environment:
      - WUD_WATCHER_LOCAL_CRON=0 0 * * *
EOF
fi

if is_selected netdata; then
    make_dir "${DOCKERPATH}/infrastructure/netdata"
    cat > "${DOCKERPATH}/infrastructure/netdata/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  netdata:
    container_name: netdata
    image: netdata/netdata
    ports:
      - 19999:19999
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - internal
    restart: always
EOF
fi

if is_selected duckdns; then
    make_dir "${DOCKERPATH}/infrastructure/duckdns"
    cat > "${DOCKERPATH}/infrastructure/duckdns/docker-compose.yaml" <<EOF
networks:
  external:
    external: true

services:
  duckdns:
    image: lscr.io/linuxserver/duckdns:latest
    container_name: duckdns
    networks:
      - external
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
      - SUBDOMAINS=${DOMAINNAME}
      - TOKEN=${DUCKDNSTOKEN}
      - LOG_FILE=false
    volumes:
      - ${DOCKERPATH}/infrastructure/duckdns:/config
    restart: unless-stopped
EOF
fi

if is_selected uptime-kuma; then
    make_dir "${DOCKERPATH}/mediaserver/uptime-kuma"
    cat > "${DOCKERPATH}/mediaserver/uptime-kuma/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  uptime-kuma:
    container_name: uptime-kuma
    image: louislam/uptime-kuma:1
    restart: always
    ports:
      - 3001:3001
    networks:
      - internal
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ${DOCKERPATH}/mediaserver/uptime-kuma:/app/data
EOF
fi

if is_selected speedtest; then
    make_dir "${DOCKERPATH}/infrastructure/speedtest"
    cat > "${DOCKERPATH}/infrastructure/speedtest/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  speedtest:
    container_name: speedtest
    image: adolfintel/speedtest
    ports:
      - 8223:8223
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TITLE=${DOMAINNAME}
      - WEBPORT=8223
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - internal
    restart: always
EOF
fi

if is_selected nzbget; then
    make_dir "${DOCKERPATH}/mediaserver/nzbget"
    cat > "${DOCKERPATH}/mediaserver/nzbget/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  nzbget:
    container_name: nzbget
    image: linuxserver/nzbget:latest
    ports:
      - 6789:6789
    environment:
      - LC_ALL=C
      - PUID=${PUID}
      - PGID=${PGID}
      - HOME=/root
      - TERM=xterm
    volumes:
      - /etc/localtime:/etc/localtime
      - ${DOCKERPATH}/mediaserver/nzbget:/config
      - ${PROCESSPATH}:/mnt/processing
      - ${MEDIAPATH}:/mnt/Media
      - /tmp:/tmp
    networks:
      - internal
    restart: always
EOF
fi

if is_selected qbittorrentvpn; then
    make_dir "${DOCKERPATH}/mediaserver/qbittorrent"
    cat > "${DOCKERPATH}/mediaserver/qbittorrent/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  gluetun:
    container_name: gluetun
    image: qmcgaw/gluetun
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - 8080:8080
    volumes:
      - ${DOCKERPATH}/mediaserver/gluetun:/gluetun
    environment:
      - VPN_SERVICE_PROVIDER=custom
      - VPN_TYPE=${GLUETUN_VPN_TYPE}
      - OPENVPN_CUSTOM_CONFIG=/gluetun/custom.conf
      - OPENVPN_USER=${OPENVPN_USER:-}
      - OPENVPN_PASSWORD=${OPENVPN_PASSWORD:-}
      - FIREWALL_INPUT_PORTS=8080
    networks:
      - internal
    restart: unless-stopped

  qbittorrent:
    container_name: qbittorrent
    image: lscr.io/linuxserver/qbittorrent:latest
    network_mode: service:gluetun
    depends_on:
      gluetun:
        condition: service_healthy
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
      - WEBUI_PORT=8080
    volumes:
      - ${DOCKERPATH}/mediaserver/qbittorrent:/config
      - ${MEDIAPATH}:/mnt/Media
      - ${PROCESSPATH}:/mnt/processing
    restart: unless-stopped
EOF
fi

if is_selected prowlarr; then
    make_dir "${DOCKERPATH}/mediaserver/prowlarr"
    cat > "${DOCKERPATH}/mediaserver/prowlarr/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    container_name: prowlarr
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${DOCKERPATH}/mediaserver/prowlarr:/config
    ports:
      - 9696:9696
    networks:
      - internal
    restart: always
EOF
fi

if is_selected sonarr; then
    make_dir "${DOCKERPATH}/mediaserver/sonarr"
    cat > "${DOCKERPATH}/mediaserver/sonarr/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  sonarr:
    container_name: sonarr
    image: linuxserver/sonarr:latest
    ports:
      - 8989:8989
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - HOME=/root
      - TERM=xterm
      - XDG_CONFIG_HOME=/config/xdg
      - LANGUAGE=en_US.UTF-8
      - LANG=en_US.UTF-8
    volumes:
      - /etc/localtime:/etc/localtime
      - ${DOCKERPATH}/mediaserver/sonarr:/config
      - ${MEDIAPATH}:/mnt/Media
      - ${PROCESSPATH}:/mnt/processing
    networks:
      - internal
    restart: always
EOF
fi

if is_selected radarr; then
    make_dir "${DOCKERPATH}/mediaserver/radarr"
    cat > "${DOCKERPATH}/mediaserver/radarr/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  radarr:
    container_name: radarr
    image: linuxserver/radarr:latest
    ports:
      - 7878:7878
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - HOME=/root
      - TERM=xterm
      - XDG_CONFIG_HOME=/config/xdg
      - LANGUAGE=en_US.UTF-8
      - LANG=en_US.UTF-8
    volumes:
      - /etc/localtime:/etc/localtime
      - ${DOCKERPATH}/mediaserver/radarr:/config
      - ${MEDIAPATH}:/mnt/Media
      - ${PROCESSPATH}:/mnt/processing
    networks:
      - internal
    restart: always
EOF
fi

if is_selected tdarr; then
    make_dir "${DOCKERPATH}/mediaserver/tdarr"
    cat > "${DOCKERPATH}/mediaserver/tdarr/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  tdarr:
    container_name: tdarr_server
    image: haveagitgat/tdarr
    volumes:
      - ${DOCKERPATH}/mediaserver/tdarr/server:/app/server
      - ${DOCKERPATH}/mediaserver/tdarr/configs:/app/configs
      - ${DOCKERPATH}/mediaserver/tdarr/logs:/app/logs
      - ${MEDIAPATH}:/media
      - ${PROCESSPATH}:/temp
    environment:
      - serverIP=0.0.0.0
      - serverPort=8266
      - webUIPort=8265
      - TZ=${TZ}
      - PUID=${PUID}
      - PGID=${PGID}
    ports:
      - 8265:8265
      - 8266:8266
    networks:
      - internal
    restart: always

  tdarr_node:
    container_name: tdarr_node
    image: haveagitgat/tdarr_node
    volumes:
      - ${DOCKERPATH}/mediaserver/tdarr/configs:/app/configs
      - ${DOCKERPATH}/mediaserver/tdarr/logs:/app/logs
      - ${MEDIAPATH}:/media
      - ${PROCESSPATH}:/temp
    network_mode: service:tdarr
    environment:
      - nodeID=Node01
      - serverIP=0.0.0.0
      - serverPort=8266
      - TZ=${TZ}
      - PUID=${PUID}
      - PGID=${PGID}
    devices:
      - /dev/dri:/dev/dri
    restart: always
EOF
fi

if is_selected listenarr; then
    make_dir "${DOCKERPATH}/mediaserver/listenarr"
    cat > "${DOCKERPATH}/mediaserver/listenarr/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  listenarr:
    container_name: listenarr
    image: ghcr.io/listenarrs/listenarr:latest
    ports:
      - 4545:4545
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - UMASK=022
      - TZ=${TZ}
    volumes:
      - ${DOCKERPATH}/mediaserver/listenarr:/app/config
      - ${MEDIAPATH}:/mnt/Media
      - ${PROCESSPATH}:/mnt/processing
    networks:
      - internal
    restart: unless-stopped
EOF
fi

if is_selected plex; then
    make_dir "${DOCKERPATH}/mediaserver/plex"
    cat > "${DOCKERPATH}/mediaserver/plex/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true
  external:
    external: true

services:
  pms-docker:
    container_name: plex
    image: plexinc/pms-docker
    devices:
      - /dev/dri:/dev/dri
    ports:
      - 32400:32400/tcp
      - 3005:3005/tcp
      - 8324:8324/tcp
      - 32469:32469/tcp
      - 1900:1900/udp
      - 32410:32410/udp
      - 32412:32412/udp
      - 32413:32413/udp
      - 32414:32414/udp
    environment:
      - TZ=${TZ}
      - PLEX_CLAIM=${PLEXCLAIM}
    networks:
      - internal
      - external
    volumes:
      - ${DOCKERPATH}/mediaserver/plex/database:/config
      - /dev/shm:/transcode
      - ${MEDIAPATH}:/mnt/Media
    restart: always
EOF
fi

if is_selected seerr; then
    make_dir "${DOCKERPATH}/mediaserver/seerr"
    cat > "${DOCKERPATH}/mediaserver/seerr/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  seerr:
    container_name: seerr
    image: ghcr.io/seerr-team/seerr:latest
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    ports:
      - 5055:5055
    volumes:
      - ${DOCKERPATH}/mediaserver/seerr/config:/app/config
    networks:
      - internal
    restart: unless-stopped
EOF
fi

if is_selected lazylibrarian; then
    make_dir "${DOCKERPATH}/mediaserver/lazylibrarian"
    cat > "${DOCKERPATH}/mediaserver/lazylibrarian/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  lazylibrarian:
    container_name: lazylibrarian
    image: lscr.io/linuxserver/lazylibrarian:latest
    ports:
      - 5299:5299
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
      - DOCKER_MODS=linuxserver/mods:universal-calibre|linuxserver/mods:lazylibrarian-ffmpeg
    volumes:
      - ${DOCKERPATH}/mediaserver/lazylibrarian:/config
      - ${MEDIAPATH}:/mnt/Media
      - ${PROCESSPATH}:/mnt/processing
      - ${BOOKSPATH}:/books
    networks:
      - internal
    restart: always
EOF
fi

if is_selected calibre-server; then
    make_dir "${DOCKERPATH}/mediaserver/calibre-server"
    cat > "${DOCKERPATH}/mediaserver/calibre-server/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  calibre-server:
    container_name: calibre-server
    image: lscr.io/linuxserver/calibre:latest
    ports:
      - 8085:8080
      - 8081:8081
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
      - SELKIES_ENABLE_HTTPS=false
    volumes:
      - ${DOCKERPATH}/mediaserver/calibre-server:/config
      - ${BOOKSPATH}:/books
    networks:
      - internal
    restart: unless-stopped
EOF
fi

if is_selected calibre-web; then
    make_dir "${DOCKERPATH}/mediaserver/calibre-web"
    cat > "${DOCKERPATH}/mediaserver/calibre-web/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  calibre-web:
    container_name: calibre-web
    image: lscr.io/linuxserver/calibre-web:latest
    ports:
      - 8084:8083
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
      - DOCKER_MODS=linuxserver/mods:universal-calibre
    volumes:
      - ${DOCKERPATH}/mediaserver/calibre-web:/config
      - ${BOOKSPATH}:/books
    networks:
      - internal
    restart: unless-stopped
EOF
fi

if is_selected bookshelf; then
    make_dir "${DOCKERPATH}/mediaserver/bookshelf"
    cat > "${DOCKERPATH}/mediaserver/bookshelf/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  bookshelf:
    container_name: bookshelf
    image: ghcr.io/pennydreadful/bookshelf:hardcover
    ports:
      - 8787:8787
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${DOCKERPATH}/mediaserver/bookshelf:/config
      - ${BOOKSPATH}:/books
      - ${MEDIAPATH}:/mnt/Media
      - ${PROCESSPATH}:/mnt/processing
    networks:
      - internal
    restart: unless-stopped
EOF
fi

if is_selected audiobookshelf; then
    make_dir "${DOCKERPATH}/mediaserver/audiobookshelf/config"
    make_dir "${DOCKERPATH}/mediaserver/audiobookshelf/metadata"
    cat > "${DOCKERPATH}/mediaserver/audiobookshelf/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  audiobookshelf:
    container_name: audiobookshelf
    image: ghcr.io/advplyr/audiobookshelf:latest
    ports:
      - 13378:80
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${DOCKERPATH}/mediaserver/audiobookshelf/config:/config
      - ${DOCKERPATH}/mediaserver/audiobookshelf/metadata:/metadata
      - ${BOOKSPATH}:/audiobooks
    networks:
      - internal
    restart: unless-stopped
EOF
fi

if is_selected nextcloud; then
    make_dir "${DOCKERPATH}/cloudservices/nextcloud"
    cat > "${DOCKERPATH}/cloudservices/nextcloud/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  nextcloud:
    image: nextcloud
    container_name: nextcloud
    restart: always
    ports:
      - 8087:80
    depends_on:
      - nextcloud-db
    volumes:
      - ${DOCKERPATH}/cloudservices/nextcloud/html:/var/www/html
      - ${DOCKERPATH}/cloudservices/nextcloud/data:/var/www/html/data
    environment:
      - MYSQL_PASSWORD=${NCDBUSER}
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_HOST=nextcloud-db
    networks:
      - internal

  nextcloud-db:
    image: mariadb:10.6
    container_name: nextcloud-db
    restart: always
    command: --transaction-isolation=READ-COMMITTED --log-bin=binlog --binlog-format=ROW
    volumes:
      - ${DOCKERPATH}/cloudservices/nextcloud/db:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=${NCDBROOT}
      - MYSQL_PASSWORD=${NCDBUSER}
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
    networks:
      - internal
EOF
fi

if is_selected ocis; then
    make_dir "${DOCKERPATH}/cloudservices/ocis"
    cat > "${DOCKERPATH}/cloudservices/ocis/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  ocis:
    image: owncloud/ocis:latest
    container_name: ocis
    restart: always
    ports:
      - 9200:9200
    entrypoint:
      - /bin/sh
      - -c
      - |
        ocis init --insecure true || true
        ocis server
    environment:
      - OCIS_URL=${OCIS_URL}
      - OCIS_INSECURE=true
      - OCIS_LOG_LEVEL=info
    volumes:
      - ${DOCKERPATH}/cloudservices/ocis/config:/etc/ocis
      - ${DOCKERPATH}/cloudservices/ocis/data:/var/lib/ocis
    networks:
      - internal
    logging:
      driver: local
EOF
fi

if is_selected immich; then
    make_dir "${DOCKERPATH}/cloudservices/immich"
    cat > "${DOCKERPATH}/cloudservices/immich/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  immich-server:
    container_name: immich_server
    image: ghcr.io/immich-app/immich-server:release
    ports:
      - 2283:2283
    environment:
      - DB_HOSTNAME=immich-postgres
      - DB_USERNAME=immich
      - DB_PASSWORD=${IMMICH_DB_PASSWORD}
      - DB_DATABASE_NAME=immich
      - REDIS_HOSTNAME=immich-redis
    volumes:
      - ${IMMICH_UPLOAD_LOCATION}:/usr/src/app/upload
      - /etc/localtime:/etc/localtime:ro
    depends_on:
      - immich-redis
      - immich-postgres
    networks:
      - internal
    restart: always

  immich-machine-learning:
    container_name: immich_machine_learning
    image: ghcr.io/immich-app/immich-machine-learning:release
    volumes:
      - ${DOCKERPATH}/cloudservices/immich/model-cache:/cache
    environment:
      - DB_HOSTNAME=immich-postgres
      - DB_USERNAME=immich
      - DB_PASSWORD=${IMMICH_DB_PASSWORD}
      - DB_DATABASE_NAME=immich
      - REDIS_HOSTNAME=immich-redis
    networks:
      - internal
    restart: always

  immich-redis:
    container_name: immich_redis
    image: docker.io/redis:6.2-alpine
    networks:
      - internal
    restart: always

  immich-postgres:
    container_name: immich_postgres
    image: docker.io/tensorchord/pgvecto-rs:pg14-v0.2.0
    environment:
      - POSTGRES_PASSWORD=${IMMICH_DB_PASSWORD}
      - POSTGRES_USER=immich
      - POSTGRES_DB=immich
    volumes:
      - ${DOCKERPATH}/cloudservices/immich/postgres:/var/lib/postgresql/data
    networks:
      - internal
    restart: always
EOF
fi

if is_selected seafile; then
    make_dir "${DOCKERPATH}/cloudservices/seafile"
    cat > "${DOCKERPATH}/cloudservices/seafile/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  seafile:
    container_name: seafile
    image: seafileltd/seafile-mc:latest
    ports:
      - 8090:80
    volumes:
      - ${DOCKERPATH}/cloudservices/seafile/data:/shared
      - ${SEAFILE_STORAGE_PATH}:/shared/seafile/seafile-data
    environment:
      - DB_HOST=seafile-db
      - DB_ROOT_PASSWD=${SEAFILE_DB_ROOT_PASSWORD}
      - SEAFILE_ADMIN_EMAIL=${SEAFILE_ADMIN_EMAIL}
      - SEAFILE_ADMIN_PASSWORD=${SEAFILE_ADMIN_PASSWORD}
      - SEAFILE_SERVER_HOSTNAME=${SEAFILE_HOSTNAME}
      - SEAFILE_SERVER_LETSENCRYPT=false
      - TIME_ZONE=${TZ}
    depends_on:
      - seafile-db
      - seafile-memcached
    networks:
      - internal
    restart: always

  seafile-db:
    container_name: seafile-db
    image: mariadb:10.11
    environment:
      - MYSQL_ROOT_PASSWORD=${SEAFILE_DB_ROOT_PASSWORD}
      - MYSQL_LOG_CONSOLE=true
    volumes:
      - ${DOCKERPATH}/cloudservices/seafile/db:/var/lib/mysql
    networks:
      - internal
    restart: always

  seafile-memcached:
    container_name: seafile-memcached
    image: memcached:1.6-alpine
    entrypoint: memcached -m 256
    networks:
      - internal
    restart: always
EOF
fi

if is_selected vaultwarden; then
    make_dir "${DOCKERPATH}/cloudservices/vaultwarden"
    cat > "${DOCKERPATH}/cloudservices/vaultwarden/docker-compose.yaml" <<EOF
networks:
  internal:
    external: true

services:
  vaultwarden:
    container_name: vaultwarden
    image: vaultwarden/server:latest
    ports:
      - 8222:80
    volumes:
      - ${DOCKERPATH}/cloudservices/vaultwarden:/data
    environment:
      - WEBSOCKET_ENABLED=true
    networks:
      - internal
    restart: unless-stopped
EOF
fi

# ─────────────────────────────────────────────
#  Deploy selected services
# ─────────────────────────────────────────────
# Only add portainer profile if the container doesn't already exist
_portainer_arg=""
sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^portainer$' || _portainer_arg="--profile portainer"

ALL_ARGS="--profile cloudflared $_portainer_arg $(profile_args wud netdata duckdns uptime-kuma speedtest \
                        nzbget qbittorrentvpn \
                        prowlarr sonarr radarr tdarr listenarr \
                        plex seerr lazylibrarian calibre-server calibre-web bookshelf audiobookshelf \
                        nextcloud ocis immich seafile vaultwarden)"
# Backup includes the backrest Docker service
is_selected backup && ALL_ARGS="$ALL_ARGS --profile backrest"

[[ -n "$ALL_ARGS" ]] && sudo docker compose -f "$SCRIPT_DIR/docker-compose.yaml" $ALL_ARGS up -d

# ─────────────────────────────────────────────
#  Install Backrest hook scripts
# ─────────────────────────────────────────────
if is_selected backup; then
    make_dir "${DOCKERPATH}/backup"
    make_dir "${DOCKERPATH}/backup/dumps"

    # Minimal config — DB passwords for pre-cloud.sh dumps
    sudo tee "${DOCKERPATH}/backup/backup.conf" > /dev/null <<EOF
DOCKERPATH="${DOCKERPATH}"
SEAFILE_DB_PASSWORD='${SEAFILE_DB_ROOT_PASSWORD:-}'
NEXTCLOUD_DB_PASSWORD='${NCDBROOT:-}'
EOF
    sudo chmod 600 "${DOCKERPATH}/backup/backup.conf"

    for script in pre-cloudservices.sh post-cloudservices.sh pre-mediaserver.sh post-mediaserver.sh pre-infrastructure.sh post-infrastructure.sh; do
        sudo cp "${SCRIPT_DIR}/backup/${script}" "${DOCKERPATH}/backup/${script}"
        sudo chmod +x "${DOCKERPATH}/backup/${script}"
    done


    echo "Hook scripts installed at ${DOCKERPATH}/backup/"
    echo "In Backrest, set hooks to: ${DOCKERPATH}/backup/pre-<group>.sh and ${DOCKERPATH}/backup/post-<group>.sh"

    make_dir "${DOCKERPATH}/cloudservices/backrest/data"
    make_dir "${DOCKERPATH}/cloudservices/backrest/config"
    make_dir "${DOCKERPATH}/cloudservices/backrest/cache"
    make_dir "${DOCKERPATH}/cloudservices/backrest/tmp"

    sudo tee "${DOCKERPATH}/cloudservices/backrest/docker-compose.yaml" > /dev/null <<EOF
networks:
  internal:
    external: true

services:
  backrest:
    container_name: backrest
    profiles: [backrest]
    image: ghcr.io/garethgeorge/backrest:latest
    ports:
      - 9898:9898
    volumes:
      - ${DOCKERPATH}/cloudservices/backrest/data:/data
      - ${DOCKERPATH}/cloudservices/backrest/config:/config
      - ${DOCKERPATH}/cloudservices/backrest/cache:/cache
      - ${DOCKERPATH}/cloudservices/backrest/tmp:/tmp
      - ${DOCKERPATH}:${DOCKERPATH}
      - /var/run/docker.sock:/var/run/docker.sock
      - /usr/bin/docker:/usr/bin/docker:ro
    environment:
      - BACKREST_DATA=/data
      - BACKREST_CONFIG=/config/config.json
      - XDG_CACHE_HOME=/cache
      - TMPDIR=/tmp
      - TZ=${TZ}
    networks:
      - internal
    restart: unless-stopped
    labels:
      - wud.watch=true
EOF
fi

LOCAL_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "┌──────────────────────────────────────────────────────────────┐"
echo "│                  Installation Complete!                      │"
echo "│                  Installed Services                          │"
echo "├──────────────────────────────────────────────────────────────┤"

print_url() {
    local label="$1"
    local url="$2"
    printf "│  %-20s %s\n" "$label" "$url"
}

print_url "Portainer"      "http://${LOCAL_IP}:9000"
is_selected wud          && print_url "WUD"            "http://${LOCAL_IP}:3000"
is_selected netdata      && print_url "Netdata"        "http://${LOCAL_IP}:19999"
is_selected uptime-kuma  && print_url "Uptime Kuma"    "http://${LOCAL_IP}:3001"
is_selected speedtest    && print_url "Speedtest"      "http://${LOCAL_IP}:8223"
is_selected nzbget       && print_url "NZBGet"         "http://${LOCAL_IP}:6789  (user: nzbget / pass: tegbzn6789)"
if is_selected qbittorrentvpn; then
    if [[ "${GLUETUN_VPN_TYPE}" == "wireguard" ]]; then
        print_url "qBittorrent+VPN" "http://${LOCAL_IP}:8080  (place config at ${DOCKERPATH}/mediaserver/gluetun/wireguard/wg0.conf)"
    else
        print_url "qBittorrent+VPN" "http://${LOCAL_IP}:8080  (place config at ${DOCKERPATH}/mediaserver/gluetun/custom.conf)"
    fi
fi
is_selected prowlarr     && print_url "Prowlarr"       "http://${LOCAL_IP}:9696"
is_selected sonarr       && print_url "Sonarr"         "http://${LOCAL_IP}:8989"
is_selected radarr       && print_url "Radarr"         "http://${LOCAL_IP}:7878"
is_selected tdarr        && print_url "Tdarr"          "http://${LOCAL_IP}:8265"
is_selected listenarr   && print_url "Listenarr"      "http://${LOCAL_IP}:4545"
is_selected plex         && print_url "Plex"           "http://${LOCAL_IP}:32400/web"
is_selected seerr        && print_url "Seerr"           "http://${LOCAL_IP}:5055"
is_selected lazylibrarian && print_url "LazyLibrarian"  "http://${LOCAL_IP}:5299"
is_selected calibre-server && print_url "Calibre-Server"  "http://${LOCAL_IP}:8085"
is_selected calibre-web  && print_url "Calibre-Web"     "http://${LOCAL_IP}:8084"
is_selected bookshelf    && print_url "Bookshelf"        "http://${LOCAL_IP}:8787"
is_selected audiobookshelf && print_url "Audiobookshelf" "http://${LOCAL_IP}:13378"
is_selected nextcloud    && print_url "Nextcloud"      "http://${LOCAL_IP}:8087"
is_selected ocis         && print_url "oCIS"           "${OCIS_URL}"
is_selected immich       && print_url "Immich"         "http://${LOCAL_IP}:2283"
is_selected seafile      && print_url "Seafile"        "http://${LOCAL_IP}:8090"
is_selected vaultwarden  && print_url "Vaultwarden"    "http://${LOCAL_IP}:8222"
is_selected duckdns      && print_url "DuckDNS"        "(no UI — managing ${DOMAINNAME}.duckdns.org)"
is_selected backup       && print_url "Backrest"       "http://${LOCAL_IP}:9898"
is_selected backup       && print_url "Backup hooks"   "${DOCKERPATH}/backup/"
print_url "Cloudflared"    "(no UI — tunnel active)"

echo "└──────────────────────────────────────────────────────────────┘"
echo ""
