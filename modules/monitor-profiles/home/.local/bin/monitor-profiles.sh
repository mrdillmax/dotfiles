#!/usr/bin/env bash
# Hotplug monitor profiles for laptops with an external/dock display.
#
# The layout preference is stored in ~/.config/hypr/monitor-profiles.conf:
#   DOCK_LAYOUT=right|left|mirror|ask
#
# `watch` listens on the Hyprland event socket (socket2) with socat. Monitor
# events are debounced so a dock that registers several outputs at once only
# triggers one layout pass. `apply` changes the running session only; it never
# rewrites Hyprland configuration files.
#
# NOT VERIFIED ON REAL DOCK HARDWARE. Run `monitor-profiles.sh apply --dry-run`
# first and keep a copy of `hyprctl monitors -j` (the script also writes one
# under ~/.local/state/dotfiles/monitor-profiles/ before applying).
set -uo pipefail

REAL_HOME="${HOME:?HOME is not set}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$REAL_HOME/.config}"
STATE_DIR="${XDG_STATE_HOME:-$REAL_HOME/.local/state}/dotfiles/monitor-profiles"
LIVE_CONFIG="$CONFIG_HOME/hypr/monitor-profiles.conf"
DEBOUNCE="${MONITOR_PROFILES_DEBOUNCE:-0.5}"

DOCK_LAYOUT="right"
DRY_RUN=0
COMMAND=""

usage() {
    cat <<'EOF'
Usage: monitor-profiles.sh <apply|watch|status|set-layout LAYOUT> [--dry-run]

  apply       apply the configured layout to the running session once
  watch       listen on the Hyprland socket2 events and apply on hotplug
  status      show the configured layout and detected monitors
  set-layout  store right|left|mirror|ask in ~/.config/hypr/monitor-profiles.conf

Options:
  --dry-run   print the hyprctl commands, change nothing

Layouts:
  right   external monitors to the right of the internal panel (default)
  left    external monitors to the left
  mirror  clone the internal mode at 0x0 (hardware must support the mode)
  ask     never move monitors automatically; only show a notification

Environment:
  MONITOR_PROFILES_DEBOUNCE   quiet window in seconds (default: 0.5)

The preference is installed by `./install.sh --dock-layout LAYOUT` and is
stored in the repository at hosts/<host>/monitor-profiles.conf.

NOT VERIFIED ON REAL DOCK HARDWARE.
EOF
}

die() { printf 'monitor-profiles: %s\n' "$*" >&2; exit 1; }
info() { printf ':: %s\n' "$*"; }
ok() { printf 'ok %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

lua_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

notify() {
    local message="$1"

    # A dry run must not pop up desktop notifications either.
    if ((DRY_RUN)); then
        info "[dry-run] $message"
        return 0
    fi

    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a monitor-profiles -i video-display "Monitor profile" "$message" \
            >/dev/null 2>&1 || true
    fi
    info "$message"
}

require_session() {
    command -v hyprctl >/dev/null 2>&1 || die "hyprctl is not installed"
    command -v jq >/dev/null 2>&1 || die "jq is not installed"
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] \
        || die "not inside a Hyprland session (HYPRLAND_INSTANCE_SIGNATURE is unset)"
}

load_layout() {
    local value

    [[ -r $LIVE_CONFIG ]] || return 0
    value="$(sed -n 's/^[[:space:]]*DOCK_LAYOUT[[:space:]]*=[[:space:]]*//p' \
        "$LIVE_CONFIG" | tail -n1)"
    value="${value%"${value##*[![:space:]]}"}"
    case "$value" in
        right|left|mirror|ask) DOCK_LAYOUT="$value" ;;
        "") : ;;
        *) warn "invalid DOCK_LAYOUT in $LIVE_CONFIG: $value (using right)" ;;
    esac
}

write_layout() {
    local layout="$1" tmp

    case "$layout" in
        right|left|mirror|ask) ;;
        *) die "invalid layout: $layout (use right, left, mirror or ask)" ;;
    esac

    if ((DRY_RUN)); then
        info "[dry-run] would write DOCK_LAYOUT=$layout to $LIVE_CONFIG"
        return 0
    fi

    mkdir -p -- "$(dirname "$LIVE_CONFIG")"
    tmp="$(mktemp)"
    {
        printf '# Layout for an external/dock monitor: right|left|mirror|ask.\n'
        printf '# Source of truth: hosts/<host>/monitor-profiles.conf in the repo.\n'
        printf 'DOCK_LAYOUT=%s\n' "$layout"
    } >"$tmp"
    mv -f -- "$tmp" "$LIVE_CONFIG"
    ok "stored DOCK_LAYOUT=$layout"
}

