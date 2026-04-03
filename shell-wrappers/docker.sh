# Start Colima automatically when running docker commands
# and track activity for auto-stop via launchd idle check
docker() {
    if ! colima status &>/dev/null; then
        echo "Colima is not running, starting..."
        colima start
    fi

    mkdir -p ~/.local/state/colima
    touch ~/.local/state/colima/last-activity

    command docker "$@"
}
