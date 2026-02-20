# Remove an IP from ~/.ssh/known_hosts
rm_host() {
    if [[ "$1" == "-h" ]] || [[ -z "$1" ]]; then
        echo "Remove an IP from ~/.ssh/known_hosts"
        echo "Usage: rm_host <ip>"
        [[ -z "$1" ]] && return 1 || return 0
    fi

    local ip="$1"
    local known_hosts="$HOME/.ssh/known_hosts"

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

# Remove the last 3 entries from known_hosts
rm_last3() {
    if [[ "$1" == "-h" ]]; then
        echo "Remove the last 3 entries from known_hosts"
        echo "Usage: rm_last3"
        return 0
    fi

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
