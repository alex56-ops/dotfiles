# Function to show aliases
show_aliases() {
    local filter="$1"
    if [[ -n "$filter" ]]; then
        echo "📋 Aliase gefiltert nach: '$filter'"
        alias | grep -i "$filter" | sort
    else
        echo "📋 Alle deine Aliase:"
        echo "==================="
        alias | sort | while IFS='=' read -r name value; do
            clean_value=$(echo "$value" | sed "s/^'//; s/'$//")
            printf "%-25s → %s\n" "$name" "$clean_value"
        done | nl -w3 -s'. '
        echo ""
        echo "Anzahl Aliase: $(alias | wc -l)"
    fi
}

# SSH Known Hosts Cleanup Funktion

rm_host() {
    local ip="$1"
    local known_hosts="$HOME/.ssh/known_hosts"
    if [[ -z "$ip" ]]; then
        echo "Verwendung: rm_ssh_host <IP-Adresse>"
        return 1
    fi

    if [[ ! -f "$known_hosts" ]]; then
        echo "Fehler: $known_hosts nicht gefunden"
        return 1
    fi

    # Prüfen ob IP existiert
    if ! grep -q "^$ip\|^$ip,\|,$ip\|,$ip," "$known_hosts"; then
        echo "IP $ip nicht in known_hosts gefunden"
        return 1
    fi

    # Temporäre Datei erstellen
    local temp_file=$(mktemp)
    grep -v "^$ip\|^$ip,\|,$ip\|,$ip," "$known_hosts" > "$temp_file"
    # Temporäre Datei zurück nach known_hosts kopieren
    mv "$temp_file" "$known_hosts"
    echo "Alle Einträge für IP $ip wurden entfernt"
}

# remove last 3 hosts from known_hosts
rm_last3() {
    local known_hosts="$HOME/.ssh/known_hosts"
    if [[ ! -f "$known_hosts" ]]; then
        echo "Fehler: $known_hosts nicht gefunden"
        return 1
    fi
    # Alle Zeilen außer den letzten drei in temporäre Datei schreiben
    local temp_file=$(mktemp)
    local total_lines=$(wc -l < "$known_hosts")
    local keep_lines=$((total_lines - 3))
    head -n "$keep_lines" "$known_hosts" > "$temp_file"

    # Temporäre Datei zurück nach known_hosts kopieren
    mv "$temp_file" "$known_hosts"
    echo "Die letzten 3 Einträge wurden entfernt"
}

# Wazuh Package Search
wazuh-find() {
    if [ -z "$1" ]; then
        echo "Usage: wazuh-find <package-name>"
        echo "Example: wazuh-find wheel"
        return 1
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
