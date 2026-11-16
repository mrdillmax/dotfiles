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
            README.md|*/README.md|services/services.conf|pacman/pacman.conf.preset|makepkg/makepkg.conf.preset)
                continue
                ;;
            unbound/unbound.conf)            printf '%s\t%s\t%s\n' "$src" "/etc/unbound/unbound.conf" "0644" ;;
            pihole/dnsmasq.conf)             printf '%s\t%s\t%s\n' "$src" "/etc/pihole/dnsmasq.conf" "0644" ;;
            pihole/pihole.toml.example)      printf '%s\t%s\t%s\n' "$src" "/etc/pihole/pihole.toml" "0640" ;;
            wait-iface/wait-iface.sh)        printf '%s\t%s\t%s\n' "$src" "/usr/local/bin/wait-iface.sh" "0755" ;;
            zram/zram-generator.conf)        printf '%s\t%s\t%s\n' "$src" "/etc/systemd/zram-generator.conf" "0644" ;;
            cpupower/cpupower)               printf '%s\t%s\t%s\n' "$src" "/etc/default/cpupower" "0644" ;;
            networkmanager/dns.conf)         printf '%s\t%s\t%s\n' "$src" "/etc/NetworkManager/conf.d/dns.conf" "0644" ;;
            networkmanager/rc-manager.conf)  printf '%s\t%s\t%s\n' "$src" "/etc/NetworkManager/conf.d/rc-manager.conf" "0644" ;;
            systemd/*)                       printf '%s\t%s\t%s\n' "$src" "/etc/systemd/system/${rel#systemd/}" "0644" ;;
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
    tui_confirm "CRITICAL: replace $1. Continue?" no || rc=$?
    ASSUME_YES="$saved"
    return "$rc"
}

detect_default_iface() {
    command -v ip >/dev/null 2>&1 || return 1
    ip route show default 2>/dev/null |
        awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }'
}

valid_iface_name() {
    [[ $1 =~ ^[A-Za-z0-9_.:-]+$ ]]
}

resolve_iface() {
    local iface=""

    if [[ -n ${IFACE_ARG:-} ]]; then
        if ! valid_iface_name "$IFACE_ARG"; then
            warn "invalid interface name: $IFACE_ARG"
            return 1
        fi
        printf '%s\n' "$IFACE_ARG"
        return 0
    fi

    iface="$(detect_default_iface || true)"
    if [[ -z $iface ]] && [[ -t 0 ]]; then
        iface="$(tui_input "Network interface for Pi-hole" "")"
    fi

    if [[ -z $iface ]]; then
        warn "cannot determine the network interface; pass --iface IFACE or edit the file manually"
        return 1
    fi

    if ! valid_iface_name "$iface"; then
        warn "invalid interface name: $iface"
        return 1
    fi

    printf '%s\n' "$iface"
}

render_iface_placeholders() {
    local src="$1" iface="$2" tmp
    tmp="$(mktemp)"
    sed "s|@IFACE@|$iface|g" "$src" >"$tmp"
    printf '%s\n' "$tmp"
}

pacman_proposal() {
    local target="$1" nproc="$2"
    awk -v n="$nproc" '
        function flush_options() {
            if (!color_done) print "Color"
            if (!candy_done) print "ILoveCandy"
            if (!pd_done)    print "ParallelDownloads = " n
        }
        BEGIN {
            in_options = 0; in_multilib = 0
            color_done = 0; candy_done = 0; pd_done = 0
            multilib_done = 0; ml_inc_done = 0
        }
        /^\[options\][[:space:]]*$/ {
            in_options = 1
            print
            next
        }
        /^\[/ {
            if (in_options) {
                flush_options()
                in_options = 0
            }
            if ($0 ~ /^\[multilib\][[:space:]]*$/) {
                in_multilib = 1; multilib_done = 1
                print
                next
            }
            if ($0 ~ /^#[[:space:]]*\[multilib\][[:space:]]*$/) {
                in_multilib = 1; multilib_done = 1
                print "[multilib]"
                next
            }
            in_multilib = 0
            print
            next
        }
        in_options {
            if ($0 ~ /^#?[[:space:]]*Color[[:space:]]*$/) {
                if (!color_done) { print "Color"; color_done = 1 }
                next
            }
            if ($0 ~ /^#?[[:space:]]*ILoveCandy[[:space:]]*$/) {
                if (!candy_done) { print "ILoveCandy"; candy_done = 1 }
                next
            }
            if ($0 ~ /^#?[[:space:]]*ParallelDownloads[[:space:]]*=/) {
                if (!pd_done) { print "ParallelDownloads = " n; pd_done = 1 }
                next
            }
            print
            next
        }
        in_multilib {
            if ($0 ~ /^#?[[:space:]]*Include[[:space:]]*=/) {
                if (!ml_inc_done) {
                    print "Include = /etc/pacman.d/mirrorlist"
                    ml_inc_done = 1
                }
                next
            }
            print
            next
        }
        { print }
        END {
            if (in_options) flush_options()
            if (!multilib_done) {
                print ""
                print "[multilib]"
                print "Include = /etc/pacman.d/mirrorlist"
            }
        }
    ' "$target"
}

makepkg_proposal() {
    local target="$1" nproc="$2"
    awk -v n="$nproc" '
        BEGIN { done = 0 }
        /^[[:space:]]*#?[[:space:]]*MAKEFLAGS[[:space:]]*=/ {
            if (!done) {
                print "MAKEFLAGS=\"-j" n "\""
                done = 1
            }
            next
        }
        { print }
        END {
            if (!done) print "MAKEFLAGS=\"-j" n "\""
        }
    ' "$target"
}

merge_config() {
    local label="$1" target="$2" proposal="$3"

    [[ -r $target ]] || { warn "not found, skipping $label: $target"; return 0; }

    if cmp -s -- "$target" "$proposal"; then
        ok "$label already matches: $target"
        return 0
    fi

    log "Proposed changes to $target:"
    diff -u -- "$target" "$proposal" || true

    if (( DRY_RUN )); then
        log "${C_DIM}[dry-run]${C_RESET} merge $label into $target"
        return 0
    fi

    if (( ASSUME_YES )) || [[ ! -t 0 ]]; then
        info "skipping $label merge in non-interactive mode"
        return 0
    fi

    if ! tui_confirm "Merge $label into $target?" no; then
        warn "$label merge skipped"
        return 0
    fi

    backup_path "$target"
    install -m 0644 -- "$proposal" "$target"
    ok "merged $label into $target"
}

merge_pacman_conf() {
    local target="${1:-/etc/pacman.conf}"
    local tmp
    tmp="$(mktemp)"
    pacman_proposal "$target" "$(nproc)" >"$tmp"
    merge_config "pacman.conf" "$target" "$tmp"
    rm -f -- "$tmp"
}

merge_makepkg_conf() {
    local target="${1:-/etc/makepkg.conf}"
    local tmp
    tmp="$(mktemp)"
    makepkg_proposal "$target" "$(nproc)" >"$tmp"
    merge_config "makepkg.conf" "$target" "$tmp"
    rm -f -- "$tmp"
}

enable_system_services() {
    local conf="$DOTFILES_DIR/system/services/services.conf"
    local service package note
    local -a labels=() picked=()

    [[ -r $conf ]] || return 0

    if (( ASSUME_YES )) || [[ ! -t 0 ]]; then
        info "skipping system service selection (non-interactive)"
        return 0
    fi

    while IFS=$'\t' read -r service package note; do
        [[ -z $service || $service == \#* ]] && continue
        labels+=("$service — $note (package: $package)")
    done <"$conf"

    ((${#labels[@]})) || return 0

    tui_checklist "System services to enable (not started)" "${labels[@]}"
    ((${#TUI_SELECTION[@]})) || { info "no system services selected"; return 0; }

    local line
    for line in "${TUI_SELECTION[@]}"; do
        picked+=("${line%% — *}")
    done

    if ! tui_confirm "Enable ${#picked[@]} system service(s)? They will not be started." no; then
        warn "system services not enabled"
        return 0
    fi

    for service in "${picked[@]}"; do
        if ! systemctl list-unit-files "$service" >/dev/null 2>&1; then
            warn "unit not found, skipping: $service"
            continue
        fi
        run systemctl enable "$service"
    done
}

install_system_configs() {
    if (( EUID != 0 )) && (( !DRY_RUN )); then
        die "system configs require root: sudo ./install.sh --system"
    fi

    local src dst mode tmp_src iface
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
        tmp_src=""

        if [[ $dst == /etc/NetworkManager/conf.d/* ]]; then
            if [[ ! -e /etc/pihole/pihole.toml || ! -e /etc/unbound/unbound.conf ]]; then
                warn "skipping $dst: install and configure Pi-hole + Unbound first"
                continue
            fi
        fi

        if grep -q '@IFACE@' "$src"; then
            if ! iface="$(resolve_iface)"; then
                warn "skipping $dst: no interface name"
                continue
            fi
            tmp_src="$(render_iface_placeholders "$src" "$iface")"
            src="$tmp_src"
            info "rendered @IFACE@ as $iface for $dst"
        fi

        if is_critical_system_path "$dst"; then
            if ! confirm_critical "replace $dst"; then
                warn "skipped critical file $dst"
                [[ -n $tmp_src ]] && rm -f -- "$tmp_src"
                continue
            fi
        elif ! tui_confirm "Install $dst?" no; then
            warn "skipped $dst"
            [[ -n $tmp_src ]] && rm -f -- "$tmp_src"
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
        [[ -n $tmp_src ]] && rm -f -- "$tmp_src"
        count=$((count + 1))
    done

    printf '\n'
    merge_pacman_conf
    merge_makepkg_conf
    enable_system_services

    if (( DRY_RUN )); then
        return 0
    fi

    printf '\n'
    info "Not run automatically (review and run manually):"
    printf '  sudo systemctl daemon-reload\n'
    printf '  sudo systemctl start systemd-zram-setup@zram0.service   # zram\n'
    printf '  sudo systemctl enable --now cpupower                    # CPU governor\n'
    printf '  sudo systemctl restart NetworkManager                   # only after DNS safety check\n'
    printf '  sudo systemctl enable --now irqbalance ananicy-cpp preload lactd\n'
    printf '  sudo systemctl enable --now paccache.timer fstrim.timer\n'
    printf '  sudo unbound-checkconf /etc/unbound/unbound.conf\n'
    printf '  sudo grub-mkconfig -o /boot/grub/grub.cfg   # only if GRUB was changed\n'
    printf '  sudo mkinitcpio -P                          # only if mkinitcpio was changed\n'
    printf '  sudo pihole restartdns                      # only if Pi-hole DNS was changed\n'

    # Backups created as root should remain readable by the invoking user.
    if [[ -n ${SUDO_USER:-} && -d $BACKUP_DIR ]]; then
        chown -R "$SUDO_UID:$SUDO_GID" "$BACKUP_DIR" 2>/dev/null || true
    fi
}
