#!/usr/bin/env bash
# Interactive pointer (mouse/touchpad) tuner for Hyprland.
#
# Applies changes to the running session immediately (temporary), and can save
# them to hosts/<host>/input.lua in the dotfiles repository. The live
# hyprland.lua is never modified.
#
# Runtime API (Hyprland 0.57 Lua config):
#   hyprctl eval 'hl.config({ input = { sensitivity = -0.3 } })'
#   hyprctl eval 'hl.device({ name = "...", sensitivity = -0.3 })'
set -euo pipefail

# Float conversion and output in printf follow the user locale. Under a
# comma-decimal locale bash rejects "-0.30" and prints "-0,30", which is not
# valid Lua. Keep every number in this script locale-independent.
export LC_NUMERIC=C

DOTFILES_DIR="${DOTFILES_DIR:-}"
HOST_OVERRIDE=""
SHOW_ONLY=0

usage() {
    cat <<'EOF'
Usage: mouse-tune.sh [options]

Options:
  --repo DIR        dotfiles repository (default: autodetect)
  --host desktop|laptop
  --show            print current values and exit (read-only)
  -h, --help        this help

Keys in the live slider:
  Left/Right or -/+   change the value
  f                   toggle fine step (0.01 / 0.05)
  r                   reset this value to the session default
  Enter / q           finish adjusting

Saving writes hosts/<host>/input.lua in the repository (or
~/.config/hypr/input.lua when no repository is found) after showing a diff
and asking for confirmation. Nothing is written without confirmation.
EOF
}

while (($#)); do
    case "$1" in
        --repo)   DOTFILES_DIR="${2:?missing value for --repo}"; shift ;;
        --host)   HOST_OVERRIDE="${2:?missing value for --host}"; shift ;;
        --show)   SHOW_ONLY=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "mouse-tune: unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m' C_BOLD=$'\033[1m' C_DIM=$'\033[2m'
    C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_RED=$'\033[31m'
else
    C_RESET="" C_BOLD="" C_DIM="" C_GREEN="" C_YELLOW="" C_RED=""
fi

info() { printf '%s::%s %s\n' "$C_BOLD" "$C_RESET" "$*"; }
ok()   { printf '%sok%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%swarning:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

have_gum() { command -v gum >/dev/null 2>&1; }

need_hyprland() {
    command -v hyprctl >/dev/null 2>&1 || die "hyprctl not found (is Hyprland installed?)"
    hyprctl version >/dev/null 2>&1 || die "cannot talk to a running Hyprland instance"
}

# ---------------------------------------------------------------- discovery --

detect_repo() {
    local candidate path
    for candidate in "${DOTFILES_DIR:-}" "$HOME/Projects/dotfiles" "$HOME/.dotfiles" "$HOME/dotfiles"; do
        if [[ -n $candidate && -d $candidate/hosts && -d $candidate/modules ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    while [[ $path != / ]]; do
        if [[ -d $path/hosts && -d $path/modules ]]; then
            printf '%s\n' "$path"
            return 0
        fi
        path="$(dirname "$path")"
    done
    return 1
}

detect_host() {
    if compgen -G "/sys/class/power_supply/BAT*" >/dev/null 2>&1; then
        printf 'laptop\n'
        return
    fi
    local chassis=""
    if [[ -r /sys/class/dmi/id/chassis_type ]]; then
        chassis="$(cat /sys/class/dmi/id/chassis_type)"
    fi
    case "$chassis" in
        8|9|10|14) printf 'laptop\n' ;;
        *)         printf 'desktop\n' ;;
    esac
}

# ------------------------------------------------------------- hyprctl glue --

get_option() {
    local key="$1" raw
    raw="$(hyprctl getoption "$key" 2>/dev/null || true)"
    [[ -n $raw ]] || return 0
    if grep -q '^no such option' <<<"$raw"; then
        return 0
    fi
    sed -n 's/^[a-z]*: //p' <<<"$raw" | head -n1
}

# Convert getoption output to a plain value (empty string means "unset").
option_value() {
    local value
    value="$(get_option "$1")"
    if [[ $value == "[[EMPTY]]" ]]; then
        value=""
    fi
    printf '%s\n' "$value"
}

apply_input_field() {
    local field="$1" value="$2"
    if ! hyprctl eval "hl.config({ input = { $field = $value } })" >/dev/null 2>&1; then
        warn "failed to apply input:$field=$value"
        return 1
    fi
}

apply_touchpad_field() {
    local field="$1" value="$2"
    if ! hyprctl eval "hl.config({ input = { touchpad = { $field = $value } } })" >/dev/null 2>&1; then
        warn "failed to apply input:touchpad:$field=$value"
        return 1
    fi
}

lua_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

apply_device_field() {
    local name="$1" field="$2" value="$3"
    if ! hyprctl eval "hl.device({ name = \"$(lua_escape "$name")\", $field = $value })" >/dev/null 2>&1; then
        warn "failed to apply device '$name' $field=$value"
        return 1
    fi
}

# --------------------------------------------------------------------- math --

num_add() {
    awk -v a="$1" -v b="$2" 'BEGIN { printf "%.2f", a + b }'
}

num_clamp() {
    awk -v v="$1" -v lo="$2" -v hi="$3" 'BEGIN {
        if (v < lo) v = lo
        if (v > hi) v = hi
        printf "%.2f", v
    }'
}

