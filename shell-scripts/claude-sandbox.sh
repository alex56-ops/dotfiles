# Start Claude Code in a Docker sandbox with mounted host directories
sbx-claude() {
    if [[ "${1:-}" == "-h" ]]; then
        echo "Start Claude Code in a Docker sandbox"
        echo "Usage: sbx-claude [dir1] [dir2] ..."
        echo ""
        echo "  dir1, dir2, ...  Host directories to mount (default: current directory)"
        echo "  First directory becomes WORKDIR inside the container"
        echo ""
        echo "Mounts:"
        echo "  /tmp        → /tmp/host   (read-write)"
        echo "  ~/.claude   → /root/.claude (read-only, credentials)"
        echo ""
        echo "Example: sbx-claude ~/projects/myapp"
        echo "         sbx-claude ~/projects/myapp ~/data"
        return 0
    fi

    local -a input_dirs
    if [[ $# -eq 0 ]]; then
        input_dirs=("$(pwd)")
    else
        input_dirs=("$@")
    fi

    local -a docker_args
    local workdir=""
    local first=1

    for dir in "${input_dirs[@]}"; do
        local abs_dir
        abs_dir=$(realpath "$dir") || { echo "FEHLER: Verzeichnis nicht gefunden: $dir"; return 1; }
        if [[ ! -d "$abs_dir" ]]; then
            echo "FEHLER: Kein Verzeichnis: $abs_dir"
            return 1
        fi
        local bname
        bname=$(basename "$abs_dir")
        docker_args+=(-v "${abs_dir}:/workspace/${bname}")
        if [[ $first -eq 1 ]]; then
            workdir="/workspace/${bname}"
            first=0
        fi
    done

    docker_args+=(-v "/tmp:/tmp/host")
    docker_args+=(-v "${HOME}/.claude:/root/.claude:ro")

    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        docker_args+=(-e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}")
    fi

    echo "========================================"
    echo "  Claude Code Sandbox"
    echo "========================================"
    echo "  WORKDIR: ${workdir}"
    for dir in "${input_dirs[@]}"; do
        local abs_dir
        abs_dir=$(realpath "$dir")
        echo "  Gemountet: ${abs_dir} → /workspace/$(basename "$abs_dir")"
    done
    echo "  /tmp → /tmp/host"
    echo "========================================"
    echo ""

    docker run --rm -it \
        "${docker_args[@]}" \
        -w "${workdir}" \
        node:lts \
        sh -c 'npm install -g @anthropic-ai/claude-code --quiet && claude --dangerously-skip-permissions'
}

# Zsh completion: complete directories for all sbx-claude arguments
_sbx_claude() {
    _arguments '*:Verzeichnis:_files -/'
}
if (( $+functions[compdef] )); then
    compdef _sbx_claude sbx-claude
fi
