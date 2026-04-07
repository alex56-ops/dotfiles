#!/bin/bash
#
# Colima idle auto-stop — called every 5 min by launchd.
# Stops Colima when no Docker activity for COLIMA_IDLE_TIMEOUT seconds.

set -euo pipefail

COLIMA="$HOME/.homebrew/bin/colima"
DOCKER="/opt/homebrew/bin/docker"
ACTIVITY_FILE="$HOME/.local/state/colima/last-activity"
COLIMA_IDLE_TIMEOUT="${COLIMA_IDLE_TIMEOUT:-900}" # 15 min

log() {
    /usr/bin/logger "colima-idle-check: $*"
}

# 1. Colima not running → nothing to do
if ! "$COLIMA" status &>/dev/null; then
    exit 0
fi

# 2. Running containers → update timestamp, exit
if [ -n "$("$DOCKER" ps -q 2>/dev/null)" ]; then
    mkdir -p "$(dirname "$ACTIVITY_FILE")"
    touch "$ACTIVITY_FILE"
    log "running containers detected, resetting idle timer"
    exit 0
fi

# 3. Check timestamp age
if [ ! -f "$ACTIVITY_FILE" ]; then
    # No activity file → treat as idle, stop
    log "no activity file found, stopping Colima"
    "$COLIMA" stop
    exit 0
fi

last_activity=$(/usr/bin/stat -f %m "$ACTIVITY_FILE")
now=$(/bin/date +%s)
idle_seconds=$(( now - last_activity ))

if [ "$idle_seconds" -ge "$COLIMA_IDLE_TIMEOUT" ]; then
    log "idle for ${idle_seconds}s (threshold: ${COLIMA_IDLE_TIMEOUT}s), stopping Colima"
    "$COLIMA" stop
else
    remaining=$(( COLIMA_IDLE_TIMEOUT - idle_seconds ))
    log "idle for ${idle_seconds}s, ${remaining}s until auto-stop"
fi
