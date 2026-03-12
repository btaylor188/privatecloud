#!/bin/bash
# Private Cloud Backup — Immich, Seafile, Nextcloud, oCIS, Vaultwarden

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/backup.conf"

DATE=$(date +%Y%m%d_%H%M%S)
DEST="${BACKUPPATH}/cloud"
LOG="${BACKUPPATH}/logs/cloud.log"

mkdir -p "$DEST" "${BACKUPPATH}/logs"

log()          { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
is_running()   { docker ps -q --filter "name=^${1}$" | grep -q .; }

log "=== Cloud backup started ==="

STOPPED=()
stop_if_running() {
    if is_running "$1"; then
        log "Stopping $1"
        docker stop "$1" >>"$LOG" 2>&1
        STOPPED+=("$1")
    fi
}

# Dump databases while containers are still running
if is_running immich_postgres; then
    log "Dumping Immich database"
    docker exec immich_postgres pg_dumpall -U immich > "${DEST}/immich_db_${DATE}.sql" 2>>"$LOG"
fi

if is_running seafile-db; then
    log "Dumping Seafile database"
    docker exec seafile-db mysqldump --all-databases -uroot -p"${SEAFILE_DB_PASSWORD}" \
        > "${DEST}/seafile_db_${DATE}.sql" 2>>"$LOG"
fi

if is_running nextcloud-db; then
    log "Dumping Nextcloud database"
    docker exec nextcloud-db mysqldump --all-databases -uroot -p"${NEXTCLOUD_DB_PASSWORD}" \
        > "${DEST}/nextcloud_db_${DATE}.sql" 2>>"$LOG"
fi

# Stop apps first, then databases
for c in immich_server immich_machine_learning immich_redis immich_postgres \
          seafile seafile-memcached seafile-db \
          nextcloud nextcloud-db \
          ocis vaultwarden; do
    stop_if_running "$c"
done

# Archive config/metadata directories under DOCKERPATH
DIRS=()
for d in "${DOCKERPATH}/immich" "${DOCKERPATH}/seafile" "${DOCKERPATH}/nextcloud" \
          "${DOCKERPATH}/ocis" "${DOCKERPATH}/vaultwarden"; do
    [[ -d "$d" ]] && DIRS+=("$d")
done

if [[ ${#DIRS[@]} -gt 0 ]]; then
    log "Creating archive: cloud_${DATE}.tar.gz"
    tar -czf "${DEST}/cloud_${DATE}.tar.gz" "${DIRS[@]}" 2>>"$LOG"
    log "Archive complete"
fi

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

# Remove backups older than retention period
log "Cleaning up backups older than ${RETENTION} days"
find "$DEST" -name "*.tar.gz" -mtime +"${RETENTION}" -delete 2>>"$LOG"
find "$DEST" -name "*.sql"    -mtime +"${RETENTION}" -delete 2>>"$LOG"

log "=== Cloud backup complete ==="
