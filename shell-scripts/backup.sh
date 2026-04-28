# Manually trigger backup for a service on server03
backup() {
    if [[ "${1:-}" == "-h" ]] || [[ -z "${1:-}" ]]; then
        echo "Manually trigger backup for a service on server03"
        echo "Usage: backup <service>"
        echo "       backup --list"
        echo ""
        echo "  --list       List available backup-staging services on server03"
        echo "  <service>    Service to backup (e.g. briefkasten)"
        echo ""
        echo "Example: backup briefkasten"
        echo "         backup --list"
        [[ -z "${1:-}" ]] && return 1 || return 0
    fi

    # List mode
    if [[ "$1" == "--list" ]] || [[ "$1" == "-l" ]]; then
        echo "Fetching backup-staging services from server03..."
        ssh server03 "systemctl list-unit-files 'backup-staging-*.service' --no-legend | awk '{print \$1}' | sed 's/backup-staging-//;s/\.service//'"
        return $?
    fi

    local service="$1"
    local unit="backup-staging-${service}.service"

    # Check unit exists on server03
    echo "Checking unit ${unit} on server03..."
    if ! ssh server03 "systemctl list-unit-files '${unit}' --no-legend" | grep -q "${unit}"; then
        echo "FEHLER: Unit '${unit}' existiert nicht auf server03"
        echo ""
        echo "Verfuegbare Services:"
        backup --list
        return 1
    fi

    # Confirmation prompt
    echo ""
    echo "========================================"
    echo "  Backup von '${service}'"
    echo "========================================"
    echo ""
    echo "Dies wird:"
    echo "  - Staging auf server03 ausfuehren (${unit})"
    echo "  - Pull von NAS ausloesen (backup-pull-server03.service)"
    echo ""
    echo -n "Fortfahren? (yes/no): "
    read -r confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Abgebrochen."
        return 1
    fi

    echo ""

    # Step 1: Run staging on server03
    echo ">>> server03: Running backup staging..."
    ssh -t server03 "sudo systemctl start ${unit}"
    local staging_rc=$?
    if [[ $staging_rc -ne 0 ]]; then
        echo "FEHLER: Staging auf server03 fehlgeschlagen (exit ${staging_rc})"
        return 1
    fi
    echo "    Staging abgeschlossen."

    # Step 2: Pull from NAS
    echo ""
    echo ">>> NAS: Pulling backup from server03..."
    ssh nas "sudo systemctl start backup-pull-server03.service"
    local pull_rc=$?
    if [[ $pull_rc -ne 0 ]]; then
        echo "FEHLER: Pull auf NAS fehlgeschlagen (exit ${pull_rc})"
        return 1
    fi
    echo "    Pull abgeschlossen."

    echo ""
    echo "========================================"
    echo "  Backup von '${service}' abgeschlossen"
    echo "========================================"
}
