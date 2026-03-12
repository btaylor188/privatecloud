#!/bin/bash
# Backrest pre-backup hook — Cloud group
# Dumps databases and stops containers before snapshot

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/backup.conf"

DUMP_DIR="${DOCKERPATH}/cloud/backup/dumps"
mkdir -p "$DUMP_DIR"

is_running() { docker ps -q --filter "name=^${1}$" | grep -q .; }

echo "=== pre-cloud: dumping databases ==="

if is_running immich_postgres; then
    echo "Dumping Immich database"
    docker exec immich_postgres pg_dumpall -U immich > "${DUMP_DIR}/immich_db_$(date +%Y%m%d_%H%M%S).sql"
fi

if is_running seafile-db; then
    echo "Dumping Seafile database"
    docker exec seafile-db mysqldump --all-databases -uroot -p"${SEAFILE_DB_PASSWORD}" \
        > "${DUMP_DIR}/seafile_db_$(date +%Y%m%d_%H%M%S).sql"
fi

if is_running nextcloud-db; then
    echo "Dumping Nextcloud database"
    docker exec nextcloud-db mysqldump --all-databases -uroot -p"${NEXTCLOUD_DB_PASSWORD}" \
        > "${DUMP_DIR}/nextcloud_db_$(date +%Y%m%d_%H%M%S).sql"
fi

echo "=== pre-cloud: stopping containers ==="

for c in immich_server immich_machine_learning immich_redis immich_postgres \
          seafile seafile-memcached seafile-db \
          nextcloud nextcloud-db \
          ocis vaultwarden backrest; do
    is_running "$c" && echo "Stopping $c" && docker stop "$c"
done

echo "=== pre-cloud: done ==="
