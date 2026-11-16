#!/usr/bin/env bash
# Convenience wrapper: run the mouse tuner from a checkout of this repository.
# After installation the same tool is available as ~/.local/bin/mouse-tune.sh.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$repo/modules/mouse-sensitivity/home/.local/bin/mouse-tune.sh" --repo "$repo" "$@"
