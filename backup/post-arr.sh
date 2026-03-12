#!/bin/bash
# Backrest post-backup hook — ARR group
# Restarts containers after snapshot

echo "=== post-arr: restarting containers ==="

for c in gluetun sonarr radarr prowlarr nzbget qbittorrent tdarr_node tdarr_server uptime-kuma; do
    docker start "$c" 2>/dev/null && echo "Started $c" || true
done

echo "=== post-arr: done ==="
