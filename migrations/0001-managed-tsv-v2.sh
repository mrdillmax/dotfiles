#!/usr/bin/env bash
# managed.tsv v2 — add digest and original columns
set -euo pipefail
: "${DOTFILES_DIR:?DOTFILES_DIR is not set}"
# shellcheck source=/dev/null
source "$DOTFILES_DIR/lib/common.sh"

state="${STATE_FILE:-${STATE_DIR:?}/managed.tsv}"
[[ -r $state ]] || exit 0

# Every row already has five columns: nothing to do.
if awk -F'\t' 'NF > 0 && NF < 5 { exit 1 }' "$state"; then
    exit 0
fi

mode="$(stat -c %a "$state" 2>/dev/null || true)"
tmp="$(mktemp "$state.XXXXXX")"
awk -F'\t' -v OFS='\t' '
    NF == 0 { next }
    { while (NF < 5) $(NF + 1) = "-"; print }
' "$state" >"$tmp"

backup_path "$state"
mv -f -- "$tmp" "$state"
state_file_permissions "$state" "$mode"
