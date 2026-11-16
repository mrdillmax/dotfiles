# shellcheck shell=bash
# Opt-in installation of /etc files. Never runs grub-mkconfig, mkinitcpio or
# restarts services; it only writes files after an explicit confirmation.
[[ -n ${_DOTFILES_SYSTEM:-} ]] && return 0
_DOTFILES_SYSTEM=1

system_file_map() {
    local root="$DOTFILES_DIR/system"
    local src rel

    while IFS= read -r src; do
        rel="${src#"$root"/}"
        case "$rel" in
            unbound/unbound.conf)            printf '%s\t%s\t%s\n' "$src" "/etc/unbound/unbound.conf" "0644" ;;
            pihole/dnsmasq.conf)             printf '%s\t%s\t%s\n' "$src" "/etc/pihole/dnsmasq.conf" "0644" ;;
            pihole/pihole.toml.example)      printf '%s\t%s\t%s\n' "$src" "/etc/pihole/pihole.toml" "0640" ;;
            wait-iface/wait-iface.sh)        printf '%s\t%s\t%s\n' "$src" "/usr/local/bin/wait-iface.sh" "0755" ;;
            systemd/*)                        printf '%s\t%s\t%s\n' "$src" "/etc/systemd/system/${rel#systemd/}" "0644" ;;
            grub/default-grub)               printf '%s\t%s\t%s\n' "$src" "/etc/default/grub" "0644" ;;
            mkinitcpio/mkinitcpio.conf)      printf '%s\t%s\t%s\n' "$src" "/etc/mkinitcpio.conf" "0644" ;;
            modprobe/*)                      printf '%s\t%s\t%s\n' "$src" "/etc/modprobe.d/${rel#modprobe/}" "0644" ;;
            sysctl/*)                        printf '%s\t%s\t%s\n' "$src" "/etc/sysctl.d/${rel#sysctl/}" "0644" ;;
            *)                               printf 'warning: unmapped system file: %s\n' "$rel" >&2 ;;
        esac
    done < <(find "$root" -type f | sort)
}

is_critical_system_path() {
    case "$1" in
        /etc/default/grub|/etc/mkinitcpio.conf|*/getty@tty1.service.d/autologin.conf) return 0 ;;
        *) return 1 ;;
    esac
}

confirm_critical() {
    local saved="$ASSUME_YES"
    ASSUME_YES=0
    local rc=0
    tui_confirm "CRITICAL: $1. Type confirmation to continue?" no || rc=$?
    ASSUME_YES="$saved"
    return "$rc"
}

install_system_configs() {
    if (( EUID != 0 )); then
        die "system configs require root: sudo ./install.sh --system"
    fi

    local src dst mode
    local count=0
    local rows=()

    mapfile -t rows < <(system_file_map)
    if ((${#rows[@]} == 0)); then
        warn "no system files found"
        return 0
    fi

    info "The following /etc files will be reviewed one by one:"
    local row
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r src dst mode <<<"$row"
        printf '  %s -> %s\n' "$src" "$dst"
    done

    for row in "${rows[@]}"; do
        IFS=$'\t' read -r src dst mode <<<"$row"
        if is_critical_system_path "$dst"; then
            if ! confirm_critical "replace $dst"; then
                warn "skipped critical file $dst"
                continue
            fi
        elif ! tui_confirm "Install $dst?" no; then
            warn "skipped $dst"
            continue
        fi

        if [[ -e $dst ]]; then
            backup_path "$dst"
        fi

        if (( DRY_RUN )); then
            log "${C_DIM}[dry-run]${C_RESET} install $src -> $dst (mode $mode)"
        else
            mkdir -p "$(dirname "$dst")"
            install -m "$mode" -- "$src" "$dst"
            ok "installed $dst"
        fi
        count=$((count + 1))
    done

    if (( DRY_RUN )); then
        return 0
    fi

    printf '\n'
    info "Not run automatically (review and run manually):"
    printf '  sudo unbound-checkconf /etc/unbound/unbound.conf\n'
    printf '  sudo systemctl daemon-reload\n'
    printf '  sudo grub-mkconfig -o /boot/grub/grub.cfg   # only if GRUB was changed\n'
    printf '  sudo mkinitcpio -P                          # only if mkinitcpio was changed\n'
    printf '  sudo pihole restartdns                      # only if Pi-hole DNS was changed\n'

    # Backups created as root should remain readable by the invoking user.
    if [[ -n ${SUDO_USER:-} && -d $BACKUP_DIR ]]; then
        chown -R "$SUDO_UID:$SUDO_GID" "$BACKUP_DIR" 2>/dev/null || true
    fi
}
