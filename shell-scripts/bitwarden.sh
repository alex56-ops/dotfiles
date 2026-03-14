# Bitwarden JSON-Export nach Ordner filtern
filter_bw() {
    if [[ "$1" == "-h" ]]; then
        echo "Bitwarden JSON-Export nach Ordner filtern"
        echo "Usage: filter_bw <export.json> <ordner> [output.json]"
        echo "  <export.json>  Pfad zur exportierten Bitwarden JSON-Datei"
        echo "  <ordner>       Ordnername (z.B. 'IT/H&B') oder Ordner-ID (UUID)"
        echo "  [output.json]  Ausgabedatei (optional, Standard: export_filtered.json)"
        echo "Example: filter_bw export.json 'IT/H&B'"
        echo "         filter_bw export.json 'IT/H&B' gefiltert.json"
        return 0
    fi

    if [[ -z "$1" ]] || [[ -z "$2" ]]; then
        echo "Fehler: Mindestens 2 Argumente erforderlich."
        echo "Usage: filter_bw <export.json> <ordner> [output.json]"
        echo "Hilfe: filter_bw -h"
        return 1
    fi

    python3 "$HOME/.shell-scripts/python-scripts/filter_bitwarden.py" "$@"
}
