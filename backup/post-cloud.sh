#!/bin/bash
# Backrest post-backup hook — Cloud group
# Restarts containers after snapshot

echo "=== post-cloud: restarting containers ==="

# DBs and independent services first
for c in immich_postgres seafile-db nextcloud-db ocis vaultwarden backrest; do
    docker start "$c" 2>/dev/null && echo "Started $c" || true
done

sleep 5

# Apps that depend on DBs
for c in immich_redis immich_server immich_machine_learning \
          seafile-memcached seafile \
          nextcloud; do
    docker start "$c" 2>/dev/null && echo "Started $c" || true
done

echo "=== post-cloud: done ==="
