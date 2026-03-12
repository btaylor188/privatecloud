#!/bin/bash
# Backrest post-backup hook — Media group
# Restarts containers after snapshot

echo "=== post-media: restarting containers ==="

for c in plex seerr; do
    docker start "$c" 2>/dev/null && echo "Started $c" || true
done

echo "=== post-media: done ==="
