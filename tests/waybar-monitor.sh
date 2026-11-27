#!/usr/bin/env bash
# Waybar monitoring scripts: failed units, updates, battery and network JSON.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/modules/waybar/home/.local/bin"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/bat"

printf '#!/bin/sh\ncase "$*" in\n  *--user*--failed*) echo "user1.service loaded failed failed" ;;\n  *--failed*) echo "sys1.service loaded failed failed"; echo "sys2.service loaded failed failed" ;;\nesac\n' >"$work/bin/systemctl"
# shellcheck disable=SC2016 # the stub expands its own $1
printf '#!/bin/sh\ncase "$1" in\n  --json) echo "{\\"status\\":\\"behind\\",\\"behind\\":2,\\"ahead\\":0,\\"local\\":\\"x\\",\\"remote\\":\\"y\\",\\"cached\\":false}" ;;\n  --refresh) echo "up to date" ;;\nesac\n' >"$work/bin/update-check"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/notify"\n' "$work" >"$work/bin/notify-send"
printf '#!/bin/sh\necho "pkill $*" >>"%s/pkill.log"\n' "$work" >"$work/bin/pkill"
printf '#!/bin/sh\necho "wifi:connected:HomeNet:wl0"\n' >"$work/bin/nmcli"
printf '#!/bin/sh\necho "2: wl0    inet 10.0.0.5/24 brd 10.0.0.255 scope global wl0"\n' >"$work/bin/ip"
chmod +x "$work/bin"/*
PATH="$work/bin:$PATH"

printf '42\n' >"$work/bat/capacity"
printf 'Discharging\n' >"$work/bat/status"

out="$(SYSTEMCTL_BIN="$work/bin/systemctl" "$BIN/waybar-units.sh")"
if [[ $out == *' 3"'* ]] && [[ $out == *sys1.service* ]]; then
    pass "failed units are counted and listed"
else
    fail "units output: $out"
fi

out="$(DOTFILES_UPDATE_CHECK="$work/bin/update-check" "$BIN/waybar-update.sh")"
if [[ $out == *'"alt":"behind"'* && $out == *' 2"'* && $out == *'"class":"behind"'* ]]; then
    pass "a repo that is behind is reported"
else
    fail "update output: $out"
fi

DOTFILES_UPDATE_CHECK="$work/bin/update-check" "$BIN/waybar-update.sh" --click >/dev/null 2>&1
if grep -q 'dotfiles: up to date' "$work/notify"; then
    pass "clicking the update module checks and notifies"
else
    fail "click did not notify: $(cat "$work/notify" 2>/dev/null)"
fi

mkdir -p "$work/backlight/panel" "$work/emptylight"
printf '40\n' >"$work/backlight/panel/brightness"
printf '100\n' >"$work/backlight/panel/max_brightness"
out="$(BACKLIGHT_DIR="$work/backlight/panel" "$BIN/waybar-brightness.sh" --once)"
if [[ $out == *'40%'* ]]; then
    pass "brightness reports the backlight percentage"
else
    fail "brightness output: $out"
fi
out="$(BACKLIGHT_DIR="$work/emptylight" "$BIN/waybar-brightness.sh" --once)"
if [[ $out == '{"text": ""}' ]]; then
    pass "no backlight produces an empty module"
else
    fail "empty brightness output: $out"
fi

out="$(BAT_DIR="$work/bat" "$BIN/waybar-battery.sh" --once)"
if [[ $out == *'42%'* && $out == *Discharging* ]]; then
    pass "battery reports capacity and state"
else
    fail "battery output: $out"
fi
mkdir -p "$work/empty"
out="$(BAT_DIR="$work/empty" "$BIN/waybar-battery.sh" --once)"
if [[ $out == '{"text": ""}' ]]; then
    pass "no battery produces an empty module"
else
    fail "empty battery output: $out"
fi

out="$(NMCLI_BIN="$work/bin/nmcli" IP_BIN="$work/bin/ip" "$BIN/waybar-network.sh" --once)"
if [[ $out != *HomeNet* && $out == *'"alt":"wifi"'* && $out == *10.0.0.5* ]]; then
    pass "network hides the SSID but keeps the link type and address"
else
    fail "network output: $out"
fi
out="$(NMCLI_BIN=/bin/false "$BIN/waybar-network.sh" --once)"
if [[ $out == *'"alt":"offline"'* && $out == *'"class":"offline"'* ]]; then
    pass "offline still leaves a clickable link icon"
else
    fail "offline network output: $out"
fi

# The streaming modules read their own events; Waybar must not poll them.
CONFIG="$ROOT/modules/waybar/home/.config/waybar/config.jsonc"
config_json="$(sed -E 's#^[[:space:]]*//.*$##' "$CONFIG")"
if jq -e '."custom/battery" | has("interval") | not' >/dev/null <<<"$config_json" &&
    jq -e '."custom/brightness" | has("interval") | not' >/dev/null <<<"$config_json" &&
    jq -e '."custom/network" | has("interval") | not' >/dev/null <<<"$config_json"; then
    pass "event-driven Waybar modules are not polled"
