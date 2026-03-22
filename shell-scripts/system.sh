# macOS Apps und CLI-Tools auditieren (Homebrew vs. manuell vs. System)
app-audit() {
  if [[ "$1" == "-h" ]]; then
      echo "macOS Apps und CLI-Tools auditieren (Homebrew vs. manuell vs. System)"
      echo "Usage: app-audit [--csv]"
      echo "  --csv  Exportiert Ergebnisse als CSV-Datei"
      echo "Example: app-audit"
      echo "         app-audit --csv"
      return 0
  fi

  if ! command -v brew &>/dev/null; then
      echo "Fehler: Homebrew ist nicht installiert"
      return 1
  fi

  # ── Farben ──
  local GREEN='\033[0;32m' YELLOW='\033[0;33m' BLUE='\033[0;34m'
  local CYAN='\033[0;36m' MAGENTA='\033[0;35m' NC='\033[0m'

  echo "Sammle Daten... (kann beim ersten Lauf etwas dauern)"

  # ══════════════════════════════════════════════════════════
  # 1) macOS Tahoe 26 Standard-Apps (Applications + Utilities)
  # ══════════════════════════════════════════════════════════
  local -A macos_default=(
    # ── /Applications ──
    ["App Store.app"]=1
    ["Automator.app"]=1
    ["Books.app"]=1
    ["Calculator.app"]=1
    ["Calendar.app"]=1
    ["Chess.app"]=1
    ["Clock.app"]=1
    ["Contacts.app"]=1
    ["Dictionary.app"]=1
    ["FaceTime.app"]=1
    ["Find My.app"]=1
    ["Font Book.app"]=1
    ["Freeform.app"]=1
    ["Home.app"]=1
    ["Image Capture.app"]=1
    ["Invitations.app"]=1
    ["Mail.app"]=1
    ["Maps.app"]=1
    ["Messages.app"]=1
    ["Mission Control.app"]=1
    ["Music.app"]=1
    ["News.app"]=1
    ["Notes.app"]=1
    ["Passwords.app"]=1
    ["Phone.app"]=1
    ["Photo Booth.app"]=1
    ["Photos.app"]=1
    ["Podcasts.app"]=1
    ["Preview.app"]=1
    ["QuickTime Player.app"]=1
    ["Reminders.app"]=1
    ["Safari.app"]=1
    ["Shortcuts.app"]=1
    ["Siri.app"]=1
    ["Stickies.app"]=1
    ["Stocks.app"]=1
    ["System Settings.app"]=1
    ["TextEdit.app"]=1
    ["Time Machine.app"]=1
    ["Tips.app"]=1
    ["TV.app"]=1
    ["Voice Memos.app"]=1
    ["Weather.app"]=1
    # ── /Applications/Utilities ──
    ["Activity Monitor.app"]=1
    ["AirPort Utility.app"]=1
    ["Audio MIDI Setup.app"]=1
    ["Bluetooth File Exchange.app"]=1
    ["ColorSync Utility.app"]=1
    ["Console.app"]=1
    ["Digital Color Meter.app"]=1
    ["Disk Utility.app"]=1
    ["Grapher.app"]=1
    ["Keychain Access.app"]=1
    ["Migration Assistant.app"]=1
    ["Screenshot.app"]=1
    ["Script Editor.app"]=1
    ["System Information.app"]=1
    ["Terminal.app"]=1
    ["VoiceOver Utility.app"]=1
    # ── iWork / iLife (vorinstalliert auf neuen Macs) ──
    ["Keynote.app"]=1
    ["Numbers.app"]=1
    ["Pages.app"]=1
    ["GarageBand.app"]=1
    ["iMovie.app"]=1
  )

  # ══════════════════════════════════════════════════════════
  # 2) Homebrew Casks → App-Pfad-Mapping
  # ══════════════════════════════════════════════════════════
  local -A brew_cask_map=()   # app_name.app → cask_name
  local -a cask_list=()
  while IFS= read -r cask; do
    [[ -z "$cask" ]] && continue
    cask_list+=("$cask")
  done < <(brew list --cask 2>/dev/null)

  # Cask-Artifakte aus dem Caskroom lesen (schneller als brew info)
  local caskroom="$(brew --prefix)/Caskroom"

  local -a unresolved_casks=()
  for cask in "${cask_list[@]}"; do
    local -a vdirs=("$caskroom/$cask"/*(N/))
    local vdir="${vdirs[1]:-}"
    local cask_found=0
    if [[ -n "$vdir" ]]; then
      for app in "$vdir"/*.app(N) ; do
        brew_cask_map[$(basename "$app")]="$cask"
        cask_found=1
      done
    fi
    (( cask_found )) || unresolved_casks+=("$cask")
  done

  # Fallback: unaufgelöste Casks via brew info abfragen (ein Aufruf für alle)
  if (( ${#unresolved_casks[@]} > 0 )); then
    local current_cask=""
    while IFS= read -r line; do
      if [[ "$line" == "==> "* && "$line" == *": "* ]]; then
        local rest="${line#==> }"
        local maybe_cask="${rest%%:*}"
        [[ "$maybe_cask" != *" "* ]] && current_cask="$maybe_cask"
      elif [[ -n "$current_cask" && "$line" == *".app (App)"* ]]; then
        local app_name="${line%.app*}.app"
        app_name="${app_name#"${app_name%%[![:space:]]*}"}"
        brew_cask_map[$app_name]="$current_cask"
        current_cask=""
      fi
    done < <(brew info --cask "${unresolved_casks[@]}" 2>/dev/null)
  fi

  # Cask-Namen als Set für Namens-Matching (PKG-basierte Casks)
  local -A cask_set=()
  for cask in "${cask_list[@]}"; do
    cask_set[$cask]=1
  done

  # ══════════════════════════════════════════════════════════
  # 3) Homebrew Formulae
  # ══════════════════════════════════════════════════════════
  local -A brew_formulae=()
  while IFS= read -r formula; do
    [[ -n "$formula" ]] && brew_formulae["$formula"]=1
  done < <(brew list --formula 2>/dev/null)

  # ══════════════════════════════════════════════════════════
  # 4) CLI-Tools: System vs. Homebrew
  # ══════════════════════════════════════════════════════════
  local -A system_cli=(
    [git]=1 [ssh]=1 [curl]=1 [python3]=1 [ruby]=1 [perl]=1
    [swift]=1 [clang]=1 [make]=1 [vim]=1 [nano]=1 [zip]=1
    [unzip]=1 [tar]=1 [rsync]=1 [awk]=1 [sed]=1 [grep]=1
    [top]=1 [ps]=1 [ls]=1 [cp]=1 [mv]=1 [rm]=1 [cat]=1
    [zsh]=1 [bash]=1 [open]=1 [pbcopy]=1 [pbpaste]=1
    [networksetup]=1 [scutil]=1 [defaults]=1 [softwareupdate]=1
    [xcode-select]=1 [instruments]=1 [ditto]=1 [hdiutil]=1
    [diskutil]=1 [tmutil]=1 [caffeinate]=1 [say]=1 [afplay]=1
    [screencapture]=1 [sips]=1 [mdls]=1 [mdfind]=1 [plutil]=1
    [codesign]=1 [security]=1 [profiles]=1 [launchctl]=1
  )

  # ══════════════════════════════════════════════════════════
  # 5) Ausgabe: GUI-Apps
  # ══════════════════════════════════════════════════════════
  local total_gui=0 brew_gui=0 manual_gui=0 macos_gui=0

  printf "\n${MAGENTA}═══ GUI-APPS (/Applications) ═══${NC}\n\n"
  printf "${CYAN}%-40s %-15s %-30s${NC}\n" "APP" "STATUS" "DETAILS"
  printf '%.0s─' {1..85}; echo

  local output_gui=""
  for app_path in /Applications/*.app(N) /Applications/Utilities/*.app(N); do
    [[ -e "$app_path" ]] || continue
    local app_name=$(basename "$app_path")
    local display_name="${app_name%.app}"
    ((total_gui++))

    # Namens-Matching für PKG-basierte Casks (z.B. nordvpn, veracrypt)
    local normalized="${display_name:l}"
    normalized="${normalized// /-}"
    local matched_cask=""
    if [[ -n "${brew_cask_map[$app_name]+x}" ]]; then
      matched_cask="${brew_cask_map[$app_name]}"
    elif [[ -n "${cask_set[$normalized]+x}" ]]; then
      matched_cask="$normalized"
    fi

    if [[ -n "$matched_cask" ]]; then
      output_gui+=$(printf "%-40s ${GREEN}%-15s${NC} %-30s\n" \
        "$display_name" "✅ Homebrew" "cask: $matched_cask")
      output_gui+=$'\n'
      ((brew_gui++))
    elif [[ -n "${macos_default[$app_name]+x}" ]]; then
      output_gui+=$(printf "%-40s ${BLUE}%-15s${NC} %-30s\n" \
        "$display_name" "🍎 macOS" "vorinstalliert")
      output_gui+=$'\n'
      ((macos_gui++))
    else
      output_gui+=$(printf "%-40s ${YELLOW}%-15s${NC} %-30s\n" \
        "$display_name" "⚠️  Manuell" "nicht via Brew verwaltet")
      output_gui+=$'\n'
      ((manual_gui++))
    fi
  done
  echo "$output_gui" | sort

  printf '%.0s─' {1..85}; echo
  printf "GUI gesamt: %d | ${GREEN}Homebrew: %d${NC} | ${BLUE}macOS: %d${NC} | ${YELLOW}Manuell: %d${NC}\n" \
    "$total_gui" "$brew_gui" "$macos_gui" "$manual_gui"

  # ══════════════════════════════════════════════════════════
  # 6) Ausgabe: CLI-Tools (Homebrew Formulae)
  # ══════════════════════════════════════════════════════════
  local total_cli=0 brew_cli=0 system_cli_count=0 both_count=0

  printf "\n${MAGENTA}═══ CLI-TOOLS (Homebrew Formulae + System) ═══${NC}\n\n"
  printf "${CYAN}%-30s %-15s %-40s${NC}\n" "TOOL" "STATUS" "DETAILS"
  printf '%.0s─' {1..85}; echo

  local output_cli=""

  # Alle Homebrew-Formulae auflisten
  for formula in "${(@k)brew_formulae}"; do
    ((total_cli++))
    local brew_path=""
    brew_path=$(brew --prefix 2>/dev/null)/bin/$formula

    if [[ -n "${system_cli[$formula]+x}" ]]; then
      output_cli+=$(printf "%-30s ${GREEN}%-15s${NC} %-40s\n" \
        "$formula" "🔀 Beide" "brew + system (brew hat Vorrang)")
      output_cli+=$'\n'
      ((both_count++))
    else
      output_cli+=$(printf "%-30s ${GREEN}%-15s${NC} %-40s\n" \
        "$formula" "✅ Homebrew" "formula")
      output_cli+=$'\n'
      ((brew_cli++))
    fi
  done

  # System-CLI-Tools die NICHT in Homebrew sind
  for cmd in "${(@k)system_cli}"; do
    if [[ -z "${brew_formulae[$cmd]+x}" ]] && command -v "$cmd" &>/dev/null; then
      ((total_cli++))
      local cmd_path=$(command -v "$cmd")
      output_cli+=$(printf "%-30s ${BLUE}%-15s${NC} %-40s\n" \
        "$cmd" "🍎 System" "$cmd_path")
      output_cli+=$'\n'
      ((system_cli_count++))
    fi
  done
  echo "$output_cli" | sort

  printf '%.0s─' {1..85}; echo
  printf "CLI gesamt: %d | ${GREEN}Homebrew: %d${NC} | ${GREEN}Beide: %d${NC} | ${BLUE}System: %d${NC}\n" \
    "$total_cli" "$brew_cli" "$both_count" "$system_cli_count"

  # ══════════════════════════════════════════════════════════
  # 7) Zusammenfassung + Tipps
  # ══════════════════════════════════════════════════════════
  printf "\n${MAGENTA}═══ ZUSAMMENFASSUNG ═══${NC}\n\n"
  printf "GUI-Apps:  %d total (%d Homebrew, %d macOS, %d manuell)\n" \
    "$total_gui" "$brew_gui" "$macos_gui" "$manual_gui"
  printf "CLI-Tools: %d total (%d Homebrew, %d beide, %d nur System)\n\n" \
    "$total_cli" "$brew_cli" "$both_count" "$system_cli_count"

  if ((manual_gui > 0)); then
    echo "💡 Manuell installierte GUI-Apps zu Homebrew migrieren:"
    echo "   1. App deinstallieren"
    echo "   2. brew search <name>       (Cask-Namen finden)"
    echo "   3. brew install --cask <name>"
    echo ""
    echo "   Oder direkt prüfen ob ein Cask existiert:"
    echo "   brew info --cask <name>"
    echo ""
  fi

  # Optional: Exportierbare Liste
  if [[ "$1" == "--csv" ]]; then
    local csv_file="$HOME/app-audit-$(date +%Y%m%d).csv"
    echo "Name,Typ,Status,Details" > "$csv_file"
    for app_path in /Applications/*.app(N) /Applications/Utilities/*.app(N); do
      [[ -e "$app_path" ]] || continue
      local app_name=$(basename "$app_path")
      local display_name="${app_name%.app}"
      local normalized="${display_name:l}"
      normalized="${normalized// /-}"
      local matched_cask=""
      if [[ -n "${brew_cask_map[$app_name]+x}" ]]; then
        matched_cask="${brew_cask_map[$app_name]}"
      elif [[ -n "${cask_set[$normalized]+x}" ]]; then
        matched_cask="$normalized"
      fi
      if [[ -n "$matched_cask" ]]; then
        echo "$display_name,GUI,Homebrew,cask:$matched_cask" >> "$csv_file"
      elif [[ -n "${macos_default[$app_name]+x}" ]]; then
        echo "$display_name,GUI,macOS,vorinstalliert" >> "$csv_file"
      else
        echo "$display_name,GUI,Manuell," >> "$csv_file"
      fi
    done
    for formula in "${(@k)brew_formulae}"; do
      echo "$formula,CLI,Homebrew,formula" >> "$csv_file"
    done
    echo "📄 CSV exportiert: $csv_file"
  fi
}
