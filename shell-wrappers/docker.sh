# Start Colima automatically when running docker commands
docker() {
    if ! colima status &>/dev/null; then
        echo "Colima is not running, starting..."
        colima start
    fi

    command docker "$@"
}
