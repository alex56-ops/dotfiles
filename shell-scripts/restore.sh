# Restore a service on server03 from NAS backup
restore() {
    if [[ "${1:-}" == "-h" ]] || [[ -z "${1:-}" ]]; then
        echo "Restore a service on server03 from NAS backup"
        echo "Usage: restore <service> [archive]"
        echo "       restore list [service]"
        echo "       restore -local <service> [archive]"
        echo ""
        echo "  list               List available services on NAS"
        echo "  list <service>     List archives for a service"
        echo "  -local <service>   Restore locally as Docker container"
        echo "  <service>          Service to restore (e.g. briefkasten)"
        echo "  [archive]          Specific archive name (default: latest)"
        echo ""
        echo "Example: restore briefkasten"
        echo "         restore list"
        echo "         restore list briefkasten"
        echo "         restore -local briefkasten"
        [[ -z "${1:-}" ]] && return 1 || return 0
    fi

    local NAS_SCRIPT="/mnt/backup/recovery/scripts/restore-push.sh"

    # List mode
    if [[ "$1" == "--list" ]] || [[ "$1" == "list" ]] || [[ "$1" == "-l" ]]; then
        local filter="${2:-}"
        if [[ -n "$filter" ]]; then
            echo "Fetching archives for '${filter}'..."
            ssh nas "sudo -u recovery ${NAS_SCRIPT} --list server03 ${filter}"
        else
            echo "Fetching services from NAS..."
            ssh nas "sudo -u recovery ${NAS_SCRIPT} --list server03"
        fi
        return $?
    fi

    # Local restore mode
    if [[ "$1" == "-local" ]]; then
        _restore_local "$2" "${3:-}"
        return $?
    fi

    local service="$1"
    local archive="${2:-}"

    # Show available services on NAS
    echo "Checking available services on NAS..."
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

# Local restore: extract from NAS, run as Docker container locally
_restore_local() {
    local service="${1:?Service required}"
    local archive="${2:-}"
    local NAS_SCRIPT="/mnt/backup/recovery/scripts/restore-push.sh"
    local restore_dir="${HOME}/.restore/${service}"

    # Abort if directory exists
    if [[ -d "$restore_dir" ]]; then
        echo "Verzeichnis ${restore_dir} existiert bereits."
        echo -n "Ueberschreiben? (yes/no): "
        read -r confirm
        if [[ "$confirm" != "yes" ]]; then
            echo "Abgebrochen."
            return 1
        fi
        # Stop running containers if compose file exists
        if [[ -f "${restore_dir}/docker-compose.yml" ]]; then
            echo ">>> Stoppe laufende Container..."
            docker-compose -f "${restore_dir}/docker-compose.yml" down -v 2>/dev/null || true
        fi
        rm -rf "$restore_dir"
    fi

    mkdir -p "$restore_dir"

    # Step 1: Extract on NAS (no push)
    echo ">>> NAS: Extracting backup data..."
    local extract_output
    extract_output=$(ssh nas "sudo -u recovery ${NAS_SCRIPT} --extract-only server03 ${service} ${archive}")
    local extract_rc=$?
    if [[ $extract_rc -ne 0 ]]; then
        echo "FEHLER: Extraktion auf NAS fehlgeschlagen (exit ${extract_rc})"
        return 1
    fi
    echo "$extract_output"

    # Step 2: rsync from NAS to local
    echo ""
    echo ">>> Syncing data from NAS..."
    rsync -avz "nas:/mnt/backup/recovery/extract/${service}/" "${restore_dir}/"
    if [[ $? -ne 0 ]]; then
        echo "FEHLER: rsync fehlgeschlagen"
        return 1
    fi

    # Step 3: Cleanup extract dir on NAS
    echo ""
    echo ">>> NAS: Cleaning up extract directory..."
    ssh nas "sudo -u recovery rm -rf /mnt/backup/recovery/extract"

    # Step 4: Adapt compose file for local use
    if [[ -f "${restore_dir}/docker-compose.yml" ]]; then
        echo ">>> Passe docker-compose.yml fuer lokalen Betrieb an..."
        python3 -c "
import sys, re

def adapt_compose(lines):
    result = []
    skip = False
    skip_indent = 0
    port_added = False

    for line in lines:
        stripped = line.rstrip('\n')
        content = stripped.lstrip()
        indent = len(stripped) - len(content)

        if skip:
            if content == '' or indent > skip_indent:
                continue
            skip = False

        # Skip top-level 'networks:' block
        if indent == 0 and content.startswith('networks:'):
            skip = True
            skip_indent = indent
            continue

        # Skip per-service 'networks:', 'extra_hosts:', 'depends_on:' blocks
        if indent > 0 and content in ('networks:', 'extra_hosts:', 'depends_on:'):
            skip = True
            skip_indent = indent
            continue

        # Detect healthcheck port and add port mapping before it
        if not port_added and content.startswith('healthcheck:'):
            # Search backwards for port in previous lines (healthcheck test)
            # or search forward — we'll scan all lines separately
            pass

        result.append(line)

    # Find app port from healthcheck URL in result
    app_port = None
    for line in result:
        m = re.search(r'localhost:(\d+)', line)
        if m:
            port = m.group(1)
            # Skip postgres default port
            if port != '5432':
                app_port = port
                break

    # Add port mapping to first service with detected port
    if app_port:
        final = []
        added = False
        for line in result:
            final.append(line)
            if not added and line.strip().startswith('restart:'):
                # Find indentation of restart line
                spc = len(line) - len(line.lstrip())
                final.append(' ' * spc + 'ports:\n')
                final.append(' ' * spc + '  - \"8080:' + app_port + '\"\n')
                added = True
        result = final

    return result

with open(sys.argv[1], 'r') as f:
    lines = f.readlines()

result = adapt_compose(lines)

with open(sys.argv[1], 'w') as f:
    f.writelines(result)
" "${restore_dir}/docker-compose.yml"
    fi

    # Step 5: Start containers
    echo ""
    echo ">>> Starte Container..."
    docker-compose -f "${restore_dir}/docker-compose.yml" up -d
    if [[ $? -ne 0 ]]; then
        echo "FEHLER: docker-compose up fehlgeschlagen"
        return 1
    fi

    # Step 6: DB import for each .sql.gz dump
    local has_dumps=false
    for dump in "${restore_dir}"/*.sql.gz; do
        [[ -f "$dump" ]] || continue
        has_dumps=true
        local container
        container=$(basename "$dump" .sql.gz)
        echo ""
        echo ">>> Importiere Datenbank in Container '${container}'..."

        # Wait for postgres to be ready
        echo "    Warte auf PostgreSQL..."
        local retries=0
        while ! docker exec "$container" pg_isready -q 2>/dev/null; do
            retries=$((retries + 1))
            if [[ $retries -ge 30 ]]; then
                echo "FEHLER: PostgreSQL in '${container}' nicht bereit nach 30s"
                return 1
            fi
            sleep 1
        done

        # Read credentials from container environment
        local pg_user pg_db
        pg_user=$(docker exec "$container" sh -c 'echo $POSTGRES_USER')
        pg_db=$(docker exec "$container" sh -c 'echo $POSTGRES_DB')

        if [[ -z "$pg_user" ]] || [[ -z "$pg_db" ]]; then
            echo "FEHLER: POSTGRES_USER oder POSTGRES_DB nicht gesetzt in '${container}'"
            return 1
        fi

        echo "    DB: ${pg_db}, User: ${pg_user}"
        docker exec "$container" dropdb --if-exists -U "$pg_user" "$pg_db"
        docker exec "$container" createdb -U "$pg_user" "$pg_db"
        gunzip -c "$dump" | docker exec -i "$container" psql -U "$pg_user" -d "$pg_db" -q

        echo "    Import abgeschlossen."
    done

    # Step 7: Restart containers so apps see DB changes
    if $has_dumps; then
        echo ""
        echo ">>> Restart Container (DB-Aenderungen uebernehmen)..."
        docker-compose -f "${restore_dir}/docker-compose.yml" restart
    fi

    # Step 8: Show status
    echo ""
    echo "========================================"
    echo "  Lokaler Restore von '${service}' abgeschlossen"
    echo "========================================"
    echo ""
    docker-compose -f "${restore_dir}/docker-compose.yml" ps
    echo ""
    # Show URL if port mapping was added
    if grep -q '8080:' "${restore_dir}/docker-compose.yml" 2>/dev/null; then
        echo "Anwendung: http://localhost:8080"
        echo ""
    fi
    echo "Stoppen mit: cd ~/.restore/${service} && docker-compose down -v"
}
