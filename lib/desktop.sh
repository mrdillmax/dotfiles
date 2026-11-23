# shellcheck shell=bash
# Desktop database and default-application refresh.
[[ -n ${_DOTFILES_DESKTOP:-} ]] && return 0
_DOTFILES_DESKTOP=1

# Rebuild the MIME/app caches and give mpv the video associations only when
# the user has no default yet. Never overwrites an existing choice.
refresh_desktop_database() {
    local mime
    if (( ${DRY_RUN:-0} )); then
        return 0
    fi

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$REAL_HOME/.local/share/applications" >/dev/null 2>&1 || true
        update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    fi
    if command -v kbuildsycoca6 >/dev/null 2>&1; then
        kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    fi

    command -v xdg-mime >/dev/null 2>&1 || return 0
    command -v mpv >/dev/null 2>&1 || return 0
    for mime in video/mp4 video/x-matroska video/webm; do
        [[ -n $(xdg-mime query default "$mime" 2>/dev/null) ]] && continue
        xdg-mime default mpv.desktop "$mime" || true
    done
}