num_normalize() {
    awk -v v="$1" 'BEGIN { printf "%.2f", v }'
}

# A leading space leaves room for the sign of positive values.
format_value() {
    printf '% .2f' "$1"
}

# ----------------------------------------------------------------------- UI --

choose() {
    local title="$1"
    shift
    local items=("$@")

    if have_gum && [[ -t 0 ]]; then
        printf '%s\n' "${items[@]}" | gum choose --header "$title"
        return
    fi

    local i choice
    printf '\n%s\n' "$title" >&2
    for i in "${!items[@]}"; do
        printf '  %2d) %s\n' "$((i + 1))" "${items[$i]}" >&2
    done
    while true; do
        printf 'Select 1-%d: ' "${#items[@]}" >&2
        read -r choice || return 1
        if [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#items[@]})); then
            printf '%s\n' "${items[$((choice - 1))]}"
            return 0
        fi
        printf 'Invalid selection.\n' >&2
    done
}

confirm() {
    local prompt="$1" default="${2:-no}"

    if have_gum && [[ -t 0 ]]; then
        if [[ $default == yes ]]; then
            gum confirm --default=true "$prompt"
        else
            gum confirm --default=false "$prompt"
        fi
        return $?
    fi

    local reply
    printf '%s [%s]: ' "$prompt" "$([[ $default == yes ]] && echo 'Y/n' || echo 'y/N')"
    read -r reply || true
    reply="${reply:-$default}"
    [[ $reply =~ ^[Yy]([Ee][Ss])?$ ]]
}

# ---------------------------------------------------------------- live edit --

live_adjust() {
    local label="$1" varname="$2" field="$3"
    local min="$4" max="$5" rough="$6" fine="$7" initial="${8:-0}" device="${9:-}"
    local -n value="$varname"
    local fine_mode=0 key rest step

    printf '\n%s%s%s  (←/→ or -/+, f = fine step, r = reset, Enter = done)\n' \
        "$C_BOLD" "$label" "$C_RESET"

    while true; do
        if ((fine_mode)); then step="$fine"; else step="$rough"; fi
        printf '\r\033[K  %s: %s%s%s   [step %s%s]\033[K' \
            "$label" "$C_BOLD" "$(format_value "$value")" "$C_RESET" "$step" \
            "$([[ $fine_mode == 1 ]] && echo ', fine')"

        IFS= read -rsn1 key || { printf '\n'; return 0; }

        if [[ $key == $'\033' ]]; then
            IFS= read -rsn2 -t 0.05 rest || true
            key="ESC$rest"
        fi

        case "$key" in
            'ESC[D'|h|-) value="$(num_add "$value" "-$step")" ;;
            'ESC[C'|l|+|'=') value="$(num_add "$value" "$step")" ;;
            f) fine_mode=$((1 - fine_mode)); continue ;;
            r) value="$initial" ;;
            ''|$'\n'|q|'ESC') break ;;
            *) continue ;;
        esac

        value="$(num_clamp "$value" "$min" "$max")"
        if [[ -n $device ]]; then
            apply_device_field "$device" "$field" "$value" || true
        else
            apply_input_field "$field" "$value" || true
        fi
        SENS_DIRTY=1
    done
    printf '\n'
}

