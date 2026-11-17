#!/usr/bin/env bash
# Lid switch handler for Hyprland laptops.
#
# closed: read `hyprctl monitors -j` immediately before acting.
#   - another active monitor exists -> disable every eDP/LVDS/DSI output and
#     remember its mode, position and scale in
#     ~/.local/state/dotfiles/lid.conf
#   - no other active monitor         -> suspend through systemctl
# open: always restore the internal panel from the saved state (or re-enable
#   it with preferred/auto when there is no saved state).
#
# logind configuration is never modified.
set -uo pipefail

REAL_HOME="${HOME:?HOME is not set}"
STATE_DIR="${XDG_STATE_HOME:-$REAL_HOME/.local/state}/dotfiles"
STATE_FILE="$STATE_DIR/lid.conf"
DRY_RUN=0
COMMAND=""

usage() {
    cat <<'EOF'
Usage: lid-handler.sh <closed|open|status> [--dry-run]

  closed   disable the internal panel when another monitor is active,
           otherwise suspend
  open     restore the internal panel
  status   show active monitors and the saved internal-panel state

Options:
  --dry-run   print the commands, change nothing (also skips suspend)

State: ~/.local/state/dotfiles/lid.conf
EOF
}

die() { printf 'lid-handler: %s\n' "$*" >&2; exit 1; }
info() { printf ':: %s\n' "$*"; }
ok() { printf 'ok %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

require_session() {
    command -v hyprctl >/dev/null 2>&1 || die "hyprctl is not installed"
    command -v jq >/dev/null 2>&1 || die "jq is not installed"
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] \
        || die "not inside a Hyprland session (HYPRLAND_INSTANCE_SIGNATURE is unset)"
}

lua_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

is_internal() {
    [[ $1 =~ ^(eDP|LVDS|DSI|DPI)- ]]
}

# Prints name<TAB>mode<TAB>position<TAB>scale for active monitors.
monitor_rows() {
    hyprctl monitors -j 2>/dev/null \
        | jq -r '.[] | [.name,
                        (if .width and .height and .refreshRate
                         then ((.width|tostring) + "x" + (.height|tostring) + "@" + (.refreshRate|round|tostring))
                         else "preferred" end),
                        ((.x|tostring) + "x" + (.y|tostring)),
                        (.scale|tostring)] | @tsv'
}

apply_monitor() {
    local name="$1" mode="$2" position="$3" scale="$4"
    local lua

    lua="hl.monitor({ output = \"$(lua_escape "$name")\", mode = \"$(lua_escape "$mode")\", position = \"$(lua_escape "$position")\", scale = $scale })"

    if ((DRY_RUN)); then
        info "[dry-run] hyprctl eval '$lua'"
        return 0
    fi
    hyprctl eval "$lua" >/dev/null 2>&1 || {
        warn "failed to apply monitor $name"
        return 1
    }
}

disable_monitor() {
    local name="$1" lua

    lua="hl.monitor({ output = \"$(lua_escape "$name")\", disabled = true })"

    if ((DRY_RUN)); then
        info "[dry-run] hyprctl eval '$lua'"
        return 0
    fi
    hyprctl eval "$lua" >/dev/null 2>&1 || {
        warn "failed to disable $name"
        return 1
    }
}

write_state() {
    local rows="$1" tmp

    if ((DRY_RUN)); then
        info "[dry-run] would write $STATE_FILE"
        return 0
    fi

    mkdir -p -- "$STATE_DIR"
    tmp="$(mktemp)"
    {
        printf '# Internal panel state captured when the lid was closed.\n'
        printf '# name\tmode\tposition\tscale\n'
        printf '%s\n' "$rows"
    } >"$tmp"
    chmod 0600 "$tmp"
    mv -f -- "$tmp" "$STATE_FILE"
}

