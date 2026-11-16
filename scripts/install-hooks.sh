#!/usr/bin/env bash
# Install the repository pre-commit hook into .git/hooks.
#
# Nothing global is touched: core.hooksPath and ~/.gitconfig stay untouched.
# Existing foreign hooks are only replaced with --force (a .bak copy is kept).
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L $SOURCE ]]; do
    dir="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$dir/$SOURCE"
done
DOTFILES_DIR="$(cd -P "$(dirname "$SOURCE")/.." && pwd)"

DRY_RUN=0
FORCE=0
MODE="symlink"

usage() {
    cat <<'EOF'
Usage: scripts/install-hooks.sh [--dry-run] [--copy] [--force]

  --dry-run   show what would be installed, change nothing
  --copy      copy the hook instead of symlinking it
  --force     replace an existing foreign pre-commit hook (keeps a .bak)
  -h, --help  this help

The hook is installed into this repository's .git/hooks only.
EOF
}

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --copy)    MODE="copy" ;;
        --force)   FORCE=1 ;;
        -h|--help) usage; exit 0 ;;
        *)         printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if ! git -C "$DOTFILES_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'not a git repository: %s\n' "$DOTFILES_DIR" >&2
    exit 1
fi

git_dir="$(git -C "$DOTFILES_DIR" rev-parse --absolute-git-dir)"
configured_path="$(git -C "$DOTFILES_DIR" config --get core.hooksPath || true)"
if [[ -n $configured_path ]]; then
    printf 'core.hooksPath is set to "%s".\n' "$configured_path" >&2
    printf 'Refusing to guess: unset it yourself or install the hook there manually.\n' >&2
    printf 'This script never changes git configuration.\n' >&2
    exit 1
fi

source_hook="$DOTFILES_DIR/hooks/pre-commit"
target="$git_dir/hooks/pre-commit"

if [[ ! -f $source_hook ]]; then
    printf 'missing hook source: %s\n' "$source_hook" >&2
    exit 1
fi

if [[ -L $target ]] && [[ "$(readlink -f -- "$target")" == "$(readlink -f -- "$source_hook")" ]]; then
    printf 'pre-commit hook already installed: %s\n' "$target"
    exit 0
fi

if [[ -e $target || -L $target ]]; then
    if (( !FORCE )); then
        printf 'a different pre-commit hook already exists: %s\n' "$target" >&2
        printf 'Re-run with --force to replace it (a .bak copy is kept).\n' >&2
        exit 1
    fi
    backup="$target.bak.$(date +%Y-%m-%d_%H%M%S)"
    if ((DRY_RUN)); then
        printf '[dry-run] move %s -> %s\n' "$target" "$backup"
    else
        mv -- "$target" "$backup"
        printf 'kept previous hook: %s\n' "$backup"
    fi
fi

if ((DRY_RUN)); then
    if [[ $MODE == copy ]]; then
        printf '[dry-run] copy %s -> %s\n' "$source_hook" "$target"
    else
        printf '[dry-run] symlink %s -> %s\n' "$target" "$source_hook"
    fi
    exit 0
fi

chmod 0755 "$source_hook"
mkdir -p "$git_dir/hooks"

if [[ $MODE == copy ]]; then
    install -m 0755 -- "$source_hook" "$target"
    printf 'installed hook (copy): %s\n' "$target"
else
    ln -sfn -- "$source_hook" "$target"
    printf 'installed hook (symlink): %s -> %s\n' "$target" "$source_hook"
fi

printf 'The hook runs on the next commit. Bypass only with: git commit --no-verify\n'
