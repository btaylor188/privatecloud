#!/bin/bash
# Media Server Backup — Plex, Seerr

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/backup.conf"

DATE=$(date +%Y%m%d_%H%M%S)
DEST="${BACKUPPATH}/media"
LOG="${BACKUPPATH}/logs/media.log"

mkdir -p "$DEST" "${BACKUPPATH}/logs"

log()          { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
is_running()   { docker ps -q --filter "name=^${1}$" | grep -q .; }

log "=== Media backup started ==="

STOPPED=()
stop_if_running() {
    if is_running "$1"; then
        log "Stopping $1"
        docker stop "$1" >>"$LOG" 2>&1
        STOPPED+=("$1")
    fi
}

for c in plex seerr; do
    stop_if_running "$c"
done

DIRS=()
for d in "${DOCKERPATH}/plex" "${DOCKERPATH}/seerr"; do
    [[ -d "$d" ]] && DIRS+=("$d")
done

if [[ ${#DIRS[@]} -gt 0 ]]; then
    log "Creating archive: media_${DATE}.tar.gz"
    tar -czf "${DEST}/media_${DATE}.tar.gz" "${DIRS[@]}" 2>>"$LOG"
    log "Archive complete"
fi

log "Restarting containers"
for c in "${STOPPED[@]}"; do
    docker start "$c" >>"$LOG" 2>&1
done

log "Cleaning up backups older than ${RETENTION} days"
find "$DEST" -name "*.tar.gz" -mtime +"${RETENTION}" -delete 2>>"$LOG"

log "=== Media backup complete ==="
