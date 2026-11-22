# shellcheck shell=bash
# Minimal firewall policy shared by install.sh and tests.
#
# Incoming is denied by default. Only services that exist on this machine get a
# rule, and local-only daemons (Pi-hole, unbound, Syncthing's web UI, CUPS) are
# never opened. Syncthing sync ports are opened because they are meant for
# other devices.
[[ -n ${_DOTFILES_FIREWALL:-} ]] && return 0
_DOTFILES_FIREWALL=1

# The installer provides `run` and the log helpers; tests source this file alone.
fw_cmd() {
    if declare -F run >/dev/null 2>&1; then
        run "$@"
    else
        "$@"
    fi
}
if ! declare -F warn >/dev/null 2>&1; then
    warn() { printf 'firewall: %s\n' "$*" >&2; }
fi

# Print "PORT/PROTO" for every inbound service that is actually installed.
firewall_rules() {
    if command -v sshd >/dev/null 2>&1; then
        printf '22/tcp\n'
    fi
    if command -v syncthing >/dev/null 2>&1; then
        printf '22000/tcp\n22000/udp\n'
    fi
}

# Apply defaults, then the rules that are missing, then enable ufw. `ufw show
# added` lists rules from a previous run, so a second call adds nothing.
firewall_apply() {
    local rules existing status rule
    local ufw="${UFW_BIN:-ufw}"

    if ! command -v "$ufw" >/dev/null 2>&1 && [[ ! -x $ufw ]]; then
        warn "ufw is not installed; firewall policy was not applied"
        return 1
    fi

    rules="${1:-$(firewall_rules)}"
    existing="$("$ufw" show added 2>/dev/null || true)"
    status="$("$ufw" status verbose 2>/dev/null || true)"

    if ! grep -q 'deny (incoming)' <<<"$status"; then
        fw_cmd "$ufw" default deny incoming || return 1
    fi
    if ! grep -q 'allow (outgoing)' <<<"$status"; then
        fw_cmd "$ufw" default allow outgoing || return 1
    fi

    while IFS= read -r rule; do
        [[ -n $rule ]] || continue
        if grep -qx "ufw allow $rule" <<<"$existing"; then
            continue
        fi
        fw_cmd "$ufw" allow "$rule" || return 1
    done <<<"$rules"

    fw_cmd "$ufw" --force enable || return 1
}

# Syncthing runs as the desktop user, not root. Enable it through the user's
# systemd instance when the runtime directory exists.
enable_syncthing_user_service() {
    local user uid

    command -v syncthing >/dev/null 2>&1 || return 0
    user="${SUDO_USER:-$(id -un)}"
    uid="$(id -u "$user" 2>/dev/null || true)"

    if [[ -n ${XDG_RUNTIME_DIR:-} && $user == "$(id -un)" ]]; then
        fw_cmd systemctl --user enable --now syncthing.service
    elif [[ -n $uid && -d /run/user/$uid ]]; then
        fw_cmd runuser -u "$user" -- \
            env XDG_RUNTIME_DIR="/run/user/$uid" \
            systemctl --user enable --now syncthing.service
    else
        warn "cannot enable the Syncthing user service for $user; log in and run:"
        warn "  systemctl --user enable --now syncthing.service"
        return 1
    fi
}
