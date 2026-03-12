#!/bin/bash
# Backrest pre-backup hook — ARR group
# Stops containers before snapshot

is_running() { docker ps -q --filter "name=^${1}$" | grep -q .; }

echo "=== pre-arr: stopping containers ==="

for c in sonarr radarr prowlarr nzbget qbittorrent tdarr_node tdarr_server uptime-kuma; do
    is_running "$c" && echo "Stopping $c" && docker stop "$c"
done

echo "=== pre-arr: done ==="
