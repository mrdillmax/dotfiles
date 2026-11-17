# shellcheck shell=bash
# Secret scanner used by scripts/audit.sh.
[[ -n ${_DOTFILES_SECRETS:-} ]] && return 0
_DOTFILES_SECRETS=1

# Patterns that should never appear in a committed file.
SECRET_PATTERNS=(
    'sk-[A-Za-z0-9_-]{20,}'
    'gh[pousr]_[A-Za-z0-9]{20,}'
    'github_pat_[A-Za-z0-9_]{20,}'
    'glpat-[A-Za-z0-9_-]{20,}'
    'npm_[A-Za-z0-9]{30,}'
    'AKIA[0-9A-Z]{16}'
    'AIza[0-9A-Za-z_-]{35}'
    'xox[baprs]-[A-Za-z0-9-]{10,}'
    'AGE-SECRET-KEY-1[0-9A-Z]{50,}'
    '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----'
    'pwhash[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{4,}["'"'"']'
    'totp_secret[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{4,}["'"'"']'
    'cli_pw[[:space:]]*[:=][[:space:]]*true'
    '(api[_-]?key|access[_-]?token|client[_-]?secret|auth[_-]?token|password|passwd|secret)[[:space:]]*[:=][[:space:]]*["'"'"']?[^"'"'"'$@<%{ ][^"'"'"']{7,}'
)

secret_files() {
    local root="${1:-$DOTFILES_DIR}"

    find "$root" \
        -path "$root/.git" -prune -o \
        -type f \
        ! -name '*.md' \
        ! -name '*.example' \
        ! -name '*.txt' \
        ! -name 'LICENSE*' \
        ! -path "$root/lib/secrets.sh" \
        ! -path "$root/scripts/audit.sh" \
        ! -path "$root/tests/*" \
        -print
}

# Prints "file:line:match" for every suspicious line.
scan_secrets() {
    local root="${1:-$DOTFILES_DIR}"
    local file pattern found=0

    while IFS= read -r file; do
        for pattern in "${SECRET_PATTERNS[@]}"; do
            if grep -nIiE -- "$pattern" "$file" 2>/dev/null; then
                found=1
            fi
        done
    done < <(secret_files "$root")

    return "$found"
}

# Scan a single candidate file, regardless of its extension. Used before a
# sync pull writes live content back into the repository.
scan_secret_content() {
    local file="$1"
    local pattern found=0

    [[ -r $file ]] || return 1

    case "${file##*/}" in
        *.md|*.example) return 0 ;;
    esac

    for pattern in "${SECRET_PATTERNS[@]}"; do
        if grep -nIiE -- "$pattern" "$file" 2>/dev/null; then
            found=1
        fi
    done

    return "$found"
}

# Files that must be excluded from the repository entirely.
check_forbidden_paths() {
    local root="${1:-$DOTFILES_DIR}"
    local rel found=0

    for rel in \
        pihole.toml \
        .config/rclone/rclone.conf \
        .config/rustdesk \
        .config/opencode \
        personal/mimeapps.list; do
        if [[ -e $root/$rel ]]; then
            # An ignored file may live in the working tree without being part
            # of the repository; only tracked forbidden files are a failure.
            if command -v git >/dev/null 2>&1 \
                && git -C "$root" rev-parse --git-dir >/dev/null 2>&1 \
                && git -C "$root" check-ignore -q "$root/$rel"; then
                continue
            fi
            printf 'forbidden path present: %s\n' "$root/$rel"
            found=1
        fi
    done

    return "$found"
}

# Paths that must never enter the repository, regardless of .gitignore.
# The pre-commit hook uses this on staged paths; audit.sh uses it on the tree.
is_forbidden_path() {
    local path="${1#./}"
    local base="${path##*/}"

    case "$path" in
        personal/*|*/.config/opencode/*|*/.config/rustdesk/*)
            return 0
            ;;
    esac

    case "$base" in
        pihole.toml) return 0 ;;
        pihole.toml.*) [[ $base == pihole.toml.example ]] || return 0 ;;
        rclone.conf|id_rsa|id_ed25519) return 0 ;;
        .env|.env.*|*.key|*.pem|*.kdbx|*.ovpn|*.token|*.secret|*.pacnew|*.pacsave)
            return 0
            ;;
    esac

    return 1
}

# Output produced by matugen; templates are the source of truth.
is_generated_output_path() {
    local path="${1#./}"

    case "$path" in
        */matugen/templates/*) return 1 ;;
        modules/hypr/home/.config/hypr/colors.lua|\
        modules/waybar/home/.config/waybar/colors.css|\
        modules/rofi/home/.config/rofi/colors.rasi|\
        modules/kitty/home/.config/kitty/themes/Matugen.conf|\
        modules/theming/home/.config/gtk-3.0/colors.css|\
        modules/theming/home/.config/gtk-4.0/colors.css|\
        modules/dunst/home/.config/dunst/dunstrc|\
        modules/theming/home/.config/qt5ct/colors/*|\
        modules/theming/home/.config/qt6ct/colors/*|\
        modules/theming/home/.local/share/color-schemes/*|\
        modules/apps/home/.config/btop/themes/*|\
        modules/apps/home/.config/micro/colorschemes/*|\
        modules/apps/home/.config/spicetify/Themes/Sleek/color.ini|\
        modules/apps/home/.config/vesktop/themes/*)
            return 0
            ;;
    esac

    case "${path##*/}" in
        colors.lua|colors.css|colors.rasi|Matugen.conf) return 0 ;;
    esac

    return 1
}

# Scan only the staged (index) content. Prints "file:line:match" and returns
# nonzero when something matched, mirroring scan_secrets().
scan_staged_secrets() {
    local root="${1:-$DOTFILES_DIR}"
    local pattern out found=0

    for pattern in "${SECRET_PATTERNS[@]}"; do
        if out="$(git -C "$root" grep --cached -nIiE -e "$pattern" -- \
            . \
            ':(exclude)lib/secrets.sh' \
            ':(exclude)scripts/audit.sh' \
            ':(exclude)hooks/pre-commit' \
            ':(exclude)tests' \
            ':(exclude)*.md' 2>/dev/null)"; then
            printf '%s\n' "$out"
            found=1
        fi
    done

    return "$found"
}
