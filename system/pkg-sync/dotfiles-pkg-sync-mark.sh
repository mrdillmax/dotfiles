#!/usr/bin/env bash
# Pacman hook helper. Runs after a package transaction and records a stamp so
# `pkg-sync.sh status` can ask for a package-list review later.
#
# Installed by `./install.sh --system` as
# /usr/local/bin/dotfiles-pkg-sync-mark.sh
set -euo pipefail

TARGET_DIR="${DOTFILES_PKG_SYNC_DIR:-/var/lib/dotfiles}"

install -d -m 0755 -- "$TARGET_DIR"
date +%s >"$TARGET_DIR/pkg-sync.stamp"
