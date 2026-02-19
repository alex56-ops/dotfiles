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

# Selective Ansible Service Update on server03
update() {
    if [ -z "$1" ]; then
        echo "Usage: update [--base|-b] <service1> [service2] [service3] ..."
        echo "Example: update authelia immich"
        echo "         update --base authelia  (includes baseline and docker)"
        echo "         update -b authelia      (short form)"
        return 1
    fi

    local skip_tags="--skip-tags baseline,docker"

    if [ "$1" = "--base" ] || [ "$1" = "-b" ]; then
        skip_tags=""
        shift
    fi

    local services="['$(echo "$@" | sed "s/ /','/g")']"

    ssh -t server03 \
        "cd /mnt/ansible/repo && 
         git pull && 
         ansible-playbook playbooks/services/main-updating.yml -e \"deploy_only=$services\" $skip_tags"
}

# generate alphanumeric password and encrypt it with ansible
encpass() {
  local use_hex=0
  local args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h) use_hex=1; shift ;;
      *)  args+=("$1"); shift ;;
    esac
  done

  if [ ${#args[@]} -ne 2 ]; then
    echo "Usage: encpass [-h] <length> <name>"
    return 1
  fi

  local length=${args[1]}
  local name=${args[2]}
  local password

  if [ $use_hex -eq 1 ]; then
    password=$(openssl rand -hex "$((length / 2))")
  else
    password=$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | cut -c1-"$length")
  fi

  ansible-vault encrypt_string "$password" --name "$name"
}

# decrypt ansible-vault encrypted string
decpass() {
  if [ $# -ne 1 ]; then
    echo "Usage: decpass <encrypted_string>"
    return 1
  fi

  echo "$1" | grep -v '!vault' | sed 's/^[[:space:]]*//' | ansible-vault decrypt --output -
  echo
}
