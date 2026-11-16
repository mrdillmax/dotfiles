#!/usr/bin/env bash
# Pull live configuration changes back into this repository.
#
# Direction is always system -> repository. Nothing under $HOME is modified.
# Generated matugen output and secret paths are never pulled.
#
# Commands:
#   status [module]   list files where the live copy differs from the repo
#   diff   [module]   show unified diffs for those files
#   pull   [module]   write the live content back (diff + confirm + secret scan)
#   packages          compare installed explicit packages with packages/*.txt
#
# A pre-pull copy of every repository file is stored under
# ~/.local/state/dotfiles/sync-backup/<timestamp>/ and listed in manifest.tsv.
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTFILES_DIR

DRY_RUN=0
ASSUME_YES=0

# shellcheck source=lib/common.sh
source "$DOTFILES_DIR/lib/common.sh"
# shellcheck source=lib/secrets.sh
source "$DOTFILES_DIR/lib/secrets.sh"
# shellcheck source=lib/tui.sh
source "$DOTFILES_DIR/lib/tui.sh"

# The live tree is normally the passwd home. Tests (and unusual setups) can
# point it elsewhere without touching anything outside that temporary tree.
if [[ -n ${DOTFILES_SYNC_HOME:-} ]]; then
    REAL_HOME="$DOTFILES_SYNC_HOME"
else
    REAL_HOME="$(real_home)"
fi
[[ -n $REAL_HOME ]] || die "cannot determine home directory"
export REAL_HOME

STATE_DIR="${XDG_STATE_HOME:-$REAL_HOME/.local/state}/dotfiles"

COMMAND=""
TARGET=""
PACKAGES_LIST=0
SYNC_TMPDIR=""

cleanup() {
    if [[ -n $SYNC_TMPDIR ]]; then
        rm -rf -- "$SYNC_TMPDIR"
    fi
}
trap cleanup EXIT

usage() {
    cat <<'EOF'
Usage: scripts/sync.sh <command> [target] [options]

Commands:
  status [module]   list files where the live copy differs from the repository
  diff   [module]   show unified diffs for those files
  pull   [module]   write live content back into the repository
  packages          compare installed explicit packages with packages/*.txt

Target:
  all (default) or a module name from modules/ (hypr, waybar, theming, ...)

Options:
  --dry-run         show what pull would write, change nothing
  --yes, -y         do not ask for confirmation (pull)
  --list            with packages: print the full lists
  -h, --help        this help

Environment:
  DOTFILES_SYNC_HOME   override the live home directory (tests only)
  XDG_STATE_HOME       where sync-backup/<timestamp>/ is created
EOF
}

while (($#)); do
    case "$1" in
        status|diff|pull|packages)
            if [[ -n $COMMAND ]]; then
                die "only one command is allowed (got '$COMMAND' and '$1')"
            fi
            COMMAND="$1"
            ;;
        --dry-run) DRY_RUN=1 ;;
        --yes|-y)  ASSUME_YES=1 ;;
        --list)    PACKAGES_LIST=1 ;;
        -h|--help) usage; exit 0 ;;
        -*)        die "unknown option: $1 (see --help)" ;;
        *)
            if [[ -n $TARGET ]]; then
                die "only one target is allowed (got '$TARGET' and '$1')"
            fi
            TARGET="$1"
            ;;
    esac
    shift
done

[[ -n $COMMAND ]] || { usage >&2; exit 2; }

if [[ $COMMAND == packages ]]; then
    [[ -z $TARGET ]] || die "the packages command takes no target"
elif [[ -n $TARGET && $TARGET != all && ! -d $DOTFILES_DIR/modules/$TARGET ]]; then
    die "unknown module: $TARGET (try status all)"
fi

# ---------------------------------------------------------------- helpers ----

sync_modules() {
    local dir
    for dir in "$DOTFILES_DIR"/modules/*/; do
        basename "$dir"
    done | sort
}

sync_firefox_profile_dir() {
    local candidate
    for candidate in "$REAL_HOME"/.config/mozilla/firefox/*.default-release; do
        if [[ -d $candidate ]]; then
            basename "$candidate"
            return 0
        fi
    done
    printf 'default-release\n'
}

sync_obsidian_vault() {
    local candidate
    for candidate in "$REAL_HOME"/Obsidian/*/; do
        if [[ -d $candidate ]]; then
            basename "$candidate"
            return 0
        fi
    done
    printf 'Obsidian\n'
}