else
    fail "a streaming Waybar module still has an interval"
fi
if jq -e '."modules-right" | index("group/zvuk")' >/dev/null <<<"$config_json" &&
    jq -e '."modules-right" | index("group/hardware")' >/dev/null <<<"$config_json" &&
    jq -e '."modules-right" | index("group/link")' >/dev/null <<<"$config_json" &&
    jq -e '."group/zvuk".modules | index("custom/brightness")' >/dev/null <<<"$config_json" &&
    jq -e '."group/hardware".modules | index("custom/battery")' >/dev/null <<<"$config_json" &&
    jq -e '."group/hardware".modules | index("power-profiles-daemon")' >/dev/null <<<"$config_json" &&
    jq -e '."group/hardware".modules | index("cpu")' >/dev/null <<<"$config_json" &&
    jq -e '."group/link".modules | index("custom/network")' >/dev/null <<<"$config_json" &&
    jq -e '."group/link".modules | index("bluetooth")' >/dev/null <<<"$config_json"; then
    pass "sound, power and link modules are grouped into three compact pills"
else
    fail "the related status modules are not grouped"
fi
if jq -e '."group/link".modules | index("bluetooth")' >/dev/null <<<"$config_json" &&
    jq -e '."bluetooth"."format-no-controller" == ""' >/dev/null <<<"$config_json" &&
    jq -e '."bluetooth"."format-disabled" != ""' >/dev/null <<<"$config_json"; then
    pass "the Bluetooth module hides without an adapter and shows a blocked state"
else
    fail "the Bluetooth module is missing or not gated"
fi
if jq -e '."custom/battery" | has("on-click") | not' >/dev/null <<<"$config_json" &&
    jq -e '."custom/network"."on-click" | endswith("--wifi")' >/dev/null <<<"$config_json" &&
    jq -e '."bluetooth"."on-click" | endswith("--bluetooth")' >/dev/null <<<"$config_json"; then
    pass "battery has no click action and link modules open the Control Center"
else
    fail "Waybar click actions are wrong"
fi

STYLE="$ROOT/modules/waybar/home/.config/waybar/style.css"
if ! grep -q 'Font Awesome 7 Free' "$STYLE" &&
    grep -q '#custom-battery' "$STYLE" &&
    grep -q '#custom-brightness' "$STYLE" &&
    grep -q '#custom-network' "$STYLE" &&
    grep -q '#bluetooth' "$STYLE" &&
    grep -q '#power-profiles-daemon' "$STYLE"; then
    pass "status modules share the pill style and the icon font is usable"
else
    fail "status modules are unstyled or the woff2 icon font is still named"
fi

# Old autostart entries must move to the explicit managed config path.
AUTOSTART="$ROOT/modules/autostart/home/.local/bin/autostart.sh"
mkdir -p "$work/home/.local/state/dotfiles" "$work/autostart-bin" "$work/run"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/uwsm.args"\n' "$work" >"$work/autostart-bin/uwsm"
printf '#!/bin/sh\nexit 0\n' >"$work/autostart-bin/waybar"
chmod +x "$work/autostart-bin/uwsm" "$work/autostart-bin/waybar"
state="$work/home/.local/state/dotfiles/autostart.tsv"
printf '1\twaybar\tuwsm app -- waybar\n' >"$state"
HOME="$work/home" XDG_RUNTIME_DIR="$work/run" XDG_STATE_HOME="$work/home/.local/state" \
    PATH="$work/autostart-bin:$PATH" "$AUTOSTART" run >/dev/null 2>&1
for _ in {1..20}; do
    [[ -e $work/uwsm.args ]] && break
    sleep 0.05
done
if grep -qF -- "-c $work/home/.config/waybar/config.jsonc" "$state" &&
    grep -qF -- "-s $work/home/.config/waybar/style.css" "$state"; then
    pass "the autostart entry names the managed Waybar config"
else
    fail "the autostart entry was not migrated: $(cat "$state")"
fi
if grep -qF -- "-c $work/home/.config/waybar/config.jsonc" "$work/uwsm.args" 2>/dev/null; then
    pass "Waybar starts with the managed config, not a leftover file"
else
    fail "Waybar started without explicit paths: $(cat "$work/uwsm.args" 2>/dev/null)"
fi

cal_out="$("$BIN/waybar-calendar.sh" --render 2026 11)"
if grep -q 'October 2026' <<<"$cal_out" &&
    grep -q 'November 2026' <<<"$cal_out" &&
    grep -q 'December 2026' <<<"$cal_out"; then
    pass "calendar renders previous, current and next month"
else
    fail "calendar output missing expected months: $cal_out"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
((FAIL == 0))