# --------------------------------------------------------------- save/reload --

devices_with_settings() {
    local name
    {
        if ((${#DEV_SENS[@]})); then printf '%s\n' "${!DEV_SENS[@]}"; fi
        if ((${#DEV_ACCEL[@]})); then printf '%s\n' "${!DEV_ACCEL[@]}"; fi
        if ((${#DEV_SCROLL[@]})); then printf '%s\n' "${!DEV_SCROLL[@]}"; fi
    } | sed '/^$/d' | sort -u
}

render_state() {
    local name

    printf -- '-- Generated by mouse-tune.sh on %s.\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf -- '-- Loaded from hyprland.lua via pcall(dofile, ...).\n\n'
    printf 'hl.config({\n    input = {\n'

    if [[ -n ${SENS:-} ]]; then
        printf '        sensitivity = %s,\n' "$SENS"
    fi
    if [[ -n ${ACCEL:-} ]]; then
        printf '        accel_profile = "%s",\n' "$ACCEL"
    fi
    if [[ -n ${FNA:-} ]]; then
        printf '        force_no_accel = %s,\n' "$FNA"
    fi
    if [[ -n ${SCROLL:-} ]]; then
        printf '        scroll_factor = %s,\n' "$SCROLL"
    fi
    if ((SHOW_TOUCHPAD)); then
        printf '        touchpad = {\n'
        [[ -n ${TP_NAT:-} ]] && printf '            natural_scroll = %s,\n' "$TP_NAT"
        [[ -n ${TP_TAP:-} ]] && printf '            tap_to_click = %s,\n' "$TP_TAP"
        [[ -n ${TP_DWT:-} ]] && printf '            disable_while_typing = %s,\n' "$TP_DWT"
        printf '        },\n'
    fi
    printf '    },\n})\n'

    while IFS= read -r name; do
        [[ -n $name ]] || continue
        printf '\nhl.device({\n    name = "%s",\n' "$(lua_escape "$name")"
        [[ -n ${DEV_SENS[$name]:-} ]] && printf '    sensitivity = %s,\n' "${DEV_SENS[$name]}"
        [[ -n ${DEV_ACCEL[$name]:-} ]] && printf '    accel_profile = "%s",\n' "${DEV_ACCEL[$name]}"
        [[ -n ${DEV_SCROLL[$name]:-} ]] && printf '    scroll_factor = %s,\n' "${DEV_SCROLL[$name]}"
        printf '})\n'
    done < <(devices_with_settings)
}

backup_file() {
    local target="$1" label="$2" stamp dir
    stamp="$(date +%Y-%m-%d_%H%M%S)"
    dir="$HOME/.dotfiles-backup/$stamp"
    mkdir -p "$dir/$(dirname "$label")"
    cp -a -- "$target" "$dir/$label"
    printf '%s\n' "$dir/$label"
}

save_state() {
    local repo host target tmp diff_out backup dest install_copy=0

    repo="$(detect_repo || true)"
    host="$HOST"

    if [[ -n $repo ]]; then
        target="$repo/hosts/$host/input.lua"
    else
        target="$HOME/.config/hypr/input.lua"
    fi

    if [[ -z ${SENS:-}${ACCEL:-}${FNA:-}${SCROLL:-} ]] && ! ((SHOW_TOUCHPAD)) && (($(devices_with_settings | wc -l) == 0)); then
        warn "nothing to save"
        return 0
    fi

    tmp="$(mktemp)"
    render_state >"$tmp"

    printf '\n'
    info "Target: $target"
    if [[ -f $target ]]; then
        if cmp -s -- "$tmp" "$target"; then
            ok "file is already up to date"
            rm -f -- "$tmp"
            return 0
        fi
        diff_out="$(diff -u -- "$target" "$tmp" || true)"
        printf '%s\n' "$diff_out"
    else
        printf '%s\n' "${C_DIM}(new file)${C_RESET}"
        sed 's/^/  /' "$tmp"
    fi

    if ! confirm "Write this configuration?" no; then
        warn "not saved"
        rm -f -- "$tmp"
        return 1
    fi

    if [[ -f $target ]]; then
        backup="$(backup_file "$target" "${target#"$HOME"/}")"
        ok "backup: $backup"
    fi

    mkdir -p "$(dirname "$target")"
    install -m 0644 -- "$tmp" "$target"
    ok "saved $target"

    dest="$HOME/.config/hypr/input.lua"
    if [[ "$(readlink -f -- "$target")" != "$(readlink -f -- "$dest" 2>/dev/null || printf '%s' "$dest")" ]] \
        && [[ -f $dest || -d $(dirname "$dest") ]]; then
        if confirm "Also install it as ~/.config/hypr/input.lua?" yes; then
            if [[ -f $dest ]]; then
                backup="$(backup_file "$dest" "config/hypr/input.lua")"
                ok "backup: $backup"
            fi
            install -m 0644 -- "$tmp" "$dest"
            ok "installed $dest"
            install_copy=1
        fi
    fi

    rm -f -- "$tmp"

    if ((install_copy)) && confirm "Reload Hyprland to apply the saved file?" no; then
        hyprctl reload >/dev/null
        ok "Hyprland reloaded"
    fi
}

# ------------------------------------------------------------------ presets --

apply_preset() {
    local choice
    choice="$(choose "Sensitivity preset" \
        "Low (-0.60)" \
        "Medium (-0.30)" \
        "High (+0.20)" \
        "My current session value (${SENS_INIT})")" || return 0

    case "$choice" in
        Low*)    SENS="-0.60" ;;
        Medium*) SENS="-0.30" ;;
        High*)   SENS="0.20" ;;
        My*)     SENS="$SENS_INIT" ;;
        *)       return 0 ;;
    esac

    SENS="$(num_clamp "$SENS" -1 1)"
    apply_input_field sensitivity "$SENS" || true
    ok "sensitivity = $SENS (temporary until saved)"
}

# ------------------------------------------------------------- touchpad/dev --

touchpad_present() {
    if [[ $HOST == laptop ]]; then
        return 0
    fi
    hyprctl devices -j 2>/dev/null | jq -e '(.touch // []) | length > 0' >/dev/null 2>&1 && return 0
    hyprctl devices -j 2>/dev/null | jq -r '.mice[]?.name' 2>/dev/null | grep -qi 'touchpad\|synaptics\|elan' && return 0
    return 1
}

pointer_devices() {
    hyprctl devices -j 2>/dev/null | jq -r '.mice[]?.name' 2>/dev/null || true
}

toggle_bool() {
    local label="$1" varname="$2" apply_fn="$3" field="$4"
    local -n value="$varname"
    local next
    if [[ $value == true ]]; then next=false; else next=true; fi
    value="$next"
    "$apply_fn" "$field" "$value" || true
    ok "$label = $value"
}

touchpad_menu() {
    local choice
    while true; do
        choice="$(choose "Touchpad settings" \
            "natural_scroll: $TP_NAT" \
            "tap_to_click: $TP_TAP" \
            "disable_while_typing: $TP_DWT" \
            "Back")" || return 0

        case "$choice" in
            natural_scroll*)       toggle_bool natural_scroll TP_NAT apply_touchpad_field natural_scroll ;;
            tap_to_click*)         toggle_bool tap_to_click TP_TAP apply_touchpad_field tap_to_click ;;
            disable_while_typing*) toggle_bool disable_while_typing TP_DWT apply_touchpad_field disable_while_typing ;;
            Back*)                 return 0 ;;
        esac
    done
}

device_menu() {
    local devices=() name choice field value
    mapfile -t devices < <(pointer_devices)

    if ((${#devices[@]} == 0)); then
        warn "no pointer devices reported by Hyprland"
        return 0
    fi

    name="$(choose "Pointer device" "${devices[@]}" "Back")" || return 0
    [[ $name == Back ]] && return 0

    while true; do
        choice="$(choose "Device: $name" \
            "sensitivity: ${DEV_SENS[$name]:-default}" \
            "accel_profile: ${DEV_ACCEL[$name]:-default}" \
            "scroll_factor: ${DEV_SCROLL[$name]:-default}" \
            "Reset this device" \
            "Back")" || return 0

        case "$choice" in
            sensitivity:*)
                DEV_SENS[$name]="$(num_normalize "${DEV_SENS[$name]:-0}")"
                live_adjust "sensitivity" "DEV_SENS[$name]" "sensitivity" -1 1 0.05 0.01 0 "$name"
                ok "$name sensitivity = ${DEV_SENS[$name]}"
                ;;
            accel_profile:*)
                field="$(choose "Acceleration profile for $name" flat adaptive default)" || continue
                if [[ $field == default ]]; then
                    DEV_ACCEL[$name]=""
                    apply_device_field "$name" accel_profile '""' || true
                else
                    DEV_ACCEL[$name]="$field"
                    apply_device_field "$name" accel_profile "\"$field\"" || true
                fi
                ok "$name accel_profile = ${DEV_ACCEL[$name]:-default}"
                ;;
            scroll_factor:*)
                DEV_SCROLL[$name]="$(num_normalize "${DEV_SCROLL[$name]:-1}")"
                live_adjust "scroll_factor" "DEV_SCROLL[$name]" "scroll_factor" 0.1 3 0.1 0.05 1 "$name"
                ok "$name scroll_factor = ${DEV_SCROLL[$name]}"
                ;;
            Reset*)
                unset 'DEV_SENS[$name]' 'DEV_ACCEL[$name]' 'DEV_SCROLL[$name]' 2>/dev/null || true
                apply_device_field "$name" sensitivity 0 || true
                apply_device_field "$name" accel_profile '""' || true
                apply_device_field "$name" scroll_factor 1 || true
                ok "reset overrides for $name"
                ;;
            Back*) return 0 ;;
        esac
    done
}

