# List all shell aliases, optionally filtered
show_aliases() {
    if [[ "$1" == "-h" ]]; then
        echo "List all shell aliases, optionally filtered"
        echo "Usage: show_aliases [filter]"
        echo "Example: show_aliases git"
        return 0
    fi

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

# List all available shell functions
funcs() {
    local scripts_dir="$HOME/.shell-scripts"

    echo "Available functions:"
    echo "==================="

    for f in "$scripts_dir"/*.sh; do
        local category=$(basename "$f" .sh)
        local has_funcs=0

        while IFS= read -r line; do
            local name=$(echo "$line" | sed 's/().*//')
            local desc=$(grep -B3 "^${name}()" "$f" | grep "^#" | tail -1 | sed 's/^# *//')

            if [[ $has_funcs -eq 0 ]]; then
                echo ""
                echo "  [$category]"
                has_funcs=1
            fi

            printf "  %-20s %s\n" "$name" "$desc"
        done < <(grep -E "^[a-zA-Z0-9_-]+\(\)" "$f")
    done

    echo ""
    echo "Use '<function> -h' for usage details."
}

# Keyboard-Shortcuts und Navigation anzeigen
shortcuts() {
  cat <<'EOF'
Navigation
  Control+A      Zeilenanfang
  Control+E      Zeilenende
  Alt+B          Wort zurück
  Alt+F          Wort vor
  Control+XX     Zwischen aktueller und vorheriger Position wechseln

Löschen & Einfügen
  Control+U      Vor Cursor löschen
  Control+K      Nach Cursor löschen
  Control+W      Letztes Wort löschen
  Alt+D          Nächstes Wort löschen
  Control+P      Gelöschtes einfügen (yank)
  Control+O      Durch Kill-Ring rotieren (nach yank)

Bearbeiten
  Control+T      Zwei Zeichen vertauschen
  Alt+T          Zwei Wörter vertauschen
  Alt+U          Wort in Großbuchstaben
  Alt+L          Wort in Kleinbuchstaben
  Alt+C          Wort kapitalisieren
  Control+_      Rückgängig (undo)

History
  Control+R      History rückwärts durchsuchen
  Control+S      History vorwärts durchsuchen
  Control+G      Suche abbrechen
  !!             Letzter Befehl
  !$             Letztes Argument
  !^             Erstes Argument
  !*             Alle Argumente
  !:n            n-tes Argument
  !cmd           Letzter Befehl der mit cmd begann

Prozesse & Terminal
  Control+L      Terminal leeren
  Control+C      Abbrechen
  Control+Z      Prozess pausieren
  fg             Pausierten Prozess fortsetzen
  Control+D      Shell beenden / EOF senden

Named Directories
  ~prod          production-cluster
  ~staging       staging-cluster
  ~test          test-cluster
EOF
}

# Alle docx- und xlsx-Dateien im aktuellen Verzeichnis mit pandoc zu Markdown zusammenfuehren
# (xlsx wird ueber LibreOffice in Markdown-Tabellen umgewandelt, da pandoc xlsx nicht liest)
mergedocs() {
    if [[ "${1:-}" == "-h" ]]; then
        echo "Alle docx- und xlsx-Dateien im aktuellen Verzeichnis zu einer Markdown-Datei zusammenfuehren"
        echo "Usage: mergedocs [-d|--date] [output]"
        echo "  -d|--date  Datum an Dateinamen anhaengen (z.B. merged_2025-01-15.md)"
        echo "  output     Ausgabedatei (Standard: merged.md)"
        echo "  xlsx wird ueber LibreOffice (soffice) in Markdown-Tabellen umgewandelt"
        echo "Example: mergedocs -d ergebnis.md"
        return 0
    fi

    local add_date=0
    if [[ "${1:-}" == "-d" ]] || [[ "${1:-}" == "--date" ]]; then
        add_date=1
        shift
    fi

    local output="${1:-merged.md}"
    if [[ $add_date -eq 1 ]]; then
        output="${output%.md}_$(date +%Y-%m-%d).md"
    fi

    local docx_files=(*.docx(N))
    local xlsx_files=(*.xlsx(N))

    if [[ ${#docx_files[@]} -eq 0 && ${#xlsx_files[@]} -eq 0 ]]; then
        echo "Fehler: Keine .docx- oder .xlsx-Dateien im aktuellen Verzeichnis gefunden"
        return 1
    fi

    if ! command -v pandoc &>/dev/null; then
        echo "Fehler: pandoc ist nicht installiert"
        return 1
    fi

    if [[ ${#xlsx_files[@]} -gt 0 ]] && ! command -v soffice &>/dev/null; then
        echo "Fehler: soffice (LibreOffice) wird zum Konvertieren von .xlsx benoetigt, ist aber nicht installiert"
        return 1
    fi

    : > "$output"

    if [[ ${#docx_files[@]} -gt 0 ]]; then
        echo ">>> Konvertiere ${#docx_files[@]} docx-Datei(en)..."
        pandoc -f docx -t markdown_strict "${docx_files[@]}" --extract-media=./media >> "$output"
        if [[ $? -ne 0 ]]; then
            echo "FEHLER: docx-Konvertierung fehlgeschlagen"
            return 1
        fi
    fi

    if [[ ${#xlsx_files[@]} -gt 0 ]]; then
        echo ">>> Konvertiere ${#xlsx_files[@]} xlsx-Datei(en)..."
        local tmpdir
        tmpdir=$(mktemp -d)
        # Alle xlsx in einem soffice-Aufruf konvertieren (LibreOffice-Start ist langsam)
        soffice --headless --convert-to html "${xlsx_files[@]}" --outdir "$tmpdir" >/dev/null 2>&1
        local x html
        for x in "${xlsx_files[@]}"; do
            html="$tmpdir/${x:t:r}.html"
            if [[ -f "$html" ]]; then
                printf '\n\n# %s\n\n' "${x:t}" >> "$output"
                pandoc -f html -t markdown_strict+pipe_tables "$html" >> "$output"
            else
                echo "WARNUNG: Konnte $x nicht konvertieren (uebersprungen)"
            fi
        done
        rm -rf "$tmpdir"
    fi

    echo "Fertig: $(wc -l < "$output") Zeilen in $output (${#docx_files[@]} docx, ${#xlsx_files[@]} xlsx)"
}

# Video/Audio mit yt-dlp herunterladen
yt() {
    if [[ "$1" == "-h" ]]; then
        echo "Video/Audio mit yt-dlp herunterladen"
        echo "Usage: yt [url]"
        echo "  Ohne Argument wird die URL aus der Zwischenablage verwendet."
        echo "Example: yt https://youtube.com/watch?v=abc123"
        return 0
    fi

    if [ -n "$1" ]; then
        yt-dlp "$1"
    else
        yt-dlp "$(pbpaste)"
    fi
}
