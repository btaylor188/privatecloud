#!/bin/bash
# ARR + Downloaders Backup — Sonarr, Radarr, Prowlarr, NZBGet, qBittorrent, Tdarr, Uptime Kuma

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/backup.conf"

DATE=$(date +%Y%m%d_%H%M%S)
DEST="${BACKUPPATH}/arr"
LOG="${BACKUPPATH}/logs/arr.log"

mkdir -p "$DEST" "${BACKUPPATH}/logs"

log()          { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
is_running()   { docker ps -q --filter "name=^${1}$" | grep -q .; }

log "=== ARR backup started ==="

STOPPED=()
stop_if_running() {
    if is_running "$1"; then
        log "Stopping $1"
        docker stop "$1" >>"$LOG" 2>&1
        STOPPED+=("$1")
    fi
}

for c in sonarr radarr prowlarr nzbget qbittorrent tdarr_node tdarr_server uptime-kuma; do
    stop_if_running "$c"
done

DIRS=()
for d in "${DOCKERPATH}/sonarr" "${DOCKERPATH}/radarr" "${DOCKERPATH}/prowlarr" \
          "${DOCKERPATH}/nzbget" "${DOCKERPATH}/qbittorrent" "${DOCKERPATH}/tdarr" \
          "${DOCKERPATH}/uptime-kuma"; do
    [[ -d "$d" ]] && DIRS+=("$d")
done

if [[ ${#DIRS[@]} -gt 0 ]]; then
    log "Creating archive: arr_${DATE}.tar.gz"
    tar -czf "${DEST}/arr_${DATE}.tar.gz" "${DIRS[@]}" 2>>"$LOG"
    log "Archive complete"
fi

log "Restarting containers"
for c in "${STOPPED[@]}"; do
    docker start "$c" >>"$LOG" 2>&1
done

log "Cleaning up backups older than ${RETENTION} days"
find "$DEST" -name "*.tar.gz" -mtime +"${RETENTION}" -delete 2>>"$LOG"

log "=== ARR backup complete ==="
