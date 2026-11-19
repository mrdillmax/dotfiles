# shellcheck shell=bash
# Opt-in installation of /etc files. Never runs grub-mkconfig, mkinitcpio or
# restarts services; it only writes files after an explicit confirmation.
[[ -n ${_DOTFILES_SYSTEM:-} ]] && return 0
_DOTFILES_SYSTEM=1

# shellcheck source=lib/dns.sh
source "$DOTFILES_DIR/lib/dns.sh"

# Optional filter: --system-components dns,zram,... Empty means "everything".
if [[ -z ${SYSTEM_COMPONENTS+x} ]]; then
    SYSTEM_COMPONENTS=()
fi

system_component_all() {
    ((${#SYSTEM_COMPONENTS[@]} == 0))
}

system_component_wanted() {
    local component="$1" item
    system_component_all && return 0
    for item in "${SYSTEM_COMPONENTS[@]}"; do
        [[ $item == "$component" ]] && return 0
    done
    return 1
}

system_rel_component() {
    case "$1" in
        unbound/*|pihole/*|networkmanager/*|wait-iface/*) printf 'dns' ;;
        zram/*)                                           printf 'zram' ;;
        cpupower/*)                                       printf 'cpupower' ;;
        systemd/*|services/*|pkg-sync/*)                  printf 'services' ;;
        grub/*|mkinitcpio/*|modprobe/*)                   printf 'grub' ;;
        pacman/*|makepkg/*)                               printf 'pacman' ;;
        ram-cache/*)                                      printf 'ram' ;;
    esac
}

system_file_map() {
    local root="$DOTFILES_DIR/system"
    local src rel component

    while IFS= read -r src; do
        rel="${src#"$root"/}"
        component="$(system_rel_component "$rel")"
        if [[ -n $component ]] && ! system_component_wanted "$component"; then
            continue
        fi
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
            ram-cache/*)                     printf '%s\t%s\t%s\n' "$src" "/etc/sysctl.d/${rel#ram-cache/}" "0644" ;;
            pkg-sync/dotfiles-pkg-sync-mark.sh) printf '%s\t%s\t%s\n' "$src" "/usr/local/bin/dotfiles-pkg-sync-mark.sh" "0755" ;;
            pacman/hooks/*)                  printf '%s\t%s\t%s\n' "$src" "/etc/pacman.d/hooks/${rel#pacman/hooks/}" "0644" ;;
            networkmanager/dns.conf)         printf '%s\t%s\t%s\n' "$src" "/etc/NetworkManager/conf.d/dns.conf" "0644" ;;
            networkmanager/rc-manager.conf)  printf '%s\t%s\t%s\n' "$src" "/etc/NetworkManager/conf.d/rc-manager.conf" "0644" ;;
            systemd/*)                       printf '%s\t%s\t%s\n' "$src" "/etc/systemd/system/${rel#systemd/}" "0644" ;;
            grub/default-grub)
                if [[ ${GPU_PROFILE:-} == nvidia || ${GPU_PROFILE:-} == hybrid ]]; then
                    printf '%s\t%s\t%s\n' "$src" "/etc/default/grub" "0644"
                fi
                ;;
            mkinitcpio/mkinitcpio.conf)
                if [[ ${GPU_PROFILE:-} == nvidia || ${GPU_PROFILE:-} == hybrid ]]; then
                    printf '%s\t%s\t%s\n' "$src" "/etc/mkinitcpio.conf" "0644"
                fi
                ;;
            modprobe/nvidia.conf)
                if [[ ${GPU_PROFILE:-} == nvidia || ${GPU_PROFILE:-} == hybrid ]]; then
                    printf '%s\t%s\t%s\n' "$src" "/etc/modprobe.d/nvidia.conf" "0644"
                fi
                ;;
            modprobe/*)                      printf '%s\t%s\t%s\n' "$src" "/etc/modprobe.d/${rel#modprobe/}" "0644" ;;
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

valid_login_name() {
    [[ $1 =~ ^[A-Za-z0-9._-]+$ ]]
}

resolve_autologin_user() {
    local user="${AUTOLOGIN_USER_ARG:-}"

    if [[ -z $user && -n ${SUDO_USER:-} ]]; then
        user="$SUDO_USER"
    fi
    if [[ -z $user ]]; then
        user="$(logname 2>/dev/null || true)"
    fi
    if [[ -z $user ]]; then
        user="$(id -un 2>/dev/null || true)"
    fi
    if [[ -z $user ]] && [[ -t 0 ]]; then
        user="$(tui_input "User for getty autologin" "")"
    fi

    if [[ -z $user ]]; then
        warn "cannot determine the autologin user; pass --autologin-user USER"
        return 1
    fi
    if ! valid_login_name "$user"; then
        warn "invalid autologin user: $user"
        return 1
    fi
    if command -v getent >/dev/null 2>&1 && ! getent passwd "$user" >/dev/null; then
        warn "autologin user does not exist: $user"
        return 1
    fi

    printf '%s\n' "$user"
}

render_system_placeholders() {
    local src="$1" iface="${2:-}" user="${3:-}" tmp
    tmp="$(mktemp)"
    sed -e "s|@IFACE@|$iface|g" -e "s|@USER@|$user|g" "$src" >"$tmp"
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
    if [[ ! -r $target ]]; then
        warn "not found, skipping pacman.conf: $target"
        return 1
    fi
    tmp="$(mktemp)"
    pacman_proposal "$target" "$(nproc)" >"$tmp"
    merge_config "pacman.conf" "$target" "$tmp"
    rm -f -- "$tmp"
}

# True when pacman.conf contains an active [multilib] section.
multilib_enabled() {
    local conf="${1:-/etc/pacman.conf}"
    [[ -r $conf ]] || return 1
    awk '/^\[multilib\][[:space:]]*$/ { found = 1 } END { exit !found }' "$conf"
}

# First run: without [multilib] every lib32-* package fails with
# "target not found". Merge the preset, then refresh with -Syu; -Sy alone is a
# partial upgrade and is exactly what breaks the system.
prepare_repositories() {
    local conf="${1:-/etc/pacman.conf}"

    if [[ ! -r $conf ]]; then
        warn "not found: $conf"
        return 1
    fi

    if multilib_enabled "$conf"; then
        ok "multilib is already enabled; nothing to do"
        return 0
    fi

    info "enabling [multilib] in $conf and refreshing the database"
    if ! merge_pacman_conf "$conf"; then
        warn "cannot update $conf; package installs would fail"
        return 1
    fi

    if (( !DRY_RUN )) && ! multilib_enabled "$conf"; then
        warn "[multilib] is still disabled; package installs would fail"
        return 1
    fi

    run pacman -Syu
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
    local service package note label
    local -a labels=() picked=() checked=()

    [[ -r $conf ]] || return 0

    if (( ASSUME_YES )) || [[ ! -t 0 ]]; then
        info "skipping system service selection (non-interactive)"
        return 0
    fi

    while IFS=$'\t' read -r service package note; do
        [[ -z $service || $service == \#* ]] && continue
        label="$service — $note (package: $package)"
        labels+=("$label")
        case "$service" in
            irqbalance|ananicy-cpp) checked+=("$label") ;;
        esac
    done <"$conf"

    ((${#labels[@]})) || return 0

    # shellcheck disable=SC2034 # read by tui_checklist_indexes
    TUI_CHECKED_ITEMS=("${checked[@]}")
    tui_checklist "System services to enable and start" "${labels[@]}"
    ((${#TUI_SELECTION[@]})) || { info "no system services selected"; return 0; }

    local line
    for line in "${TUI_SELECTION[@]}"; do
        picked+=("${line%% — *}")
    done

    if ! tui_confirm "Enable and start ${#picked[@]} system service(s)?" no; then
        warn "system services not enabled"
        return 0
    fi

    for service in "${picked[@]}"; do
        if ! systemctl list-unit-files "$service" >/dev/null 2>&1; then
            warn "unit not found, skipping: $service"
            continue
        fi
        run systemctl enable --now "$service"
    done
}

# Use fish as the login shell, so getty autologin reaches the tty1 block in
# config.fish and starts Hyprland. Safe to run repeatedly.
set_login_shell_fish() {
    local user="${1:-}" shell current

    if [[ -z $user ]]; then
        user="$(resolve_autologin_user)" || return 0
    fi
    shell="$(command -v fish 2>/dev/null || true)"
    if [[ -z $shell ]]; then
        warn "fish is not installed; login shell unchanged"
        return 1
    fi
    current="$(getent passwd "$user" 2>/dev/null | cut -d: -f7)"
    if [[ $current == "$shell" ]]; then
        ok "login shell is already fish"
        return 0
    fi
    if (( !DRY_RUN )) && (( !ASSUME_YES )); then
        if ! tui_confirm "Make fish the login shell for $user?" yes; then
            warn "login shell unchanged"
            return 1
        fi
    fi
    run chsh -s "$shell" "$user" || { warn "could not change the login shell"; return 1; }
    ok "login shell set to $shell for $user"
}

install_system_configs() {
    if (( EUID != 0 )) && (( !DRY_RUN )); then
        die "system configs require root: sudo ./install.sh --system"
    fi

    local src dst mode tmp_src iface user
    local count=0 dns_ok=1 dns_skipped=0 boot_changed=0 dns_changed=0
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

    # Fail closed: if the resolver chain cannot be verified, leave every DNS
    # file alone but keep reviewing the rest of /etc.
    if system_component_wanted dns && ! dns_chain_ok; then
        dns_ok=0
        warn "DNS chain is not healthy; only DNS files will be skipped."
        while IFS= read -r row; do
            [[ -n $row ]] && warn "  $row"
        done < <(dns_failures)
        while IFS= read -r row; do
            [[ -n $row ]] && warn "  $row"
        done < <(dns_warnings)
        dns_emergency_help
    fi

    for row in "${rows[@]}"; do
        IFS=$'\t' read -r src dst mode <<<"$row"
        tmp_src=""

        if ((!dns_ok)) && dns_is_dns_file "$dst"; then
            warn "skipping DNS file $dst (resolver chain is not healthy)"
            dns_skipped=$((dns_skipped + 1))
            continue
        fi

        if [[ $dst == /etc/NetworkManager/conf.d/* ]]; then
            if [[ ! -e /etc/pihole/pihole.toml || ! -e /etc/unbound/unbound.conf ]]; then
                warn "skipping $dst: install and configure Pi-hole + Unbound first"
                continue
            fi
        fi

        iface=""
        user=""
        if grep -q '@IFACE@' "$src"; then
            if ! iface="$(resolve_iface)"; then
                warn "skipping $dst: no interface name"
                continue
            fi
        fi
        if grep -q '@USER@' "$src"; then
            if ! user="$(resolve_autologin_user)"; then
                warn "skipping $dst: no valid autologin user"
                continue
            fi
        fi
        if [[ -n $iface || -n $user ]]; then
            tmp_src="$(render_system_placeholders "$src" "$iface" "$user")"
            src="$tmp_src"
            if [[ -n $iface ]]; then
                info "rendered @IFACE@ as $iface for $dst"
            fi
            if [[ -n $user ]]; then
                info "rendered @USER@ as $user for $dst"
            fi
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
        case "$dst" in
            /etc/default/grub|/etc/mkinitcpio.conf) boot_changed=1 ;;
        esac
        dns_is_dns_file "$dst" && dns_changed=1
        count=$((count + 1))
    done

    if ((dns_skipped)); then
        warn "skipped $dns_skipped DNS file(s); fix the resolver chain and re-run --system"
    fi

    printf '\n'
    if system_component_wanted pacman; then
        merge_pacman_conf || warn "pacman.conf merge skipped"
        merge_makepkg_conf
    fi
    if system_component_wanted services; then
        enable_system_services
        set_login_shell_fish || true
    fi

    printf '\n'
    info "Applying the changes"
    run systemctl daemon-reload || warn "daemon-reload failed"

    if system_component_wanted zram; then
        run systemctl start systemd-zram-setup@zram0.service \
            || warn "could not start zram; check /etc/systemd/zram-generator.conf"
    fi
    if system_component_wanted cpupower; then
        run systemctl enable --now cpupower || warn "could not enable cpupower"
    fi
    if (( dns_changed )); then
        run systemctl restart NetworkManager || warn "could not restart NetworkManager"
        if systemctl list-unit-files unbound.service >/dev/null 2>&1; then
            run systemctl restart unbound || warn "could not restart unbound"
        fi
        if command -v pihole >/dev/null 2>&1; then
            run pihole restartdns || warn "could not restart Pi-hole DNS"
        fi
    fi
    if (( boot_changed )); then
        if command -v grub-mkconfig >/dev/null 2>&1; then
            run grub-mkconfig -o /boot/grub/grub.cfg || warn "grub-mkconfig failed"
        else
            warn "grub-mkconfig is not installed; GRUB was not regenerated"
        fi
        if command -v mkinitcpio >/dev/null 2>&1; then
            run mkinitcpio -P || warn "mkinitcpio failed"
        else
            warn "mkinitcpio is not installed; initramfs was not rebuilt"
        fi
    fi

    # Backups created as root should remain readable by the invoking user.
    if [[ -n ${SUDO_USER:-} && -d $BACKUP_DIR ]]; then
        chown -R "$SUDO_UID:$SUDO_GID" "$BACKUP_DIR" 2>/dev/null || true
    fi
}