# --------------------------------------------------------------------- reset --

reset_live() {
    SENS="$SENS_INIT"
    ACCEL="$ACCEL_INIT"
    FNA="$FNA_INIT"
    SCROLL="$SCROLL_INIT"
    if ((SHOW_TOUCHPAD)); then
        TP_NAT="$TP_NAT_INIT"
        TP_TAP="$TP_TAP_INIT"
        TP_DWT="$TP_DWT_INIT"
    fi

    apply_input_field sensitivity "$SENS" || true
    if [[ -n $ACCEL ]]; then
        apply_input_field accel_profile "\"$ACCEL\"" || true
    else
        apply_input_field accel_profile '""' || true
    fi
    apply_input_field force_no_accel "$FNA" || true
    apply_input_field scroll_factor "$SCROLL" || true
    if ((SHOW_TOUCHPAD)); then
        apply_touchpad_field natural_scroll "$TP_NAT" || true
        apply_touchpad_field tap_to_click "$TP_TAP" || true
        apply_touchpad_field disable_while_typing "$TP_DWT" || true
    fi

    local name
    while IFS= read -r name; do
        [[ -n $name ]] || continue
        apply_device_field "$name" sensitivity 0 || true
        apply_device_field "$name" accel_profile '""' || true
        apply_device_field "$name" scroll_factor 1 || true
    done < <(devices_with_settings)

    DEV_SENS=()
    DEV_ACCEL=()
    DEV_SCROLL=()
    ok "restored the session defaults"
}