# Prints name<TAB>width<TAB>height<TAB>refresh<TAB>scale.
read_monitors() {
    hyprctl monitors -j 2>/dev/null \
        | jq -r '.[] | [.name, (.width|tostring), (.height|tostring),
                        (.refreshRate|round|tostring), (.scale|tostring)] | @tsv'
}

mode_of() {
    local width="$1" height="$2" refresh="$3"
    if [[ -z $width || -z $height || $refresh == 0 ]]; then
        printf 'preferred'
    else
        printf '%sx%s@%s' "$width" "$height" "$refresh"
    fi
}

logical_width() {
    local width="$1" scale="$2"
    awk -v w="$width" -v s="$scale" \
        'BEGIN { printf "%d", (s + 0 > 0 ? w / s : w) }'
}

save_backup() {
    local json="$1" file

    ((DRY_RUN)) && return 0
    mkdir -p -- "$STATE_DIR"
    file="$STATE_DIR/monitors-$(date +%Y-%m-%d_%H%M%S).json"
    printf '%s\n' "$json" >"$file"
    info "pre-apply monitor state: $file"
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
        warn "failed to apply monitor $name ($mode at $position)"
        return 1
    }
}

is_internal() {
    [[ $1 =~ ^(eDP|LVDS|DSI|DPI)- ]]
}

