#!/bin/bash
# Media Server Backup — Plex, Seerr

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/backup.conf"

LOG="${BACKUPPATH}/logs/media.log"
mkdir -p "${BACKUPPATH}/logs"

log()        { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
is_running() { docker ps -q --filter "name=^${1}$" | grep -q .; }

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

# Build list of directories to snapshot
DIRS=()
for d in "${DOCKERPATH}/plex" "${DOCKERPATH}/seerr"; do
    [[ -d "$d" ]] && DIRS+=("$d")
done

# Add extra user-defined paths
for p in ${EXTRA_PATHS_MEDIA}; do
    [[ -d "$p" ]] && DIRS+=("$p")
done

if [[ ${#DIRS[@]} -eq 0 ]]; then
    log "No directories found to back up — skipping"
else
    # Backup to B2
    export B2_ACCOUNT_ID="${B2_KEY_ID}"
    export B2_ACCOUNT_KEY="${B2_APP_KEY}"
    export RESTIC_PASSWORD
    export RESTIC_REPOSITORY="b2:${B2_BUCKET}:/media"

    log "Initializing B2 repo if needed"
    restic snapshots >>"$LOG" 2>&1 || restic init >>"$LOG" 2>&1

    log "Running restic backup to B2 (${RESTIC_REPOSITORY})"
    restic backup "${DIRS[@]}" >>"$LOG" 2>&1

    log "Running restic forget/prune on B2"
    restic forget \
        --keep-daily  "${RETENTION}" \
        --keep-weekly 4 \
        --keep-monthly 3 \
        --prune >>"$LOG" 2>&1

    # Also backup to local NAS repo if BACKUPPATH is set
    if [[ -n "${BACKUPPATH}" ]]; then
        log "Initializing local repo if needed (${BACKUPPATH}/media)"
        restic -r "${BACKUPPATH}/media" snapshots >>"$LOG" 2>&1 || \
            restic -r "${BACKUPPATH}/media" init >>"$LOG" 2>&1

        log "Running restic backup to local repo (${BACKUPPATH}/media)"
        restic -r "${BACKUPPATH}/media" backup "${DIRS[@]}" >>"$LOG" 2>&1
        restic -r "${BACKUPPATH}/media" forget \
            --keep-daily  "${RETENTION}" \
            --keep-weekly 4 \
            --keep-monthly 3 \
            --prune >>"$LOG" 2>&1
    fi
fi

log "Restarting containers"
for c in "${STOPPED[@]}"; do
    docker start "$c" >>"$LOG" 2>&1
done

log "=== Media backup complete ==="