# ---------------------------------------------------------------------- main --

need_hyprland

HOST="${HOST_OVERRIDE:-$(detect_host)}"
SHOW_TOUCHPAD=0
if touchpad_present; then
    SHOW_TOUCHPAD=1
fi

SENS_INIT="$(option_value input:sensitivity)"
SENS_INIT="${SENS_INIT:-0}"
SENS_INIT="$(num_normalize "$SENS_INIT")"

ACCEL_INIT="$(option_value input:accel_profile)"
FNA_INIT="$(option_value input:force_no_accel)"
FNA_INIT="${FNA_INIT:-false}"
SCROLL_INIT="$(option_value input:scroll_factor)"
SCROLL_INIT="${SCROLL_INIT:-1}"
SCROLL_INIT="$(num_normalize "$SCROLL_INIT")"

TP_NAT_INIT="$(option_value input:touchpad:natural_scroll)"
TP_NAT_INIT="${TP_NAT_INIT:-false}"
TP_TAP_INIT="$(option_value input:touchpad:tap-to-click)"
TP_TAP_INIT="${TP_TAP_INIT:-true}"
TP_DWT_INIT="$(option_value input:touchpad:disable_while_typing)"
TP_DWT_INIT="${TP_DWT_INIT:-true}"

SENS="$SENS_INIT"
ACCEL="$ACCEL_INIT"
FNA="$FNA_INIT"
SCROLL="$SCROLL_INIT"
TP_NAT="$TP_NAT_INIT"
TP_TAP="$TP_TAP_INIT"
TP_DWT="$TP_DWT_INIT"
SENS_DIRTY=0

