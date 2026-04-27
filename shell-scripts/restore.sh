# Restore a service on server03 from NAS backup
restore() {
    if [[ "${1:-}" == "-h" ]] || [[ -z "${1:-}" ]]; then
        echo "Restore a service on server03 from NAS backup"
        echo "Usage: restore <service> [archive]"
        echo "       restore --list"
        echo ""
        echo "  --list       List available archives on NAS"
        echo "  <service>    Service to restore (e.g. briefkasten)"
        echo "  [archive]    Specific archive name (default: latest)"
        echo ""
        echo "Example: restore briefkasten"
        echo "         restore briefkasten server03-2025-01-15T02:00:00"
        echo "         restore --list"
        [[ -z "${1:-}" ]] && return 1 || return 0
    fi

    local NAS_SCRIPT="/mnt/backup/recovery/scripts/restore-push.sh"

    # List mode
    if [[ "$1" == "--list" ]]; then
        echo "Fetching archives from NAS..."
        ssh nas "sudo -u recovery ${NAS_SCRIPT} --list server03"
        return $?
    fi

    local service="$1"
    local archive="${2:-}"

    # Show available services in latest archive if no archive specified
    echo "Checking latest archive on NAS..."
    local info
    info=$(ssh nas "sudo -u recovery ${NAS_SCRIPT} server03" 2>&1)
    echo "$info"
    echo ""

    # Confirmation prompt
    echo "========================================"
    echo "  WARNUNG: Restore von '${service}'"
    echo "========================================"
    echo ""
    echo "Dies wird:"
    echo "  - Alle Container fuer '${service}' stoppen"
    echo "  - Datenbanken droppen und neu importieren"
    echo "  - Datenverzeichnisse ersetzen"
    echo ""
    echo -n "Fortfahren? (yes/no): "
    read -r confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Abgebrochen."
        return 1
    fi

    echo ""

    # Step 1: Push restore data from NAS to server03
    echo ">>> NAS: Extracting and pushing backup data..."
    ssh nas "sudo -u recovery ${NAS_SCRIPT} server03 ${service} ${archive}"
    local push_rc=$?
    if [[ $push_rc -ne 0 ]]; then
        echo "FEHLER: restore-push auf NAS fehlgeschlagen (exit ${push_rc})"
        return 1
    fi

    # Step 2: Run restore on server03
    echo ""
    echo ">>> server03: Running restore..."
    ssh -t server03 "sudo restore --yes ${service}"
    local restore_rc=$?
    if [[ $restore_rc -ne 0 ]]; then
        echo "FEHLER: restore auf server03 fehlgeschlagen (exit ${restore_rc})"
        return 1
    fi

    echo ""
    echo "========================================"
    echo "  Restore von '${service}' abgeschlossen"
    echo "========================================"
}
