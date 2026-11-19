# Repositories Before First Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable `[multilib]` and refresh the pacman database before the guided setup installs packages.

**Architecture:** A new read-only detector (`multilib_enabled`) feeds a root-only action (`--repositories`) that reuses the existing `merge_pacman_conf` merge and then runs `pacman -Syu`. The guided setup calls that action as an unnumbered precondition before `Step 1/4`.

**Tech Stack:** Bash 5, pacman, existing `lib/system.sh` merge helpers, bash test suite.

**Spec:** `docs/superpowers/specs/2026-11-19-repositories-first-run-design.md`

## Global Constraints

- Only the guided setup and the explicit `--repositories` action prepare repositories. `1. Packages` and `--only-packages` do not.
- Do nothing when `[multilib]` is already enabled: no prompt, no upgrade.
- Refresh with `pacman -Syu`; never `pacman -Sy` alone.
- `/etc/pacman.conf` changes go through `merge_pacman_conf`: diff, backup, confirmation.
- `--dry-run` prints diff and the planned command, never calls `sudo`, never writes `/etc`.
- Numbered menu entries stay 1–4.
- Respond in Ukrainian when reporting to the user; code, comments and tests are English.

## Review Focus

- `[multilib]` commented out vs active: a commented line must not count as enabled.
- Missing/read-protected `pacman.conf`: report not enabled instead of crashing under `set -e`.
- Non-root `--repositories` without `--dry-run`: fail with a clear sudo message, do not hang on a prompt.
- Merge declined or failed: do not run `pacman -Syu` as if the repository existed; return non-zero.
- `--setup` when multilib is already enabled: skip the stage, no extra prompt.

---

### Task 1: Detect `[multilib]`

**Files:**
- Modify: `lib/system.sh` (add next to `merge_pacman_conf`)
- Test: `tests/repositories.sh` (create)

**Interfaces:**
- Produces: `multilib_enabled [conf]` — returns 0 when `conf` (default `/etc/pacman.conf`) has an uncommented `[multilib]` line, 1 otherwise.

- [ ] **Step 1: Write the failing test**

Create `tests/repositories.sh` with the shared harness (`ROOT`, `pass`, `fail`, summary at the end, `((FAIL == 0))`).

```bash
check_enabled() {
    local file="$1" expected="$2" label="$3"
    if DOTFILES_DIR="$ROOT" bash -c '
        source "$DOTFILES_DIR/lib/system.sh"
        multilib_enabled "$1"
    ' _ "$file"; then
        actual=0
    else
        actual=1
    fi
    if [[ $actual == "$expected" ]]; then pass "$label"; else fail "$label"; fi
}
tmp="$(mktemp)"
printf '[options]\nColor\n' >"$tmp"
check_enabled "$tmp" 1 "missing [multilib] counts as disabled"
printf '[options]\nColor\n#[multilib]\n#Include = /etc/pacman.d/mirrorlist\n' >"$tmp"
check_enabled "$tmp" 1 "commented [multilib] counts as disabled"
printf '[options]\nColor\n\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >"$tmp"
check_enabled "$tmp" 0 "active [multilib] counts as enabled"
rm -f -- "$tmp"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/repositories.sh`
Expected: FAIL for the active case (`multilib_enabled: command not found` exits 127, read as 1).

- [ ] **Step 3: Implement `multilib_enabled` in `lib/system.sh`**

```bash
# True when pacman.conf contains an active [multilib] section.
multilib_enabled() {
    local conf="${1:-/etc/pacman.conf}"
    [[ -r $conf ]] || return 1
    awk '/^\[multilib\][[:space:]]*$/ { found = 1 } END { exit !found }' "$conf"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/repositories.sh`
Expected: 3 passed, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add lib/system.sh tests/repositories.sh
git commit -m "feat(repositories): detect an active multilib section"
```

---

### Task 2: `--repositories` action

**Files:**
- Modify: `install.sh` (flag parse near `--system`, help text, action handling before `DO_KERNEL`)
- Modify: `lib/system.sh` (add `prepare_repositories` after `merge_pacman_conf`)
- Test: `tests/repositories.sh`

**Interfaces:**
- Consumes: `multilib_enabled`, `merge_pacman_conf`, `run`, `info`, `ok`, `warn`.
- Produces: `prepare_repositories()` — returns 0 when multilib is enabled and the database is refreshed (or would be, under `--dry-run`), 1 when it is still disabled after the merge. Flag `--repositories` sets `DO_REPOSITORIES=1`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/repositories.sh`:

```bash
log="$(mktemp)"
if (cd "$ROOT" && ./install.sh --repositories --dry-run) >"$log" 2>&1; then
    if grep -Eq 'multilib is already enabled|\[dry-run\].*merge pacman.conf' "$log"; then
        pass "--repositories --dry-run reports its plan"
    else
        fail "--repositories --dry-run printed no plan"
    fi
else
    fail "--repositories --dry-run failed"
fi
rm -f -- "$log"

if ((EUID != 0)); then
    log="$(mktemp)"
    if (cd "$ROOT" && ./install.sh --repositories) >"$log" 2>&1; then
        fail "--repositories ran without root"
    elif grep -q 'requires root' "$log"; then
        pass "--repositories needs root"
    else
        fail "--repositories failed without a root message"
    fi
    rm -f -- "$log"
fi

if ./install.sh --help 2>&1 | grep -q -- '--repositories'; then
    pass "--repositories is documented in --help"
else
    fail "--repositories is missing from --help"
fi
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/repositories.sh`
Expected: FAIL: unknown option `--repositories`.

- [ ] **Step 3: Implement the flag, the guard and the action**

In `install.sh`:

- Declare `DO_REPOSITORIES=0` beside `DO_SYSTEM=0`.
- Parse `--repositories) DO_REPOSITORIES=1; HAS_ACTION=1 ;;`.
- Handle it after the log and backup paths exist, immediately before `if (( DO_KERNEL )); then`:

```bash
if (( DO_REPOSITORIES )); then
    if (( EUID != 0 )) && (( !DRY_RUN )); then
        die "repositories require root: sudo $DOTFILES_DIR/install.sh --repositories"
    fi
    prepare_repositories
    exit $?
fi
```

- Add to the help under `System`:
  `--repositories        enable [multilib] and refresh the database (sudo)`.

In `lib/system.sh`:

```bash
prepare_repositories() {
    if multilib_enabled; then
        ok "multilib is already enabled; nothing to do"
        return 0
    fi

    info "enabling [multilib] in /etc/pacman.conf and refreshing the database"
    merge_pacman_conf

    if (( !DRY_RUN )) && ! multilib_enabled; then
        warn "[multilib] is still disabled; package installs would fail"
        return 1
    fi

    run pacman -Syu
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/repositories.sh && bash -n install.sh && shellcheck -x install.sh lib/system.sh`
Expected: all tests pass, no shellcheck output.

- [ ] **Step 5: Commit**

```bash
git add install.sh lib/system.sh tests/repositories.sh
git commit -m "feat(repositories): enable multilib and refresh the database"
```

---

### Task 3: Setup stage and documentation

**Files:**
- Modify: `install.sh` (`run_setup`)
- Modify: `README.md`, `README.uk.md`
- Test: `tests/repositories.sh`

**Interfaces:**
- Consumes: `multilib_enabled`, `--repositories`.
- Produces: guided setup runs `--repositories` before `--only-packages`.

- [ ] **Step 1: Write the failing order test**

Append to `tests/repositories.sh`:

```bash
repo_line="$(grep -n -- '--repositories' "$ROOT/install.sh" | grep -v 'die ' | tail -1 | cut -d: -f1)"
packages_line="$(grep -n -- '--only-packages' "$ROOT/install.sh" | grep 'run_setup\|setup_stage\|install.sh"' | tail -1 | cut -d: -f1)"
setup_start="$(grep -n '^run_setup()' "$ROOT/install.sh" | cut -d: -f1)"
if [[ -n $repo_line && -n $packages_line ]] && ((repo_line > setup_start && repo_line < packages_line)); then
    pass "setup prepares repositories before packages"
else
    fail "setup order is repositories ($repo_line) then packages ($packages_line)"
fi
```

If that grep is ambiguous while implementing, replace it with `awk` over the `run_setup` body instead of loosening the assertion.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/repositories.sh`
Expected: FAIL: setup prepares repositories before packages.

- [ ] **Step 3: Implement the stage**

In `run_setup`, before the packages stage:

```bash
if ! multilib_enabled; then
    local -a repo_cmd=(--repositories)
    (( DRY_RUN )) && repo_cmd+=(--dry-run)
    if (( DRY_RUN || EUID == 0 )); then
        setup_stage "Repositories — enable [multilib] and refresh the package database?" \
            bash "$DOTFILES_DIR/install.sh" "${repo_cmd[@]}" || return $?
    else
        setup_stage "Repositories — enable [multilib] and refresh the package database (sudo)?" \
            sudo bash "$DOTFILES_DIR/install.sh" "${repo_cmd[@]}" || return $?
    fi
else
    info "multilib is already enabled; repositories step skipped"
fi
```

Change the opening line to
`info "First-time setup: repositories -> packages -> configuration -> system -> kernel"`.

- [ ] **Step 4: Update the READMEs**

In `README.md` and `README.uk.md`, wherever the first run order is listed:

- Put repositories before packages.
- Note that it runs only when `[multilib]` is missing, and that it enables `[multilib]` and refreshes the database with `pacman -Syu`.
- Add `--repositories` to the command/flag list next to `--system`.

- [ ] **Step 5: Run the repository checks**

Run: `make check`
Expected: all tests pass, audit without FAIL.

- [ ] **Step 6: Commit**

```bash
git add install.sh README.md README.uk.md tests/repositories.sh
git commit -m "feat(setup): prepare repositories before the first package install"
```
