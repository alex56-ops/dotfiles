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
        done < <(grep -E "^[a-zA-Z_-]+\(\)" "$f")
    done

    echo ""
    echo "Use '<function> -h' for usage details."
}
