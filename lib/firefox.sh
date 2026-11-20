# shellcheck shell=bash
# Firefox profile discovery.
#
# Firefox installs its profile in one of three places depending on how it was
# installed. The chrome CSS must land in the profile that exists, so the caller
# discovers it instead of assuming a directory name.
[[ -n ${_DOTFILES_FIREFOX:-} ]] && return 0
_DOTFILES_FIREFOX=1

# Candidate profile roots, most likely first.
firefox_profile_roots() {
    local home="${REAL_HOME:-$HOME}"
    printf '%s\n' \
        "$home/.config/mozilla/firefox" \
        "$home/.mozilla/firefox" \
        "$home/.var/app/org.mozilla.firefox/.mozilla/firefox"
}

# Print the profile directory name, or fail when there is no profile yet.
firefox_profile_dir() {
    local root candidate
    while IFS= read -r root; do
        for candidate in "$root"/*.default-release "$root"/*.default; do
            [[ -d $candidate ]] || continue
            basename "$candidate"
            return 0
        done
    done < <(firefox_profile_roots)
    return 1
}

# Print the directory that contains the discovered profile.
firefox_profile_root() {
    local name root
    name="$(firefox_profile_dir)" || return 1
    while IFS= read -r root; do
        if [[ -d $root/$name ]]; then
            printf '%s\n' "$root"
            return 0
        fi
    done < <(firefox_profile_roots)
    return 1
}
