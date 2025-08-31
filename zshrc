ssh-add --apple-use-keychain ~/.ssh/id_ed25519

setopt EXTENDED_HISTORY      # Speichere Timestamps
setopt SHARE_HISTORY         # Teile History zwischen Sessions
setopt HIST_VERIFY           # Bestätige History-Expansion
setopt INC_APPEND_HISTORY    # Speichere sofort, nicht erst beim Exit
export HISTTIMEFORMAT="%d.%m.%Y %H:%M:%S "

# Completion-System aktivieren
autoload -Uz compinit
compinit
# load aliases first
if [ -f ~/.aliases ]; then
    source ~/.aliases
fi

# shell helpers
export PATH="/opt/homebrew/bin:$PATH"
eval "$(/Users/abaer/.local/bin/mise activate zsh)"
export TOKENIZERS_PARALLELISM=false

# shell design
PROMPT='[%F{green}%n%f]-(%F{blue}%~%f)-
%F{red}└─▶%f '

# function to show aliases
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
# Personal Homebrew
export PATH="$HOME/.homebrew/bin:$PATH"

if [ -f "$HOME/.local/bin/env" ]; then
    . "$HOME/.local/bin/env"
fi
