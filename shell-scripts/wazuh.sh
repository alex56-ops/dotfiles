# Search for a package in the local Wazuh database
wazuh_find() {
    if [[ "$1" == "-h" ]] || [[ -z "$1" ]]; then
        echo "Search for a package in the local Wazuh database"
        echo "Usage: wazuh_find <package-name>"
        echo "Example: wazuh_find wheel"
        [[ -z "$1" ]] && return 1 || return 0
    fi

    local db="/Library/Ossec/queue/syscollector/db/local.db"

    # Prüfe mit sudo ob die DB existiert
    if ! sudo test -f "$db"; then
        echo "Error: Wazuh database not found at $db"
        return 1
    fi

    echo "🔍 Searching for package: $1"
    echo "─────────────────────────────────────────────────"
    sudo sqlite3 -header -column "$db" \
        "SELECT name, version, format, location FROM dbsync_packages WHERE name='$1';"

    # Zeige Anzahl der Treffer
    local count=$(sudo sqlite3 "$db" "SELECT COUNT(*) FROM dbsync_packages WHERE name='$1';")
    echo "─────────────────────────────────────────────────"
    echo "✓ Found $count installation(s)"
}
