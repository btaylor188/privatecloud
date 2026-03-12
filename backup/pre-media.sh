#!/bin/bash
# Backrest pre-backup hook — Media group
# Stops containers before snapshot

is_running() { docker ps -q --filter "name=^${1}$" | grep -q .; }

echo "=== pre-media: stopping containers ==="

for c in plex seerr; do
    is_running "$c" && echo "Stopping $c" && docker stop "$c"
done

echo "=== pre-media: done ==="
