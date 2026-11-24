#!/usr/bin/env bash
# Control Center behavior: pages, hardware gating and the lock entry. These
# checks call the functions instead of grepping for them.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CC="$ROOT/modules/control-center/home/.local/bin/dotfiles-control-center"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

# shellcheck source=/dev/null
source "$CC"

pages="$(control_center_pages)"
if [[ $pages != *Apps* ]]; then
    pass "Apps page is gone"
else
    fail "Apps page is still listed"
fi
if [[ $pages != *Docker* ]]; then
    pass "main menu has no Docker entry"
else
    fail "main menu still lists Docker"
fi
if ! declare -F apps_page >/dev/null || ! declare -F docker_page >/dev/null; then
    pass "apps_page and docker_page are removed"
else
    fail "dead pages still defined"
fi
if ! grep -q 'Maintenance help' "$CC"; then
    pass "Maintenance help is gone"
else
    fail "Maintenance help still exists"
fi

stub="$(mktemp -d)"
trap 'rm -rf "$stub"' EXIT
PATH="$stub:$PATH"

printf '#!/bin/sh\necho ethernet\necho loopback\n' >"$stub/nmcli"
printf '#!/bin/sh\nexit 0\n' >"$stub/bluetoothctl"
chmod +x "$stub/nmcli" "$stub/bluetoothctl"

if wifi_hardware_present; then
    fail "Wi-Fi reported without a Wi-Fi device"
else
    pass "Wi-Fi hidden when only ethernet exists"
fi
if bluetooth_hardware_present; then
    fail "Bluetooth reported without an adapter"
else
    pass "Bluetooth hidden without an adapter"
fi

printf '#!/bin/sh\necho wifi\necho ethernet\n' >"$stub/nmcli"
printf '#!/bin/sh\necho "Controller 00:11:22:33:44:55 host"\n' >"$stub/bluetoothctl"
chmod +x "$stub/nmcli" "$stub/bluetoothctl"

if wifi_hardware_present; then
    pass "Wi-Fi shown when the device exists"
else
    fail "Wi-Fi hidden despite a Wi-Fi device"
fi
if bluetooth_hardware_present; then
    pass "Bluetooth shown when an adapter exists"
else
    fail "Bluetooth hidden despite an adapter"
fi

printf '#!/bin/sh\necho stub-hyprlock\n' >"$stub/hyprlock"
chmod +x "$stub/hyprlock"
if [[ $(lock_screen_page) == *stub-hyprlock* ]]; then
    pass "Lock screen runs hyprlock when installed"
else
    fail "Lock screen does not run hyprlock"
fi

BT_CALLS="$stub/bt-calls" BT_ON="$stub/bt-on"
export BT_CALLS BT_ON
cat >"$stub/bluetoothctl" <<'BT'
#!/bin/sh
printf '%s\n' "$*" >>"$BT_CALLS"
case "$*" in
    show) [[ -e $BT_ON ]] && printf 'Powered: yes\n' || printf 'Powered: no\n' ;;
    'power on')  : >"$BT_ON" ;;
    'power off') rm -f "$BT_ON" ;;
    list) printf 'Controller 00:11:22:33:44:55 host\n' ;;
esac
BT
chmod +x "$stub/bluetoothctl"
(
    # shellcheck disable=SC2329
    notify() { printf '%s\n' "$*" >>"$stub/bt-notes"; }
    bluetooth_label >"$stub/bt-before"
    bluetooth_toggle
    bluetooth_label >"$stub/bt-after"
)
if [[ $(cat "$stub/bt-before") == "Bluetooth: off" &&
    $(cat "$stub/bt-after") == "Bluetooth: on" ]] &&
    grep -q 'power on' "$stub/bt-calls"; then
    pass "Bluetooth has one stateful on/off action"
else
    fail "Bluetooth toggle: $(cat "$stub/bt-before" "$stub/bt-after" 2>/dev/null)"
fi
(
    # shellcheck disable=SC2329
    pick_icon() { printf '%s\n' "$@" >"$stub/bt-page"; return 1; }
    bluetooth_page
)
if grep -q 'Bluetooth: on' "$stub/bt-page" &&
    ! grep -q 'Power on' "$stub/bt-page"; then
    pass "the Bluetooth page shows one toggle row, not two power buttons"