declare -A DEV_SENS=()
declare -A DEV_ACCEL=()
declare -A DEV_SCROLL=()

if ((SHOW_ONLY)); then
    printf 'host:            %s\n' "$HOST"
    printf 'sensitivity:     %s\n' "$SENS"
    printf 'accel_profile:   %s\n' "${ACCEL:-<default>}"
    printf 'force_no_accel:  %s\n' "$FNA"
    printf 'scroll_factor:   %s\n' "$SCROLL"
    printf 'touchpad:        %s\n' "$([[ $SHOW_TOUCHPAD == 1 ]] && echo present || echo absent)"
    if ((SHOW_TOUCHPAD)); then
        printf '  natural_scroll:       %s\n' "$TP_NAT"
        printf '  tap_to_click:         %s\n' "$TP_TAP"
        printf '  disable_while_typing: %s\n' "$TP_DWT"
    fi
    printf 'pointer devices:\n'
    pointer_devices | sed 's/^/  /'
    exit 0
fi

if [[ ! -t 0 ]]; then
    die "this tuner needs an interactive terminal (try --show for a read-only report)"
fi

printf '%sMouse and touchpad tuner%s\n' "$C_BOLD" "$C_RESET"
printf 'Host: %s   GPU session: Hyprland %s\n' "$HOST" "$(hyprctl version | sed -n 's/^Hyprland \([^ ]*\).*/\1/p' | head -n1)"
printf '%sChanges are applied immediately and are temporary until you choose Save.%s\n' "$C_DIM" "$C_RESET"

while true; do
    choice="$(choose "What do you want to tune?" \
        "Sensitivity (live): $SENS" \
        "Acceleration profile: ${ACCEL:-default}" \
        "Force no acceleration: $FNA" \
        "Scroll factor (live): $SCROLL" \
        "Per-device settings" \
        "$([[ $SHOW_TOUCHPAD == 1 ]] && echo 'Touchpad settings' || echo 'Touchpad settings (not detected)')" \
        "Presets" \
        "Save configuration" \
        "Reset to session defaults" \
        "Quit")" || break

    case "$choice" in
        Sensitivity*)
            live_adjust "sensitivity" SENS "sensitivity" -1 1 0.05 0.01 "$SENS_INIT"
            ;;
        Acceleration*)
            value="$(choose "Acceleration profile" flat adaptive default)" || continue
            if [[ $value == default ]]; then
                ACCEL=""
                apply_input_field accel_profile '""' || true
            else
                ACCEL="$value"
                apply_input_field accel_profile "\"$value\"" || true
            fi
            ok "accel_profile = ${ACCEL:-default}"
            ;;
        Force*)
            if [[ $FNA == true ]]; then FNA=false; else FNA=true; fi
            apply_input_field force_no_accel "$FNA" || true
            ok "force_no_accel = $FNA"
            ;;
        Scroll*)
            live_adjust "scroll_factor" SCROLL "scroll_factor" 0.1 3 0.1 0.05 "$SCROLL_INIT"
            ;;
        Per-device*)
            device_menu
            ;;
        Touchpad*)
            if ((SHOW_TOUCHPAD)); then
                touchpad_menu
            else
                warn "no touchpad detected on this host"
            fi
            ;;
        Presets*)
            apply_preset
            ;;
        Save*)
            save_state || true
            ;;
        Reset*)
            if confirm "Restore the values that were active when the tuner started?" no; then
                reset_live
            fi
            ;;
        Quit*)
            if ((SENS_DIRTY)); then
                if confirm "Restore the session defaults before quitting?" no; then
                    reset_live
                fi
            fi
            break
            ;;
    esac
done

exit 0
