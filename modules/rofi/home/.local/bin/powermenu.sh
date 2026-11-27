#!/usr/bin/env bash
dir="$HOME/.config/rofi"
theme='powermenu'

uptime="$(uptime -p | sed -e 's/up //g')"

shutdown=''
reboot=''
logout='󰈆'
yes=''
no=''

rofi_cmd() {
    rofi -dmenu \
        -p "Uptime: $uptime" \
        -mesg "Uptime: $uptime" \
        -theme-str 'window { width: 400px; } listview { columns: 3; lines: 1; }' \
        -theme-str 'mainbox { children: [ "message", "listview" ]; }' \
        -theme-str 'element-text { horizontal-align: 0.44; }' \
        -theme "${dir}/${theme}.rasi"
}

confirm_cmd() {
    rofi -theme-str 'window { location: center; anchor: center; fullscreen: false; width: 350px; }' \
        -theme-str 'mainbox { children: [ "message", "listview" ]; }' \
        -theme-str 'listview { columns: 2; lines: 1; }' \
        -theme-str 'element-text { horizontal-align: 0.5; }' \
        -theme-str 'textbox { horizontal-align: 0.5; }' \
        -dmenu \
        -p 'Confirmation' \
        -mesg 'Are you Sure?' \
        -theme "${dir}/${theme}.rasi"
}

confirm_exit() {
    echo -e "$yes\n$no" | confirm_cmd
}

run_rofi() {
    echo -e "$logout\n$reboot\n$shutdown" | rofi_cmd
}

run_hyprshutdown() {
    local post_cmd="$1"
    # --no-fork keeps hyprshutdown attached to the launcher instead of
    # daemonising, so it cannot leave a stray window behind.
    if command -v systemd-run &>/dev/null && systemctl --user is-active --quiet 'wayland-wm@*' 2>/dev/null; then
        systemd-run --user --scope --quiet hyprshutdown --no-fork --post-cmd "$post_cmd"
    else
        hyprshutdown --no-fork --post-cmd "$post_cmd"
    fi
}

run_cmd() {
    selected="$(confirm_exit)"
    if [[ "$selected" == "$yes" ]]; then
        if [[ $1 == '--shutdown' ]]; then
            if command -v hyprshutdown &>/dev/null; then
                run_hyprshutdown "systemctl poweroff"
            else
                systemctl poweroff
            fi
        elif [[ $1 == '--reboot' ]]; then
            if command -v hyprshutdown &>/dev/null; then
                run_hyprshutdown "systemctl reboot"
            else
                systemctl reboot
            fi
        elif [[ $1 == '--logout' ]]; then
                uwsm stop
        fi
    else
        exit 0
    fi
}

# Sourced by tests for the action functions; only the script drives rofi.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    chosen="$(run_rofi)"
    case ${chosen} in
        "$shutdown")
            run_cmd --shutdown
            ;;
        "$reboot")
            run_cmd --reboot
            ;;
        "$logout")
            run_cmd --logout
            ;;
    esac
fi