else
    fail "Bluetooth page rows: $(cat "$stub/bt-page" 2>/dev/null)"
fi

printf '#!/bin/sh\ncase "$*" in\n  *"connection show --active"*) echo Home ;;\n  *"connection down"*) printf "%%s\\n" "$*" >>"%s/nm-down" ;;\nesac\n' \
    "$stub" >"$stub/nmcli"
chmod +x "$stub/nmcli"
(
    # shellcheck disable=SC2329
    pick_icon() { printf '%s\n' "Disconnect"; }
    # shellcheck disable=SC2329
    run_terminal() { printf '%s\n' "$*" >"$stub/wifi-terminal"; }
    # shellcheck disable=SC2329
    notify() { printf '%s\n' "$*" >>"$stub/wifi-notes"; }
    wifi_page
)
if [[ ! -e $stub/wifi-terminal ]] &&
    grep -q 'Wi-Fi disconnected' "$stub/wifi-notes" &&
    grep -q 'connection down Home' "$stub/nm-down"; then
    pass "Wi-Fi disconnect acts in place without opening a terminal"
else
    fail "Wi-Fi disconnect still used a terminal or failed"
fi

# shellcheck disable=SC2016 # the stub expands $1 at its own runtime
printf '#!/bin/sh\ncase "$1" in --refresh) echo "up to date" ;; *) echo "3 commits behind" ;; esac\n' >"$stub/dotfiles-update-check.sh"
chmod +x "$stub/dotfiles-update-check.sh"
(
    # pick_icon runs in a command substitution, so the marker lives on disk.
    # shellcheck disable=SC2329 # both functions are called by update_page
    pick_icon() {
        [[ -e $stub/picked ]] && return 1
        : >"$stub/picked"
        printf '%s\n' "dotfiles: 3 commits behind"
    }
    # shellcheck disable=SC2329
    notify() { printf '%s\n' "$*" >>"$stub/notify"; }
    update_page
)
if grep -q 'dotfiles: up to date' "$stub/notify" 2>/dev/null; then
    pass "selecting the update row refreshes the status"
else
    fail "update row did not refresh the status"
fi

# shellcheck disable=SC2016 # the stub expands $1 at its own runtime
printf '#!/bin/sh
printf "%%s\\n" "$*" >>"%s/nightlight.calls"
case "$1" in
    status) echo "night light: enabled" ;;
    get) case "$2" in
        enabled) echo 1 ;;
        schedule) echo times ;;
        on-time) echo 18:00 ;;
        off-time) echo 07:00 ;;
        location) echo 50.45,30.52 ;;
    esac ;;
esac
' "$stub" >"$stub/nightlight.sh"
chmod +x "$stub/nightlight.sh"

if [[ $(nightlight_label) == "Night light: on" ]]; then
    pass "the menu label names the night light state"
else
    fail "night light label: $(nightlight_label)"
fi

(
    # shellcheck disable=SC2329 # called by nightlight_toggle
    notify() { printf '%s\n' "$*" >"$stub/nightlight-error"; }
    # shellcheck disable=SC2329 # overrides the stub for this subshell
    nightlight.sh() { printf 'hyprsunset is not installed\n' >&2; return 1; }
    nightlight_toggle
)
if grep -q 'hyprsunset is not installed' "$stub/nightlight-error" 2>/dev/null; then
    pass "a failed night light toggle reports the helper's reason"
else
    fail "the toggle failure reason was hidden"
fi

(
    # shellcheck disable=SC2329 # called by menu_page
    pick_icon() {
        printf '%s\n' "$@" >"$stub/menu-rows"
        return 1
    }
    menu_page
)
if grep -q 'Night light: on' "$stub/menu-rows"; then
    pass "the Menu carries the stateful night light row"
else
    fail "the Menu does not list the night light"
fi

(
    # shellcheck disable=SC2329
    pick_icon() { printf '%s\n' "$@" >"$stub/style-rows"; return 1; }
    style_page
)
if ! grep -q "Night light" "$stub/style-rows"; then
    pass "the night light moved out of the Style page"
else
    fail "the Style page still lists the night light"
fi

(
    # shellcheck disable=SC2329 # called by configuration_page
    pick_icon() {
        printf '%s\n' "$@" >"$stub/config-rows"
        return 1
    }
    configuration_page
)
missing=0
for label in Sound Monitors "Lock screen" Keybinds Tide "Night light"; do
    grep -q "$label" "$stub/config-rows" || missing=1
