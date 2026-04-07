#!/bin/bash
#
# Disconnect all WireGuard tunnels and quit the app.
# Called by wireguard-session-watcher on user-switch (Fast User Switch).

set -euo pipefail

log() {
    /usr/bin/logger "wireguard-disconnect: $*"
}

log "session resigned — disconnecting WireGuard tunnels"

# 1. Disconnect tunnels managed by macOS Network Extensions (scutil)
while IFS= read -r line; do
    # Lines look like: * (Connected)      "AB12-…" [WireGuard]
    name=$(echo "$line" | sed -n 's/.*"\(.*\)".*/\1/p')
    [ -z "$name" ] && continue
    log "stopping tunnel: $name"
    /usr/sbin/scutil --nc stop "$name"
done < <(/usr/sbin/scutil --nc list 2>/dev/null | grep -i wireguard || true)

# 2. If wg-quick is available, tear down kernel interfaces
if command -v wg &>/dev/null; then
    for iface in $(wg show interfaces 2>/dev/null); do
        log "bringing down interface: $iface"
        wg-quick down "$iface" 2>/dev/null || true
    done
fi

# 3. Quit the WireGuard app
/usr/bin/osascript -e 'quit app "WireGuard"' 2>/dev/null || true

log "done"
