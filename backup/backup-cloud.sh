#!/bin/bash
# Private Cloud Backup — Immich, Seafile, Nextcloud, oCIS, Vaultwarden

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/backup.conf"

LOG="${BACKUPPATH}/logs/cloud.log"
mkdir -p "${BACKUPPATH}/logs"

log()        { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
is_running() { docker ps -q --filter "name=^${1}$" | grep -q .; }

log "=== Cloud backup started ==="

STOPPED=()
stop_if_running() {
    if is_running "$1"; then
        log "Stopping $1"
        docker stop "$1" >>"$LOG" 2>&1
        STOPPED+=("$1")
    fi
}

# Dump databases into a temp dir (included in snapshot)
DUMP_DIR="$(mktemp -d)"

if is_running immich_postgres; then
    log "Dumping Immich database"
    docker exec immich_postgres pg_dumpall -U immich > "${DUMP_DIR}/immich_db_$(date +%Y%m%d_%H%M%S).sql" 2>>"$LOG"
fi

if is_running seafile-db; then
    log "Dumping Seafile database"
    docker exec seafile-db mysqldump --all-databases -uroot -p"${SEAFILE_DB_PASSWORD}" \
        > "${DUMP_DIR}/seafile_db_$(date +%Y%m%d_%H%M%S).sql" 2>>"$LOG"
fi

if is_running nextcloud-db; then
    log "Dumping Nextcloud database"
    docker exec nextcloud-db mysqldump --all-databases -uroot -p"${NEXTCLOUD_DB_PASSWORD}" \
        > "${DUMP_DIR}/nextcloud_db_$(date +%Y%m%d_%H%M%S).sql" 2>>"$LOG"
fi

# Stop apps first, then databases
for c in immich_server immich_machine_learning immich_redis immich_postgres \
          seafile seafile-memcached seafile-db \
          nextcloud nextcloud-db \
          ocis vaultwarden; do
    stop_if_running "$c"
done

# Build list of directories to snapshot
DIRS=()
for d in "${DOCKERPATH}/immich" "${DOCKERPATH}/seafile" "${DOCKERPATH}/nextcloud" \
          "${DOCKERPATH}/ocis" "${DOCKERPATH}/vaultwarden"; do
    [[ -d "$d" ]] && DIRS+=("$d")
done

# Add extra user-defined paths
for p in ${EXTRA_PATHS_CLOUD}; do
    [[ -d "$p" ]] && DIRS+=("$p")
done

# Backup to B2
export B2_ACCOUNT_ID="${B2_KEY_ID}"
export B2_ACCOUNT_KEY="${B2_APP_KEY}"
export RESTIC_PASSWORD
export RESTIC_REPOSITORY="b2:${B2_BUCKET}:/cloud"

log "Running restic backup to B2 (${RESTIC_REPOSITORY})"
restic backup "${DIRS[@]}" "$DUMP_DIR" 2>>"$LOG"

log "Running restic forget/prune on B2"
restic forget \
    --keep-daily  "${RETENTION}" \
    --keep-weekly 4 \
    --keep-monthly 3 \
    --prune 2>>"$LOG"

# Also backup to local NAS repo if BACKUPPATH is set
if [[ -n "${BACKUPPATH}" ]]; then
    log "Running restic backup to local repo (${BACKUPPATH}/cloud)"
    restic -r "${BACKUPPATH}/cloud" backup "${DIRS[@]}" "$DUMP_DIR" 2>>"$LOG"
    restic -r "${BACKUPPATH}/cloud" forget \
        --keep-daily  "${RETENTION}" \
        --keep-weekly 4 \
        --keep-monthly 3 \
        --prune 2>>"$LOG"
fi

rm -rf "$DUMP_DIR"

# Restart in dependency order (DBs first, then apps)
log "Restarting containers"
for c in immich_postgres seafile-db nextcloud-db ocis vaultwarden; do
    [[ " ${STOPPED[*]} " =~ " ${c} " ]] && docker start "$c" >>"$LOG" 2>&1
done
sleep 5
for c in immich_redis immich_server immich_machine_learning \
          seafile-memcached seafile \
          nextcloud; do
    [[ " ${STOPPED[*]} " =~ " ${c} " ]] && docker start "$c" >>"$LOG" 2>&1
done

log "=== Cloud backup complete ==="