done
if ((missing == 0)); then
    pass "Configuration lists the installable entries before they exist"
else
    fail "Configuration hid an installable entry: $(cat "$stub/config-rows")"
fi

if [[ $(config_check_cmd Sound) == pavucontrol &&
    $(config_check_cmd "Night light") == nightlight.sh &&
    $(config_install_cmd Monitors) == *"--modules monitor-profiles"* &&
    $(config_install_cmd "Night light") == *"--modules nightlight"* &&
    $(config_install_cmd Tide) == *"--modules fish"* ]]; then
    pass "Configuration knows how to install what each entry needs"
else
    fail "Configuration dependency map is incomplete"
fi

mkdir -p "$stub/sysfs/wlan0/wireless" "$stub/sysfs-bt/hci0"
if WIFI_SYSFS="$stub/sysfs" wifi_hardware_present; then
    pass "Wi-Fi hardware is detected without nmcli"
else
    fail "Wi-Fi hardware was missed when nmcli is absent"
fi
if BLUETOOTH_SYSFS="$stub/sysfs-bt" bluetooth_hardware_present; then
    pass "Bluetooth hardware is detected without bluetoothctl"
else
    fail "Bluetooth hardware was missed when bluetoothctl is absent"
fi

printf '#!/bin/sh\nexit 0\n' >"$stub/idle-tune.sh"
chmod +x "$stub/idle-tune.sh"
(
    # shellcheck disable=SC2034 # read by idle_label
    STATE_DIR="$stub/state"
    # shellcheck disable=SC2329
    pick_icon() { printf '%s\n' "$@" >"$stub/menu-specs"; return 1; }
    # shellcheck disable=SC2329
    pgrep() { return 1; }
    menu_page
) >/dev/null
(
    # shellcheck disable=SC2329
    pick_icon() { printf '%s\n' "$@" >"$stub/config-specs"; return 1; }
    configuration_page
) >/dev/null
(
    # shellcheck disable=SC2329
    pick_icon() { printf '%s\n' "$@" >"$stub/idle-specs"; return 1; }
    idle_page
) >/dev/null
if grep -q 'Disable idle' "$stub/menu-specs" &&
    grep -q 'Idle' "$stub/config-specs" &&
    grep -q 'Configure' "$stub/idle-specs" &&
    ! grep -q 'Configure idle' "$stub/menu-specs"; then
    pass "idle configuration is in Configuration and the toggle stays in Menu"
else
    fail "idle pages are split incorrectly"
fi

mkdir -p "$stub/wp-home/.local/share/wallpapers"
: >"$stub/wp-home/.local/share/wallpapers/plain.png"
(
    # shellcheck disable=SC2034 # read by wallpaper_page
    REAL_HOME="$stub/wp-home"
    # shellcheck disable=SC2034
    STATE_DIR="$stub/wp-state"
    # shellcheck disable=SC2034
    CACHE_DIR="$stub/wp-cache"
    # shellcheck disable=SC2329
    have() { [[ $1 == magick ]] && return 1; command -v "$1" >/dev/null 2>&1; }
    # shellcheck disable=SC2329
    rofi_pick() { cat >"$stub/wp-rows"; return 1; }
    wallpaper_page
)
if grep -qx 'plain.png' "$stub/wp-rows" &&
    ! grep -q 'icon' "$stub/wp-rows"; then
    pass "the wallpaper picker falls back to plain rows without ImageMagick"
else
    fail "wallpaper fallback: $(cat "$stub/wp-rows" 2>/dev/null)"
fi

wifi_dispatch="$(
    # shellcheck disable=SC2329
    wifi_page() { printf 'wifi'; }
    control_center_main --wifi
)"
bluetooth_dispatch="$(
    # shellcheck disable=SC2329
    bluetooth_page() { printf 'bluetooth'; }
    control_center_main --bluetooth
)"
if [[ $wifi_dispatch == wifi && $bluetooth_dispatch == bluetooth ]]; then
    pass "Waybar can open the Wi-Fi and Bluetooth pages directly"
else
    fail "direct page dispatch: wifi=$wifi_dispatch bluetooth=$bluetooth_dispatch"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
