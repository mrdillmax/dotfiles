#!/usr/bin/env bash
# Run the shell test suite.
#
# Every test uses temporary HOME/XDG directories and stub system tools; no live
# configuration, package database or monitor is touched.
#
# Usage: tests/run.sh [pattern] [-v|--verbose] [--list]
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

VERBOSE=0
PATTERN=""
LIST=0

for arg in "$@"; do
    case "$arg" in
        -v|--verbose) VERBOSE=1 ;;
        --list)       LIST=1 ;;
        -h|--help)
            printf 'Usage: tests/run.sh [pattern] [-v|--verbose] [--list]\n'
            exit 0
            ;;
        -*) printf 'tests/run.sh: unknown option: %s\n' "$arg" >&2; exit 2 ;;
        *)
            [[ -z $PATTERN ]] || {
                printf 'tests/run.sh: only one pattern is allowed\n' >&2
                exit 2
            }
            PATTERN="$arg"
            ;;
    esac
done

shopt -s nullglob
if [[ -n $PATTERN ]]; then
    candidates=(tests/*"$PATTERN"*.sh)
else
    candidates=(tests/*.sh)
fi

# Never run this runner itself: tests/*.sh matches tests/run.sh.
tests=()
for candidate in "${candidates[@]}"; do
    [[ $candidate == tests/run.sh ]] && continue
    tests+=("$candidate")
done
unset candidate

if ((LIST)); then
    if ((${#tests[@]} == 0)); then
        printf 'no tests match %s\n' "${PATTERN:-*}" >&2
        exit 1
    fi
    printf '%s\n' "${tests[@]}"
    exit 0
fi

if ((${#tests[@]} == 0)); then
    printf 'tests/run.sh: no tests match %s\n' "${PATTERN:-*}" >&2
    exit 1
fi

total_pass=0
total_fail=0
failed=()

for test in "${tests[@]}"; do
    log="$(mktemp)"
    # Capture to a file, not a pipe: a test may leave a short-lived background
    # process that would otherwise keep the command substitution open.
    bash "$test" >"$log" 2>&1
    rc=$?
    output="$(cat -- "$log")"
    rm -f -- "$log"

    if [[ $output =~ ([0-9]+)\ passed,\ ([0-9]+)\ failed ]]; then
        total_pass=$((total_pass + BASH_REMATCH[1]))
        total_fail=$((total_fail + BASH_REMATCH[2]))
    fi

    if ((rc == 0)); then
        printf 'OK   %s\n' "$test"
        ((VERBOSE)) && printf '%s\n' "$output"
    else
        printf 'FAIL %s\n' "$test"
        printf '%s\n' "$output"
        failed+=("$test")
    fi
done

printf '\n%s: %d test file(s), %d passed, %d failed\n' \
    "$(basename "$0")" "${#tests[@]}" "$total_pass" "$total_fail"

if ((${#failed[@]} > 0)); then
    printf 'failed files: %s\n' "${failed[*]}" >&2
    exit 1
fi
exit 0
