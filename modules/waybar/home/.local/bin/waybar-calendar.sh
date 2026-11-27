#!/usr/bin/env bash
# Interactive 3-month calendar popup for Waybar's clock module.
set -uo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
THEME="$CONFIG_HOME/rofi/control-center.rasi"
[[ -r $THEME ]] || THEME="$CONFIG_HOME/rofi/launcher.rasi"

render_three_months() {
    local year="$1" month="$2"
    python3 - "$year" "$month" <<'PY'
import calendar
import datetime
import html
import sys

year = int(sys.argv[1])
month = int(sys.argv[2])
today = datetime.date.today()
cal = calendar.Calendar(firstweekday=0)  # Monday first

def shift_month(y, m, delta):
    idx = (y * 12 + (m - 1)) + delta
    return idx // 12, (idx % 12) + 1

def format_month(y, m):
    title = f"{calendar.month_name[m]} {y}".center(20)
    lines = [f"<b>{html.escape(title)}</b>"]
    lines.append("<span alpha='70%'>Mo Tu We Th Fr Sa Su</span>")
    for week in cal.monthdayscalendar(y, m):
        cells = []
        for day in week:
            if day == 0:
                cells.append("  ")
            elif y == today.year and m == today.month and day == today.day:
                cells.append(f"<b><u>{day:2d}</u></b>")
            else:
                cells.append(f"{day:2d}")
        lines.append(" ".join(cells))
    while len(lines) < 8:
        lines.append(" " * 20)
    return lines

blocks = [format_month(*shift_month(year, month, d)) for d in (-1, 0, 1)]
out = []
for row in range(8):
    out.append("   ".join(b[row] for b in blocks))
print("<span font='JetBrainsMono Nerd Font 11'>" + "\n".join(out) + "</span>")
PY
}

shift_ym() {
    local year="$1" month="$2" delta="$3"
    python3 -c '
import sys
y, m, d = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
idx = (y * 12 + (m - 1)) + d
print(f"{idx // 12} {(idx % 12) + 1}")
' "$year" "$month" "$delta"
}

if [[ ${1:-} == --render ]]; then
    read -r y m < <(date +'%Y %m')
    render_three_months "${2:-$y}" "${3:-$((10#$m))}"
    exit 0
fi

command -v rofi >/dev/null 2>&1 || exit 1
read -r cur_year cur_month < <(date +'%Y %m')
cur_month=$((10#$cur_month))
year="$cur_year"
month="$cur_month"

while :; do
    mesg="$(render_three_months "$year" "$month")"
    args=(-dmenu -i -p "" -no-custom -no-fixed-num-lines -markup-rows)
    [[ -r $THEME ]] && args+=(-theme "$THEME")
    args+=(-mesg "$mesg" -theme-str 'window { width: 760px; } prompt { enabled: false; } inputbar { enabled: false; } listview { lines: 3; } message { padding: 12px; }')
    choice="$(printf '%s\n' \
        "<span font='JetBrainsMono Nerd Font 12'></span>  Previous month" \
        "<span font='JetBrainsMono Nerd Font 12'></span>  Today" \
        "<span font='JetBrainsMono Nerd Font 12'></span>  Next month" \
        | rofi "${args[@]}")" || exit 0
    case "$choice" in
        *Previous*) read -r year month < <(shift_ym "$year" "$month" -1) ;;
        *Today*)    year="$cur_year"; month="$cur_month" ;;
        *Next*)     read -r year month < <(shift_ym "$year" "$month" 1) ;;
        *) exit 0 ;;
    esac
done