apply_profile() {
    local json rows_line
    local -a names=() widths=() heights=() refreshes=() scales=()
    local -a internal=() external=()
    local i x position mode ext_width

    require_session
    load_layout

    json="$(hyprctl monitors -j 2>/dev/null || true)"
    [[ -n $json ]] || die "cannot read monitors from hyprctl"

    mapfile -t rows_line < <(jq -r '.[] | [.name, (.width|tostring), (.height|tostring),
        (.refreshRate|round|tostring), (.scale|tostring)] | @tsv' <<<"$json" 2>/dev/null)

    if ((${#rows_line[@]} == 0)); then
        warn "no monitors reported by hyprctl"
        return 0
    fi

    for i in "${!rows_line[@]}"; do
        IFS=$'\t' read -r "names[i]" "widths[i]" "heights[i]" "refreshes[i]" "scales[i]" \
            <<<"${rows_line[$i]}"
    done

    for i in "${!names[@]}"; do
        if is_internal "${names[$i]}"; then
            internal+=("$i")
        else
            external+=("$i")
        fi
    done

    if ((${#internal[@]} == 0)); then
        if ((${#names[@]} == 1)); then
            warn "no internal panel name found; treating ${names[0]} as primary"
            mode="$(mode_of "${widths[0]}" "${heights[0]}" "${refreshes[0]}")"
            apply_monitor "${names[0]}" "$mode" "0x0" "${scales[0]:-1}" || return 1
            return 0
        fi
        info "no internal panel detected; desktop layout left unchanged"
        return 0
    fi

    if [[ $DOCK_LAYOUT == ask ]]; then
        notify "monitor layout changed; DOCK_LAYOUT=ask leaves it untouched"
        return 0
    fi

    # Position the internal panel at the origin first.
    i="${internal[0]}"
    mode="$(mode_of "${widths[$i]}" "${heights[$i]}" "${refreshes[$i]}")"
    save_backup "$json"
    apply_monitor "${names[$i]}" "$mode" "0x0" "${scales[$i]:-1}" || return 1

    if ((${#external[@]} == 0)); then
        ok "single internal panel: ${names[$i]}"
        return 0
    fi

    local internal_scale="${scales[$i]:-1}"
    local internal_width
    internal_width="$(logical_width "${widths[$i]}" "$internal_scale")"

    case "$DOCK_LAYOUT" in
        right)
            x="$internal_width"
            for i in "${external[@]}"; do
                mode="$(mode_of "${widths[$i]}" "${heights[$i]}" "${refreshes[$i]}")"
                apply_monitor "${names[$i]}" "$mode" "${x}x0" "${scales[$i]:-1}" || return 1
                ext_width="$(logical_width "${widths[$i]}" "${scales[$i]:-1}")"
                x=$((x + ext_width))
            done
            ;;
        left)
            x=0
            for i in "${external[@]}"; do
                ext_width="$(logical_width "${widths[$i]}" "${scales[$i]:-1}")"
                x=$((x - ext_width))
                mode="$(mode_of "${widths[$i]}" "${heights[$i]}" "${refreshes[$i]}")"
                apply_monitor "${names[$i]}" "$mode" "${x}x0" "${scales[$i]:-1}" || return 1
            done
            ;;
        mirror)
            i="${internal[0]}"
            mode="$(mode_of "${widths[$i]}" "${heights[$i]}" "${refreshes[$i]}")"
            for i in "${external[@]}"; do
                apply_monitor "${names[$i]}" "$mode" "0x0" "$internal_scale" || return 1
            done
            ;;
    esac

    ((DRY_RUN)) || ok "applied $DOCK_LAYOUT layout for ${#external[@]} external monitor(s)"
}

show_status() {
    local json
    local -a names=()

    load_layout
    printf 'layout: %s\n' "$DOCK_LAYOUT"
    printf 'config: %s\n' "$LIVE_CONFIG"

    command -v hyprctl >/dev/null 2>&1 || { printf 'monitors: (hyprctl missing)\n'; return 0; }
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || { printf 'monitors: (not in a Hyprland session)\n'; return 0; }

    json="$(hyprctl monitors -j 2>/dev/null || true)"
    [[ -n $json ]] || { printf 'monitors: (unavailable)\n'; return 0; }

    mapfile -t names < <(jq -r '.[].name' <<<"$json" 2>/dev/null)
    local name kind
    for name in "${names[@]}"; do
        if is_internal "$name"; then kind=internal; else kind=external; fi
        printf 'monitor: %-12s %s\n' "$name" "$kind"
    done
}

# Reads event lines on stdin and applies after a quiet window.
watch_stream() {
    local line rc dirty=0

    while true; do
        if IFS= read -r -t "$DEBOUNCE" line; then
            case "$line" in
                monitoradded\>\>*|monitorremoved\>\>*) dirty=1 ;;
            esac
        else
            rc=$?
            # >128 is a read timeout; anything else means EOF or error.
            ((rc > 128)) || break
            if ((dirty)); then
                apply_profile
                dirty=0
            fi
        fi
    done

    if ((dirty)); then
        apply_profile
    fi
}

watch_socket() {
    local sock="$1"

    socat -U - "UNIX-CONNECT:$sock" 2>/dev/null | watch_stream
}

watch() {
    local sock

    require_session
    command -v socat >/dev/null 2>&1 || die "socat is not installed"

    sock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
    [[ -S $sock ]] || sock="/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
    [[ -S $sock ]] || die "Hyprland socket2 not found (looked in \$XDG_RUNTIME_DIR and /tmp/hypr)"

    info "watching $sock (debounce ${DEBOUNCE}s, layout $DOCK_LAYOUT)"
    while true; do
        watch_socket "$sock"
        sleep 1
    done
}

main() {
    while (($#)); do
        case "$1" in
            apply|watch|status)
                [[ -z $COMMAND ]] || die "only one command is allowed"
                COMMAND="$1"
                ;;
            set-layout)
                [[ -z $COMMAND ]] || die "only one command is allowed"
                COMMAND="set-layout"
                [[ -n ${2:-} ]] || die "set-layout needs right|left|mirror|ask"
                SET_LAYOUT="$2"
                shift
                ;;
            --dry-run) DRY_RUN=1 ;;
            -h|--help) usage; exit 0 ;;
            *) die "unknown option: $1 (see --help)" ;;
        esac
        shift
    done

    load_layout

    case "$COMMAND" in
        apply)      apply_profile ;;
        watch)      watch ;;
        status)     show_status ;;
        set-layout) write_layout "$SET_LAYOUT" ;;
        "")         usage >&2; exit 2 ;;
    esac
}

if [[ ${MONITOR_PROFILES_SOURCE_ONLY:-0} != 1 ]]; then
    main "$@"
fi
