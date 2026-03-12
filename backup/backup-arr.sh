#!/bin/bash
# ARR + Downloaders Backup — Sonarr, Radarr, Prowlarr, NZBGet, qBittorrent, Tdarr, Uptime Kuma

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/backup.conf"

LOG="${BACKUPPATH}/logs/arr.log"
mkdir -p "${BACKUPPATH}/logs"

log()        { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
is_running() { docker ps -q --filter "name=^${1}$" | grep -q .; }

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

# Build list of directories to snapshot
DIRS=()
for d in "${DOCKERPATH}/sonarr" "${DOCKERPATH}/radarr" "${DOCKERPATH}/prowlarr" \
          "${DOCKERPATH}/nzbget" "${DOCKERPATH}/qbittorrent" "${DOCKERPATH}/tdarr" \
          "${DOCKERPATH}/uptime-kuma"; do
    [[ -d "$d" ]] && DIRS+=("$d")
done

# Add extra user-defined paths
for p in ${EXTRA_PATHS_ARR}; do
    [[ -d "$p" ]] && DIRS+=("$p")
done

# Backup to B2
export B2_ACCOUNT_ID="${B2_KEY_ID}"
export B2_ACCOUNT_KEY="${B2_APP_KEY}"
export RESTIC_PASSWORD
export RESTIC_REPOSITORY="b2:${B2_BUCKET}:/arr"

log "Running restic backup to B2 (${RESTIC_REPOSITORY})"
restic backup "${DIRS[@]}" 2>>"$LOG"

log "Running restic forget/prune on B2"
restic forget \
    --keep-daily  "${RETENTION}" \
    --keep-weekly 4 \
    --keep-monthly 3 \
    --prune 2>>"$LOG"

# Also backup to local NAS repo if BACKUPPATH is set
if [[ -n "${BACKUPPATH}" ]]; then
    log "Running restic backup to local repo (${BACKUPPATH}/arr)"
    restic -r "${BACKUPPATH}/arr" backup "${DIRS[@]}" 2>>"$LOG"
    restic -r "${BACKUPPATH}/arr" forget \
        --keep-daily  "${RETENTION}" \
        --keep-weekly 4 \
        --keep-monthly 3 \
        --prune 2>>"$LOG"
fi

log "Restarting containers"
for c in "${STOPPED[@]}"; do
    docker start "$c" >>"$LOG" 2>&1
done

log "=== ARR backup complete ==="
