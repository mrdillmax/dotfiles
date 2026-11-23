#!/usr/bin/env bash
# Manage the applications started by Hyprland.
#
# Entries live in ~/.local/state/dotfiles/autostart.tsv:
#   <enabled 0|1><TAB><name><TAB><command>
# The file is seeded from the defaults below on the first `run`. Hyprland calls
# `autostart.sh run` from its start handler, so disabling an entry here keeps it
# off at the next login without editing hyprland.lua.
#
# Only this state file is written. The compositor config and running processes
# are never touched.
set -uo pipefail

REAL_HOME="${HOME:?HOME is not set}"
STATE_DIR="${XDG_STATE_HOME:-$REAL_HOME/.local/state}/dotfiles"
STATE_FILE="$STATE_DIR/autostart.tsv"
LOG_FILE="$STATE_DIR/autostart.log"
SELF="$(readlink -f -- "${BASH_SOURCE[0]}")"

DRY_RUN=0
COMMAND=""

# Seeded on the first run. Keep in sync with the old hyprland.lua start block.
DEFAULTS=(
    "waybar|uwsm app -- waybar"
    "dunst|uwsm app -- dunst"
    "awww-daemon|uwsm app -- awww-daemon"
    "hyprpolkitagent|uwsm app -- env QT_QUICK_BACKEND=software /usr/lib/hyprpolkitagent/hyprpolkitagent"
    "cliphist-text|uwsm app -- wl-paste --type text --watch cliphist store"
    "cliphist-image|uwsm app -- wl-paste --type image --watch cliphist store"
    "wl-clip-persist|uwsm app -- wl-clip-persist --clipboard regular"
    "per-window-layout|uwsm app -- hyprland-per-window-layout"
    "kbuildsycoca|uwsm app -- kbuildsycoca6 --noincremental"
    "kopia-ui|uwsm app -- /opt/KopiaUI/kopia-ui"
    "monitor-profiles|monitor-profiles.sh watch"
    "hypridle|uwsm app -- idle-tune.sh run"
    "vesktop|uwsm app -- vesktop"
    "obsidian|uwsm app -- obsidian"
    "firefox|uwsm app -- firefox"
    "steam|uwsm app -- steam -silent"
)

usage() {
    cat <<'EOF'
Usage: autostart.sh <list|status|enable NAME|disable NAME|toggle NAME|
                    add NAME COMMAND|remove NAME|run|reset|pick> [--dry-run]

  list            show every entry and whether it starts
  enable NAME     start NAME at the next login
  disable NAME    keep NAME off at the next login
  toggle NAME     flip the state of NAME
  add NAME CMD    add a new entry (starts at the next login)
  remove NAME     delete an entry
  run             start the enabled entries (used by Hyprland at login)
  reset           restore the built-in list, all enabled
  pick            interactive toggle menu (rofi/gum/whiptail/dialog/plain)
  add-fzf         add a desktop app or custom command through fzf (terminal)
  remove-fzf      remove entries through fzf (terminal)

Options:
  --dry-run       print what would change; do not write or start anything

State: ~/.local/state/dotfiles/autostart.tsv
Log:   ~/.local/state/dotfiles/autostart.log
EOF
}