read_state() {
    local name mode position scale

    [[ -r $STATE_FILE ]] || return 1
    while IFS=$'\t' read -r name mode position scale; do
        [[ -z $name || $name == \#* ]] && continue
        printf '%s\t%s\t%s\t%s\n' "$name" "$mode" "$position" "$scale"
    done <"$STATE_FILE"
}

suspend_now() {
    if ((DRY_RUN)); then
        info "[dry-run] systemctl suspend"
        return 0
    fi
    command -v systemctl >/dev/null 2>&1 || {
        warn "systemctl is not available; cannot suspend"
        return 1
    }
    info "no external monitor; suspending"
    systemctl suspend
}

handle_closed() {
    local rows row name mode position scale
    local -a internal=() external=() saved=()

    require_session

    mapfile -t rows < <(monitor_rows)
    for row in "${rows[@]}"; do
        [[ -n $row ]] || continue
        IFS=$'\t' read -r name mode position scale <<<"$row"
        if is_internal "$name"; then
            internal+=("$row")
        else
            external+=("$name")
        fi
    done

    if ((${#internal[@]} == 0)); then
        if ((${#external[@]} > 0)); then
            info "no internal panel detected; leaving ${#external[@]} external monitor(s) active"
            return 0
        fi
        suspend_now
        return $?
    fi

    if ((${#external[@]} == 0)); then
        suspend_now
        return $?
    fi

    for row in "${internal[@]}"; do
        IFS=$'\t' read -r name mode position scale <<<"$row"
        saved+=("$(printf '%s\t%s\t%s\t%s' "$name" "$mode" "$position" "$scale")")
    done

    write_state "$(printf '%s\n' "${saved[@]}")"

    for row in "${saved[@]}"; do
        IFS=$'\t' read -r name _ _ _ <<<"$row"
        disable_monitor "$name" || return 1
    done

    ((DRY_RUN)) || ok "disabled ${#internal[@]} internal panel(s); ${#external[@]} external stay active"
}

handle_open() {
    local name mode position scale

    require_session

    if [[ -r $STATE_FILE ]]; then
        while IFS=$'\t' read -r name mode position scale; do
            apply_monitor "$name" "$mode" "$position" "$scale" || return 1
        done < <(read_state)

        if ((DRY_RUN)); then
            info "[dry-run] would remove $STATE_FILE"
        else
            rm -f -- "$STATE_FILE"
        fi
        ((DRY_RUN)) || ok "internal panel restored from $STATE_FILE"
        return 0
    fi

    # No saved state: re-enable any disabled internal output with safe defaults.
    local -a disabled=()
    mapfile -t disabled < <(
        hyprctl monitors all -j 2>/dev/null \
            | jq -r '.[] | select(.disabled == true) | .name' 2>/dev/null \
            | while IFS= read -r name; do is_internal "$name" && printf '%s\n' "$name"; done
    )

    if ((${#disabled[@]} == 0)); then
        info "no saved state and no disabled internal panel; nothing to restore"
        return 0
    fi

    for name in "${disabled[@]}"; do
        apply_monitor "$name" "preferred" "auto" "auto" || return 1
    done
    ((DRY_RUN)) || ok "re-enabled ${#disabled[@]} internal panel(s) with auto settings"
}

show_status() {
    local row name mode position scale

    printf 'state: %s%s\n' "$STATE_FILE" "$([[ -r $STATE_FILE ]] && echo '' || echo ' (missing)')"

    if [[ -r $STATE_FILE ]]; then
        while IFS=$'\t' read -r name mode position scale; do
            printf 'saved: %-12s %s %s scale %s\n' "$name" "$mode" "$position" "$scale"
        done < <(read_state)
    fi

    command -v hyprctl >/dev/null 2>&1 || return 0
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || return 0

    while IFS=$'\t' read -r name mode position scale; do
        [[ -n $name ]] || continue
        if is_internal "$name"; then
            printf 'active: %-12s %-16s %-10s scale %s (internal)\n' "$name" "$mode" "$position" "$scale"
        else
            printf 'active: %-12s %-16s %-10s scale %s (external)\n' "$name" "$mode" "$position" "$scale"
        fi
    done < <(monitor_rows)
}

while (($#)); do
    case "$1" in
        closed|open|status)
            [[ -z $COMMAND ]] || die "only one command is allowed"
            COMMAND="$1"
            ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

case "$COMMAND" in
    closed) handle_closed ;;
    open)   handle_open ;;
    status) show_status ;;
    "")     usage >&2; exit 2 ;;
esac