# Repository-relative path -> path relative to $HOME.
sync_live_rel() {
    local rel="$1"

    rel="${rel//@FIREFOX_PROFILE_DIR@/$(sync_firefox_profile_dir)}"
    rel="${rel//@OBSIDIAN_VAULT@/$(sync_obsidian_vault)}"
    if [[ $rel == *.in ]]; then
        rel="${rel%.in}"
    fi
    printf '%s' "$rel"
}

# Print "module<TAB>repo_rel<TAB>live_rel<TAB>template" for every pullable file.
sync_entries() {
    local module="$1"
    local root="$DOTFILES_DIR/modules/$module/home"
    local src rel repo_rel template

    [[ -d $root ]] || return 0

    while IFS= read -r src; do
        rel="${src#"$root"/}"
        repo_rel="modules/$module/home/$rel"

        case "$repo_rel" in
            personal/*|*/personal/*) continue ;;
        esac
        is_generated_output_path "$repo_rel" && continue
        is_forbidden_path "$repo_rel" && continue
        is_forbidden_path "$rel" && continue

        template=0
        [[ $rel == *.in ]] && template=1

        printf '%s\t%s\t%s\t%s\n' \
            "$module" "$repo_rel" "$(sync_live_rel "$rel")" "$template"
    done < <(find "$root" -type f | sort)
}

sync_selected_modules() {
    local module

    if [[ -z $TARGET || $TARGET == all ]]; then
        sync_modules
        return 0
    fi

    if [[ ! -d $DOTFILES_DIR/modules/$TARGET ]]; then
        die "unknown module: $TARGET (try status all)"
    fi
    printf '%s\n' "$TARGET"
}

sync_sed_escape() {
    printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

# Writes the repository-shaped content (placeholders restored) to $2.
# sed keeps trailing newlines intact, unlike a bash command substitution.
sync_reverse_render() {
    local live="$1" out="$2" template="$3"
    local profile vault

    if ((!template)); then
        cp -- "$live" "$out"
        return 0
    fi

    profile="$(sync_firefox_profile_dir)"
    vault="$(sync_obsidian_vault)"

    sed \
        -e "s|$(sync_sed_escape "$REAL_HOME")|@HOME@|g" \
        -e "s|$(sync_sed_escape "$profile")|@FIREFOX_PROFILE_DIR@|g" \
        -e "s|$(sync_sed_escape "$vault")|@OBSIDIAN_VAULT@|g" \
        -- "$live" >"$out"
}

# clean | clean-copy | modified | modified-link | missing | broken
sync_state() {
    local live="$1" repo="$2" template="$3"
    local tmp state

    if [[ -L $live && ! -e $live ]]; then
        printf 'broken'
        return 0
    fi
    if [[ ! -e $live ]]; then
        printf 'missing'
        return 0
    fi
    if [[ ! -r $live ]]; then
        printf 'unreadable'
        return 0
    fi

    tmp="$(mktemp)"
    sync_reverse_render "$live" "$tmp" "$template" 2>/dev/null || {
        rm -f -- "$tmp"
        printf 'unreadable'
        return 0
    }

    if cmp -s -- "$tmp" "$repo"; then
        if [[ -L $live ]]; then
            state=clean
        else
            state=clean-copy
        fi
    else
        if [[ -L $live ]]; then
            state=modified-link
        else
            state=modified
        fi
    fi

    rm -f -- "$tmp"
    printf '%s' "$state"
}

# Emit one line per file that needs attention.
sync_changes() {
    local module repo_rel live_rel template live state

    while IFS= read -r module; do
        while IFS=$'\t' read -r _ repo_rel live_rel template; do
            live="$REAL_HOME/$live_rel"
            state="$(sync_state "$live" "$DOTFILES_DIR/$repo_rel" "$template")"
            case "$state" in
                clean|clean-copy) continue ;;
            esac
            printf '%s\t%s\t%s\t%s\n' "$module" "$repo_rel" "$live_rel" "$state"
        done < <(sync_entries "$module")
    done < <(sync_selected_modules)
}

print_status() {
    local module repo_rel live_rel state
    local rows=() total=0

    while IFS=$'\t' read -r module repo_rel live_rel state; do
        rows+=("$(printf '%-16s %-14s ~/%s' "$module" "$state" "$live_rel")")
        total=$((total + 1))
    done < <(sync_changes)

    if ((total == 0)); then
        printf 'Repository and live configuration are in sync.\n'
        return 0
    fi

    if ((DRY_RUN)); then
        : # status is read-only; the flag is accepted for consistency
    fi

    printf '%-16s %-14s %s\n' "MODULE" "STATE" "LIVE FILE"
    printf '%s\n' "${rows[@]}"
    printf '\n%d file(s) differ. Use "sync.sh diff" to inspect, "sync.sh pull" to copy back.\n' "$total"
}

show_diff() {
    local module repo_rel live_rel state
    local live repo template tmp shown=0

    while IFS=$'\t' read -r module repo_rel live_rel state; do
        live="$REAL_HOME/$live_rel"
        repo="$DOTFILES_DIR/$repo_rel"
        template=0
        [[ $repo_rel == *.in ]] && template=1

        case "$state" in
            missing)
                printf '\n== %s: %s ==\n' "$module" "$repo_rel"
                printf 'live file is missing: ~/%s\n' "$live_rel"
                shown=$((shown + 1))
                continue
                ;;
            broken)
                printf '\n== %s: %s ==\n' "$module" "$repo_rel"
                printf 'live symlink is broken: ~/%s\n' "$live_rel"
                shown=$((shown + 1))
                continue
                ;;
            unreadable)
                printf '\n== %s: %s ==\n' "$module" "$repo_rel"
                printf 'live file is not readable: ~/%s\n' "$live_rel"
                shown=$((shown + 1))
                continue
                ;;
        esac

        tmp="$(mktemp)"
        sync_reverse_render "$live" "$tmp" "$template" || {
            rm -f -- "$tmp"
            continue
        }

        printf '\n== %s: %s ==\n' "$module" "$repo_rel"
        diff -u --label "repo/$repo_rel" --label "live/~/$live_rel" \
            -- "$repo" "$tmp" || true
        rm -f -- "$tmp"
        shown=$((shown + 1))
    done < <(sync_changes)

    if ((shown == 0)); then
        printf 'Repository and live configuration are in sync.\n'
    fi
}

pull_changes() {
    local module repo_rel live_rel state
    local live repo template tmp work
    local -a p_module=() p_repo_rel=() p_live_rel=() p_state=() p_content=()
    local blocked=0 count=0 i backup_dir manifest

    work="$(mktemp -d)"
    SYNC_TMPDIR="$work"

    while IFS=$'\t' read -r module repo_rel live_rel state; do
        case "$state" in
            missing|broken|unreadable)
                warn "cannot pull $repo_rel: live file ~/$live_rel is $state"
                continue
                ;;
        esac

        live="$REAL_HOME/$live_rel"
        repo="$DOTFILES_DIR/$repo_rel"
        template=0
        [[ $repo_rel == *.in ]] && template=1

        count=$((count + 1))
        tmp="$work/$count"

        if ! sync_reverse_render "$live" "$tmp" "$template"; then
            warn "cannot read live file: ~/$live_rel"
            count=$((count - 1))
            continue
        fi

        p_module+=("$module")
        p_repo_rel+=("$repo_rel")
        p_live_rel+=("$live_rel")
        p_state+=("$state")
        p_content+=("$tmp")
    done < <(sync_changes)

    if ((count == 0)); then
        printf 'Repository and live configuration are in sync.\n'
        return 0
    fi

    for i in "${!p_repo_rel[@]}"; do
        repo="$DOTFILES_DIR/${p_repo_rel[$i]}"
        printf '\n== %s: %s ==\n' "${p_module[$i]}" "${p_repo_rel[$i]}"
        diff -u --label "repo/${p_repo_rel[$i]}" --label "live/~/${p_live_rel[$i]}" \
            -- "$repo" "${p_content[$i]}" || true
    done

    # Refuse the whole pull when any proposed file contains a secret.
    for i in "${!p_content[@]}"; do
        if ! scan_secret_content "${p_content[$i]}"; then
            printf '\n%sBLOCK%s %s contains a possible secret; nothing was written.\n' \
                "$C_RED" "$C_RESET" "${p_repo_rel[$i]}" >&2
            blocked=1
        fi
    done
    ((blocked)) && return 1

    if ((DRY_RUN)); then
        printf '\n[dry-run] would write %d file(s) back to %s\n' "$count" "$DOTFILES_DIR"
        return 0
    fi

    if ! tui_confirm "Write $count file(s) back to the repository?" no; then
        printf 'pull cancelled\n'
        return 0
    fi

    backup_dir="$STATE_DIR/sync-backup/$(date +%Y-%m-%d_%H%M%S)"
    mkdir -p -- "$backup_dir"
    manifest="$backup_dir/manifest.tsv"
    printf 'target\tbackup\n' >"$manifest"

    for i in "${!p_repo_rel[@]}"; do
        repo="$DOTFILES_DIR/${p_repo_rel[$i]}"
        mkdir -p -- "$(dirname "$repo")"
        if [[ -e $repo ]]; then
            mkdir -p -- "$backup_dir/$(dirname "${p_repo_rel[$i]}")"
            cp -a -- "$repo" "$backup_dir/${p_repo_rel[$i]}"
            printf '%s\t%s\n' "$repo" "$backup_dir/${p_repo_rel[$i]}" >>"$manifest"
        fi
        cat -- "${p_content[$i]}" >"$repo"
        ok "pulled ${p_repo_rel[$i]}"
    done

    printf '\n%s file(s) written. Pre-pull copy: %s\n' "$count" "$backup_dir"
    printf 'Review with "git diff" and commit when satisfied.\n'
}

# --------------------------------------------------------------- packages ----

sync_packages() {
    local file line pkg
    local -A listed_all=() listed_main=()
    local -a installed=() missing_repo=() missing_system=()
    local main_count=0 all_count=0

    while IFS= read -r file; do
        while IFS= read -r line; do
            [[ -z $line || $line == \#* ]] && continue
            if [[ ${file##*/} == alternatives.txt ]]; then
                pkg="${line%%$'\t'*}"
                pkg="${pkg%%[[:space:]]*}"
            else
                pkg="${line%%[[:space:]]*}"
            fi
            [[ -n $pkg ]] || continue
            listed_all["$pkg"]=1
            all_count=$((all_count + 1))
            if [[ ${file##*/} != alternatives.txt ]]; then
                listed_main["$pkg"]=1
                main_count=$((main_count + 1))
            fi
        done <"$file"
    done < <(find "$DOTFILES_DIR/packages" -maxdepth 1 -type f -name '*.txt' | sort)

    if ! command -v pacman >/dev/null 2>&1; then
        warn "pacman is not available; package comparison skipped"
        return 0
    fi

    mapfile -t installed < <(pacman -Qqe | sort)

    for pkg in "${installed[@]}"; do
        [[ -n ${listed_all[$pkg]:-} ]] || missing_repo+=("$pkg")
    done
    for pkg in "${!listed_main[@]}"; do
        if ! pacman -Qq "$pkg" >/dev/null 2>&1; then
            missing_system+=("$pkg")
        fi
    done

    printf 'Packages: %d installed explicit, %d listed (%d main + %d alternatives)\n' \
        "${#installed[@]}" "$all_count" "$main_count" "$((all_count - main_count))"

    if ((${#missing_repo[@]})); then
        printf '\nInstalled but not listed in packages/*.txt (%d):\n' "${#missing_repo[@]}"
        printf '  %s\n' "${missing_repo[@]}"
    else
        printf '\nOK installed packages are all listed in packages/*.txt\n'
    fi

    if ((${#missing_system[@]})); then
        printf '\nListed in packages/*.txt but not installed (%d):\n' "${#missing_system[@]}"
        printf '  %s\n' "${missing_system[@]}"
    fi

    if ((PACKAGES_LIST)); then
        printf '\nInstalled explicit packages:\n'
        printf '  %s\n' "${installed[@]}"
    fi

    ((${#missing_repo[@]} == 0 && ${#missing_system[@]} == 0))
}

# ------------------------------------------------------------------ main -----

case "$COMMAND" in
    status)   print_status ;;
    diff)     show_diff ;;
    pull)     pull_changes ;;
    packages) sync_packages ;;
esac
