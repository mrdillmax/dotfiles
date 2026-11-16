# shellcheck shell=bash
# Secret scanner used by scripts/audit.sh.
[[ -n ${_DOTFILES_SECRETS:-} ]] && return 0
_DOTFILES_SECRETS=1

# Patterns that should never appear in a committed file.
SECRET_PATTERNS=(
    'sk-[A-Za-z0-9_-]{20,}'
    'gh[pousr]_[A-Za-z0-9]{20,}'
    'github_pat_[A-Za-z0-9_]{20,}'
    'AKIA[0-9A-Z]{16}'
    'AIza[0-9A-Za-z_-]{35}'
    'xox[baprs]-[A-Za-z0-9-]{10,}'
    '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----'
    '(api[_-]?key|access[_-]?token|client[_-]?secret|password)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{12,}["'"'"']'
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

# Files that must be excluded from the repository entirely.
check_forbidden_paths() {
    local root="${1:-$DOTFILES_DIR}"
    local rel found=0

    for rel in \
        pihole.toml \
        .config/rclone/rclone.conf \
        .config/rustdesk \
        .config/opencode \
        .config/omniroute \
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