die() { printf 'autostart: %s\n' "$*" >&2; exit 1; }
info() { printf ':: %s\n' "$*"; }
ok() { printf 'ok %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

notify_msg() {
    if command -v dunstify >/dev/null 2>&1; then
        dunstify -a "Autostart" "$1" >/dev/null 2>&1 || true
    elif command -v notify-send >/dev/null 2>&1; then
        notify-send "Autostart" "$1" >/dev/null 2>&1 || true
    else
        printf '%s\n' "$1" >&2
    fi
}

have_tty() { [[ -t 0 ]]; }

# fzf needs a terminal. The picker itself stays in rofi; only add/remove
# spawn this floating terminal, and it blocks until the user closes it.
run_in_terminal_wait() {
    local command="$1" workdir
    workdir="$(printf '%q' "$REAL_HOME")"
    if command -v kitty >/dev/null 2>&1; then
        kitty --class dotfiles-control-center -e bash -lc "cd $workdir && $command"
    elif command -v x-terminal-emulator >/dev/null 2>&1; then
        x-terminal-emulator -e bash -lc "cd $workdir && $command"
    else
        notify_msg "No terminal found for the fzf picker"
        return 1
    fi
}

valid_name() {
    [[ $1 =~ ^[A-Za-z0-9_.-]+$ ]]
}

valid_command() {
    [[ -n $1 && $1 != *$'\t'* && $1 != *$'\n'* && $1 != *$'\r'* ]]
}

# Fills ENTRIES=("enabled<TAB>name<TAB>command") from the state file, or from
# the defaults when the file does not exist yet.
load_entries() {
    local line enabled name cmd
    ENTRIES=()

    if [[ -r $STATE_FILE ]]; then
        while IFS=$'\t' read -r enabled name cmd; do
            [[ -z $enabled || $enabled == \#* ]] && continue
            if [[ $enabled != 0 && $enabled != 1 ]] || ! valid_name "$name" \
                || ! valid_command "$cmd"; then
                warn "ignoring malformed line in $STATE_FILE: $enabled $name $cmd"
                continue
            fi
            ENTRIES+=("$(printf '%s\t%s\t%s' "$enabled" "$name" "$cmd")")
        done <"$STATE_FILE"
        return 0
    fi

    for line in "${DEFAULTS[@]}"; do
        name="${line%%|*}"
        cmd="${line#*|}"
        ENTRIES+=("$(printf '1\t%s\t%s' "$name" "$cmd")")
    done
}

save_entries() {
    local tmp

    if ((DRY_RUN)); then
        info "[dry-run] would write $STATE_FILE"
        return 0
    fi

    mkdir -p -- "$STATE_DIR"
    tmp="$(mktemp)"
    {
        printf '# Managed by autostart.sh: <enabled>\t<name>\t<command>\n'
        printf '%s\n' "${ENTRIES[@]}"
    } >"$tmp"
    chmod 0644 "$tmp"
    mv -f -- "$tmp" "$STATE_FILE"
}

entry_index() {
    local wanted="$1" i enabled name
    for i in "${!ENTRIES[@]}"; do
        IFS=$'\t' read -r enabled name _ <<<"${ENTRIES[$i]}"
        if [[ $name == "$wanted" ]]; then
            printf '%s' "$i"
            return 0
        fi
    done
    return 1
}

# Sets ENTRY_INDEX instead of printing it, so die() runs in this shell.
require_entry() {
    ENTRY_INDEX="$(entry_index "$1")" || die "unknown entry: $1 (see list)"
}

set_enabled() {
    local name="$1" value="$2" enabled _cmd
    load_entries
    require_entry "$name"
    IFS=$'\t' read -r _ name _cmd <<<"${ENTRIES[$ENTRY_INDEX]}"

    if ((DRY_RUN)); then
        info "[dry-run] would set $name enabled=$value"
        return 0
    fi

    ENTRIES[ENTRY_INDEX]="$(printf '%s\t%s\t%s' "$value" "$name" "$_cmd")"
    save_entries
    if [[ $value == 1 ]]; then
        ok "$name will start at the next login"
    else
        ok "$name will not start at the next login"
    fi
}

show_list() {
    local line enabled name cmd state
    load_entries

    if ((${#ENTRIES[@]} == 0)); then
        printf 'no autostart entries\n'
        return 0
    fi

    for line in "${ENTRIES[@]}"; do
        IFS=$'\t' read -r enabled name cmd <<<"$line"
        if [[ $enabled == 1 ]]; then state='[x]'; else state='[ ]'; fi
        local missing=''
        entry_command_available "$cmd" || missing=' (not installed)'
        printf '%s %-20s %s%s\n' "$state" "$name" "$cmd" "$missing"
    done
}

show_status() {
    local line enabled name _cmd on=0 off=0
    load_entries

    for line in "${ENTRIES[@]}"; do
        IFS=$'\t' read -r enabled name _cmd <<<"$line"
        if [[ $enabled == 1 ]]; then on=$((on + 1)); else off=$((off + 1)); fi
    done

    printf 'state: %s%s\n' "$STATE_FILE" \
        "$([[ -r $STATE_FILE ]] && echo '' || echo ' (defaults, not written yet)')"
    printf 'log:   %s\n' "$LOG_FILE"
    printf 'entries: %d enabled, %d disabled\n' "$on" "$off"
}

add_entry() {
    local name="$1" cmd="$2" line enabled

    valid_name "$name" || die "invalid name: $name (use letters, digits, . _ -)"
    valid_command "$cmd" || die "the command must be non-empty and single-line"
    load_entries

    if entry_index "$name" >/dev/null; then
        die "an entry named $name already exists (remove it first)"
    fi

    if ((DRY_RUN)); then
        info "[dry-run] would add $name: $cmd"
        return 0
    fi

    ENTRIES+=("$(printf '1\t%s\t%s' "$name" "$cmd")")
    save_entries
    ok "added $name"
}

remove_entry() {
    local name="$1" i
    local -a kept=()
    require_entry "$name"

    if ((DRY_RUN)); then
        info "[dry-run] would remove $name"
        return 0
    fi

    for i in "${!ENTRIES[@]}"; do
        ((i == ENTRY_INDEX)) && continue
        kept+=("${ENTRIES[$i]}")
    done
    ENTRIES=("${kept[@]}")
    save_entries
    ok "removed $name"
}

reset_entries() {
    local line name cmd
    ENTRIES=()
    for line in "${DEFAULTS[@]}"; do
        name="${line%%|*}"
        cmd="${line#*|}"
        ENTRIES+=("$(printf '1\t%s\t%s' "$name" "$cmd")")
    done

    if ((DRY_RUN)); then
        info "[dry-run] would reset $STATE_FILE to ${#DEFAULTS[@]} entries"
        return 0
    fi
    save_entries
    ok "restored the default autostart list"
}

entry_command_available() {
    local cmd="$1" first
    cmd="${cmd#uwsm app -- }"
    read -r first _ <<<"$cmd"
    first="${first%\"}"
    first="${first#\"}"
    first="${first%\'}"
    first="${first#\'}"
    if [[ $first == /* ]]; then
        [[ -x $first ]]
    else
        command -v -- "$first" >/dev/null 2>&1
    fi
}

launch() {
    local name="$1" cmd="$2"

    info "start $name: $cmd"
    if command -v setsid >/dev/null 2>&1; then
        setsid sh -c "$cmd" >>"$LOG_FILE" 2>&1 &
    else
        sh -c "$cmd" >>"$LOG_FILE" 2>&1 &
    fi
}

# The polkit agent needs software rendering on GPU-less VMs, where Qt Quick
# otherwise crashes while creating a GBM buffer. Migrate the old command once.
migrate_entries() {
    local line enabled name cmd i changed=0
    load_entries
    for i in "${!ENTRIES[@]}"; do
        IFS=$'\t' read -r enabled name cmd <<<"${ENTRIES[$i]}"
        if [[ $name == hyprpolkitagent && $cmd == 'uwsm app -- /usr/lib/hyprpolkitagent/hyprpolkitagent' ]]; then
            ENTRIES[i]="$(printf '%s\t%s\t%s' "$enabled" "$name" \
                'uwsm app -- env QT_QUICK_BACKEND=software /usr/lib/hyprpolkitagent/hyprpolkitagent')"
            changed=1
        fi
    done
    ((changed)) && save_entries
}

run_entries() {
    # The optional greeter keeps the desktop behind hyprlock; do not launch
    # bars or apps until it is unlocked (the marker disappears with hyprlock).
    local greeter_marker="${XDG_RUNTIME_DIR:-/tmp}/dotfiles-greeter.lock"
    local greeter_config="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/greeter-on"
    # The Lua start handler creates the marker; give it a moment to win the race.
    if [[ -e $greeter_config ]]; then
        for _ in {1..20}; do
            [[ -e $greeter_marker ]] && break
            sleep 0.1
        done
    fi
    while [[ -e $greeter_marker ]]; do
        sleep 0.2
    done

    local line enabled name cmd started=0 failed=0 skipped=0

    migrate_entries
    load_entries
    if ((${#ENTRIES[@]} == 0)); then
        info "no autostart entries"
        return 0
    fi

    # With no state file yet, seed it so the defaults are visible in `list`
    # and can be disabled later.
    if [[ ! -r $STATE_FILE ]]; then
        save_entries
    fi

    if ((DRY_RUN)); then
        for line in "${ENTRIES[@]}"; do
            IFS=$'\t' read -r enabled name cmd <<<"$line"
            [[ $enabled == 1 ]] || continue
            if ! entry_command_available "$cmd"; then
                info "[dry-run] skip $name: command not found"
                skipped=$((skipped + 1))
                continue
            fi
            info "[dry-run] would start $name: $cmd"
            started=$((started + 1))
        done
        info "[dry-run] $started enabled entries ($skipped skipped)"
        return 0
    fi

    mkdir -p -- "$STATE_DIR"
    printf '=== autostart %s ===\n' "$(date '+%F %T')" >>"$LOG_FILE"
    for line in "${ENTRIES[@]}"; do
        IFS=$'\t' read -r enabled name cmd <<<"$line"
        [[ $enabled == 1 ]] || continue
        if ! entry_command_available "$cmd"; then
            info "skip $name: command not found"
            skipped=$((skipped + 1))
            continue
        fi
        launch "$name" "$cmd" || failed=$((failed + 1))
        started=$((started + 1))
    done

    ok "started $started enabled entries ($skipped skipped, log: $LOG_FILE)"
    ((failed == 0)) || warn "$failed entries could not be started"
}

# Free-text prompt for adding an entry.
ask_line() {
    local prompt="$1" value

    if command -v rofi >/dev/null 2>&1 \
        && [[ -n ${WAYLAND_DISPLAY:-} || -n ${DISPLAY:-} ]]; then
        value="$(printf '\n' | rofi -theme "$HOME/.config/rofi/launcher.rasi" \
            -dmenu -l 0 -p "" -no-fixed-num-lines \
            -theme-str "entry { placeholder: \"$prompt\"; }" 2>/dev/null)" || return 1
    elif command -v gum >/dev/null 2>&1; then
        value="$(gum input --prompt "$prompt: ")" || return 1
    elif [[ -t 0 ]]; then
        printf '%s: ' "$prompt"
        read -r value || return 1
    else
        return 1
    fi
    printf '%s\n' "$value"
}

# Interactive single-choice toggle loop.
choose_line() {
    local title="$1"
    shift
    local items=("$@")

    if command -v rofi >/dev/null 2>&1 \
        && [[ -n ${WAYLAND_DISPLAY:-} || -n ${DISPLAY:-} ]]; then
        printf '%s\n' "${items[@]}" | rofi -theme "$HOME/.config/rofi/launcher.rasi" -dmenu -i -p "" -no-fixed-num-lines \
            -theme-str "entry { placeholder: \"$title\"; }" 2>/dev/null
        return
    fi
    if command -v gum >/dev/null 2>&1; then
        printf '%s\n' "${items[@]}" | gum choose --header "$title"
        return
    fi
    if command -v whiptail >/dev/null 2>&1; then
        whiptail --title "$title" --menu "Toggle an entry" 0 0 0 \
            "${items[@]}" 3>&1 1>&2 2>&3
        return
    fi
    if command -v dialog >/dev/null 2>&1; then
        dialog --title "$title" --menu "Toggle an entry" 0 0 0 \
            "${items[@]}" 3>&1 1>&2 2>&3
        return
    fi
    [[ -t 0 ]] || die "pick needs a terminal or rofi/gum/whiptail/dialog"

    local i choice
    local -a menu=()
    for i in "${!items[@]}"; do
        menu+=("$((i + 1))" "${items[$i]}")
    done
    printf '%s\n' "${menu[@]}" >&2
    printf 'Toggle which entry (empty to close): '
    read -r choice || return 1
    [[ -n $choice ]] || return 1
    [[ $choice =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "${items[$((choice - 1))]}"
}

sanitize_name() {
    printf '%s' "$1" | sed 's/[^A-Za-z0-9_.-]/-/g'
}

# Installed desktop entries as id<TAB>name<TAB>command. The id keeps names
# unique and safe for the state file.
desktop_apps() {
    local dir file line id name exec nodisplay
    local -A seen=()

    for dir in /usr/share/applications "$REAL_HOME/.local/share/applications"; do
        [[ -d $dir ]] || continue
        while IFS= read -r file; do
            [[ -r $file ]] || continue
            id="$(basename "$file" .desktop)"
            [[ -n ${seen[$id]:-} ]] && continue
            seen[$id]=1
            name=""
            exec=""
            nodisplay=0
            while IFS= read -r line; do
                case "$line" in
                    Name=*) [[ -z $name ]] && name="${line#Name=}" ;;
                    Exec=*) [[ -z $exec ]] && exec="${line#Exec=}" ;;
                    NoDisplay=true|Hidden=true) nodisplay=1 ;;
                esac
            done <"$file"
            [[ $nodisplay == 1 || -z $name || -z $exec ]] && continue
            exec="${exec//%[fFuUdDnNickvm]/}"
            exec="$(printf '%s' "$exec" | sed 's/[[:space:]]*$//')"
            printf '%s\t%s\t%s\n' "$id" "$name" "$exec"
        done < <(find "$dir" -maxdepth 1 -name '*.desktop' -type f 2>/dev/null | sort)
    done
}

# Selects an application with fzf, or Command... for anything else. Prints
# name<TAB>command.
choose_program() {
    local -a rows=() names=() commands=()
    local id name exec selection i answer_name answer_command answer_name_input

    while IFS=$'\t' read -r id name exec; do
        [[ -n $id && -n $name && -n $exec ]] || continue
        names+=("$id")
        commands+=("uwsm app -- $exec")
        rows+=("$name  [$id]")
    done < <(desktop_apps)

    rows=("Command..." "${rows[@]}")
    names=("__command__" "${names[@]}")
    commands=("" "${commands[@]}")

    if command -v fzf >/dev/null 2>&1 && [[ -t 0 ]]; then
        selection="$(printf '%s\n' "${rows[@]}" | fzf --height=100% --reverse \
            --prompt='application> ' --header='Select a program or Command...')" || return 1
    else
        selection="$(choose_line "Run at login" "${rows[@]}")" || return 1
    fi
    [[ -n $selection ]] || return 1

    for i in "${!rows[@]}"; do
        [[ ${rows[$i]} == "$selection" ]] || continue
        if [[ ${names[$i]} == "__command__" ]]; then
            if have_tty; then
                printf 'Command: ' >&2
                read -r answer_command || return 1
                [[ -n $answer_command ]] || return 1
                answer_name="$(sanitize_name "$(basename -- "${answer_command%% *}")")"
                [[ -n $answer_name ]] || answer_name="custom"
                printf 'Name [%s]: ' "$answer_name" >&2
                read -r answer_name_input || return 1
                answer_name="${answer_name_input:-$answer_name}"
                answer_name="$(sanitize_name "$answer_name")"
            else
                answer_name="$(ask_line 'Program name')" || return 1
                [[ -n $answer_name ]] || return 1
                answer_name="$(sanitize_name "$answer_name")"
                answer_command="$(ask_line 'Command')" || return 1
                [[ -n $answer_command ]] || return 1
            fi
            printf '%s\t%s\n' "$answer_name" "$answer_command"
        else
            printf '%s\t%s\n' "${names[$i]}" "${commands[$i]}"
        fi
        return 0
    done
    return 1
}

# Add flow for a terminal: fzf picks an installed app, or Command... asks for
# an arbitrary command line. Esc leaves without changing anything.
add_fzf() {
    local picked new_name new_command
    if ! command -v fzf >/dev/null 2>&1; then
        notify_msg "fzf is not installed"
        return 0
    fi
    picked="$(choose_program)" || return 0
    IFS=$'\t' read -r new_name new_command <<<"$picked"
    [[ -n $new_name && -n $new_command ]] || return 0

    load_entries
    if entry_index "$new_name" >/dev/null 2>&1; then
        notify_msg "An entry named $new_name already exists"
        return 0
    fi
    add_entry "$new_name" "$new_command" || return 0
    notify_msg "Added $new_name"
}

# Remove flow for a terminal: fzf shows every entry, Tab selects several.
remove_fzf() {
    local line enabled name cmd state selected removed=0
    local -a rows=()

    if ! command -v fzf >/dev/null 2>&1; then
        notify_msg "fzf is not installed"
        return 0
    fi
    load_entries
    ((${#ENTRIES[@]})) || { notify_msg "Nothing to remove"; return 0; }

    for line in "${ENTRIES[@]}"; do
        IFS=$'\t' read -r enabled name cmd <<<"$line"
        if [[ $enabled == 1 ]]; then state='[x]'; else state='[ ]'; fi
        rows+=("$name"$'\t'"$state $name  —  $cmd")
    done

    selected="$(printf '%s\n' "${rows[@]}" | fzf --multi --height=100% \
        --reverse --border=rounded --info=inline --delimiter=$'\t' \
        --with-nth=2 --prompt='remove> ' \
        --header='Tab selects several, Enter removes')" || return 0
    [[ -n $selected ]] || return 0

    while IFS=$'\t' read -r name _; do
        [[ -n $name ]] || continue
        remove_entry "$name" || continue
        removed=$((removed + 1))
    done <<<"$selected"
    ((removed == 0)) || notify_msg "Removed $removed entr$([[ $removed == 1 ]] && echo y || echo ies)"
}

pick_entries() {
    local line enabled name _cmd labels=() choice chosen state

    migrate_entries
    load_entries
    while true; do
        labels=("+ Add a program" "- Remove a program")
        for line in "${ENTRIES[@]}"; do
            IFS=$'\t' read -r enabled name _cmd <<<"$line"
            if [[ $enabled == 1 ]]; then state='[x]'; else state='[ ]'; fi
            local missing=''
            entry_command_available "$_cmd" || missing=' (not installed)'
            labels+=("$state $name$missing")
        done

        choice="$(choose_line "Autostart (pick to toggle)" "${labels[@]}")" || return 0
        [[ -n $choice ]] || return 0
        if [[ $choice == '+ Add a program' ]]; then
            if have_tty; then
                add_fzf
            else
                run_in_terminal_wait "$(printf '%q' "$SELF") add-fzf"
            fi
            load_entries
            continue
        fi
        if [[ $choice == '- Remove a program' ]]; then
            if have_tty; then
                remove_fzf
            else
                run_in_terminal_wait "$(printf '%q' "$SELF") remove-fzf"
            fi
            load_entries
            continue
        fi
        chosen="${choice#\[?\] }"
        chosen="${chosen% (not installed)}"

        if ! index="$(entry_index "$chosen")"; then
            warn "unknown selection: $chosen"
            continue
        fi
        IFS=$'\t' read -r enabled _ cmd <<<"${ENTRIES[$index]}"

        if [[ $enabled == 0 ]] && ! entry_command_available "$cmd"; then
            warn "$chosen: command not found, not enabling"
            continue
        fi

        if [[ $enabled == 1 ]]; then
            set_enabled "$chosen" 0
        else
            set_enabled "$chosen" 1
        fi
        load_entries
    done
}

while (($#)); do
    case "$1" in
        list|status|run|reset|pick|add-fzf|remove-fzf)
            [[ -z $COMMAND ]] || die "only one command is allowed"
            COMMAND="$1"
            ;;
        enable|disable|toggle|remove)
            [[ -z $COMMAND ]] || die "only one command is allowed"
            COMMAND="$1"
            [[ -n ${2:-} ]] || die "$1 needs an entry name"
            NAME="$2"
            shift
            ;;
        add)
            [[ -z $COMMAND ]] || die "only one command is allowed"
            COMMAND="add"
            [[ -n ${2:-} && -n ${3:-} ]] || die "add needs a name and a command"
            NAME="$2"
            CMD="$3"
            shift 2
            ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

case "$COMMAND" in
    list)        show_list ;;
    status)      show_status ;;
    enable)      set_enabled "$NAME" 1 ;;
    disable)     set_enabled "$NAME" 0 ;;
    toggle)
        load_entries
        toggle_index="$(entry_index "$NAME")" || die "unknown entry: $NAME (see list)"
        IFS=$'\t' read -r enabled _ _ <<<"${ENTRIES[$toggle_index]}"
        if [[ $enabled == 1 ]]; then set_enabled "$NAME" 0; else set_enabled "$NAME" 1; fi
        ;;
    add)         add_entry "$NAME" "$CMD" ;;
    remove)      load_entries; remove_entry "$NAME" ;;
    reset)       reset_entries ;;
    run)         run_entries ;;
    pick)        pick_entries ;;
    add-fzf)     add_fzf ;;
    remove-fzf)  remove_fzf ;;
    "")          usage >&2; exit 2 ;;
esac
