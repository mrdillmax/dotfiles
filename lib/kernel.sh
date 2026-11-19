# shellcheck shell=bash
# Kernel selection driven by the CPU x86-64 microarchitecture level.
#
# Safety rules:
#   * never offer a level above the CPU's supported level without an explicit
#     "I UNDERSTAND" override;
#   * never remove the running kernel; always keep a fallback kernel;
#   * install as the invoking user (sudo for package operations), never run
#     grub-mkconfig or mkinitcpio automatically;
#   * laptops are treated conservatively (no xanmod by default).
[[ -n ${_DOTFILES_KERNEL:-} ]] && return 0
_DOTFILES_KERNEL=1

FALLBACK_KERNEL_PACKAGE="linux-lts"

kernel_level_rank() {
    case "${1,,}" in
        v1|1) printf '1\n' ;;
        v2|2) printf '2\n' ;;
        v3|3) printf '3\n' ;;
        v4|4) printf '4\n' ;;
        *)    return 1 ;;
    esac
}

kernel_normalize_level() {
    case "${1,,}" in
        v1|1) printf 'v1\n' ;;
        v2|2) printf 'v2\n' ;;
        v3|3) printf 'v3\n' ;;
        v4|4) printf 'v4\n' ;;
        *)    return 1 ;;
    esac
}

kernel_cpu_flags() {
    awk -F: '/^flags/ { print $2; exit }' /proc/cpuinfo 2>/dev/null | tr ' ' '\n' | sort -u
}

kernel_has_flags() {
    local flags="$1" flag
    shift
    for flag in "$@"; do
        grep -qx "$flag" <<<"$flags" || return 1
    done
    return 0
}

detect_cpu_level() {
    local help="" level

    if [[ -x /lib/ld-linux-x86-64.so.2 ]]; then
        help="$(/lib/ld-linux-x86-64.so.2 --help 2>/dev/null || true)"
        for level in v4 v3 v2; do
            if grep -q "x86-64-${level} (supported" <<<"$help"; then
                printf '%s\n' "$level"
                return 0
            fi
        done
    fi

    local flags
    flags="$(kernel_cpu_flags)"
    if [[ -n $flags ]]; then
        if kernel_has_flags "$flags" avx512f avx512bw avx512cd avx512dq avx512vl; then
            printf 'v4\n'
        elif kernel_has_flags "$flags" avx2 bmi1 bmi2 fma movbe abm xsave; then
            printf 'v3\n'
        elif kernel_has_flags "$flags" sse4_2 popcnt ssse3 cx16; then
            printf 'v2\n'
        else
            printf 'v1\n'
        fi
        return 0
    fi

    printf 'v1\n'
}

# Prints "<kernel-package>\t<headers-package>\t<source>".
kernel_packages_for() {
    local level="$1" source="official"

    case "$level" in
        v1) printf 'linux\tlinux-headers\t%s\n' "$source" ;;
        v2|v3|v4)
            printf 'linux-xanmod-linux-bin-x64%s\tlinux-xanmod-linux-headers-bin-x64%s\tAUR\n' "$level" "$level"
            ;;
        *) return 1 ;;
    esac
}

# Level implied by a kernel package name, or "generic" for non-level kernels.
kernel_package_level() {
    local package="$1"
    case "$package" in
        *-x64v4*) printf 'v4\n' ;;
        *-x64v3*) printf 'v3\n' ;;
        *-x64v2*) printf 'v2\n' ;;
        *)        printf 'generic\n' ;;
    esac
}

installed_kernel_packages() {
    pacman -Qq 2>/dev/null | grep -E '^linux(-lts|-zen|-hardened|-mainline)?$|^linux-xanmod-linux-bin-x64v[0-9]$' || true
}

running_kernel() {
    printf '%s\n' "$(uname -r)"
}

any_dkms_installed() {
    local packages
    packages="$(pacman -Qq 2>/dev/null || true)"
    grep -qE 'nvidia.*-dkms$|^nvidia-dkms$' <<<"$packages"
}

kernel_report() {
    local cpu level pkg pkg_level headers
    cpu="$(detect_cpu_level)"
    level="$(kernel_normalize_level "${KERNEL_LEVEL_ARG:-$cpu}")" || die "invalid kernel level: ${KERNEL_LEVEL_ARG}"

    info "kernel report (read-only)"
    printf '  running kernel : %s\n' "$(running_kernel)"
    printf '  CPU level      : x86-64-%s\n' "$cpu"
    printf '  selected level : x86-64-%s\n' "$level"

    local -a kernels=()
    mapfile -t kernels < <(installed_kernel_packages)
    if ((${#kernels[@]})); then
        printf '  installed      : %s\n' "${kernels[*]}"
    else
        printf '  installed      : (none detected)\n'
    fi

    local installed_level=""
    for pkg in "${kernels[@]}"; do
        pkg_level="$(kernel_package_level "$pkg")"
        if [[ $pkg_level != generic ]]; then
            if [[ -z $installed_level ]] || (( $(kernel_level_rank "$pkg_level") > $(kernel_level_rank "$installed_level") )); then
                installed_level="$pkg_level"
            fi
        fi
    done

    if [[ -n $installed_level ]]; then
        printf '  kernel level   : x86-64-%s\n' "$installed_level"
        if (( $(kernel_level_rank "$installed_level") > $(kernel_level_rank "$cpu") )); then
            warn "installed kernel level is above the CPU level; it may not boot"
        fi
    fi

    if pacman -Qq "$FALLBACK_KERNEL_PACKAGE" >/dev/null 2>&1; then
        printf '  fallback       : %s installed\n' "$FALLBACK_KERNEL_PACKAGE"
    else
        warn "fallback kernel missing: install $FALLBACK_KERNEL_PACKAGE before switching kernels"
    fi

    if any_dkms_installed; then
        printf '  DKMS           : NVIDIA DKMS detected\n'
        for pkg in "${kernels[@]}"; do
            case "$pkg" in
                linux)          headers="linux-headers" ;;
                linux-lts)      headers="linux-lts-headers" ;;
                linux-zen)      headers="linux-zen-headers" ;;
                *-x64v*)        headers="${pkg/-linux-bin-/-linux-headers-bin-}" ;;
                *)              headers="" ;;
            esac
            if [[ -n $headers ]] && ! pacman -Qq "$headers" >/dev/null 2>&1; then
                warn "headers missing for $pkg: $headers (DKMS modules cannot build)"
            fi
        done
    else
        printf '  DKMS           : not in use\n'
    fi
}

kernel_confirm_level() {
    local level="$1" cpu
    cpu="$(detect_cpu_level)"

    if (( $(kernel_level_rank "$level") <= $(kernel_level_rank "$cpu") )); then
        return 0
    fi

    printf '\n' >&2
    err "RED WARNING: x86-64-$level is ABOVE this CPU's supported level (x86-64-$cpu)."
    err "Such a kernel can panic on boot or silently execute unsupported instructions."
    err "A fallback kernel (linux-lts) must already be installed and bootable."

    if (( ASSUME_YES )) || [[ ! -t 0 ]]; then
        die "refusing an above-CPU kernel level in non-interactive mode"
    fi

    local reply=""
    printf 'Type I UNDERSTAND to continue: ' >&2
    read -r reply || true
    [[ $reply == "I UNDERSTAND" ]] || die "kernel level override aborted"
}

kernel_install_package() {
    local package="$1"

    if pacman -Si "$package" >/dev/null 2>&1; then
        run sudo pacman -S --needed --noconfirm "$package"
        return 0
    fi

    local helper=""
    if command -v yay >/dev/null 2>&1; then
        helper="yay"
    elif command -v paru >/dev/null 2>&1; then
        helper="paru"
    fi
    [[ -n $helper ]] || die "no AUR helper found for $package"
    if [[ $helper == yay ]]; then
        # The keyring already has the build keys on a normal install. Letting
        # yay fetch again makes it fail on unavailable keyservers, so disable
        # that prompt and let makepkg verify against the existing keyring.
        run "$helper" --pgpfetch=false -S --needed --noconfirm "$package"
    else
        run "$helper" -S --needed --noconfirm "$package"
    fi
}

kernel_offer_menu() {
    local cpu="$1" level="$2"
    local -a labels=() packages=() headers_list=()
    local kernel headers

    labels+=("$FALLBACK_KERNEL_PACKAGE + headers — fallback, generic x86-64")
    packages+=("$FALLBACK_KERNEL_PACKAGE")
    headers_list+=("${FALLBACK_KERNEL_PACKAGE}-headers")

    if [[ $HOST_NAME != laptop ]]; then
        labels+=("linux + headers — stable, generic x86-64")
        packages+=("linux")
        headers_list+=("linux-headers")

        labels+=("linux-zen + headers — desktop responsiveness")
        packages+=("linux-zen")
        headers_list+=("linux-zen-headers")
    fi

    if [[ $HOST_NAME != laptop ]] && (( $(kernel_level_rank "$level") >= 2 )); then
        local row
        row="$(kernel_packages_for "$level")"
        IFS=$'\t' read -r kernel headers _ <<<"$row"
        labels+=("$kernel + headers — x86-64-$level, AUR, level-aware")
        packages+=("$kernel")
        headers_list+=("$headers")
    fi

    tui_checklist "Kernels to install (headers always included, nothing is removed)" "${labels[@]}"
    ((${#TUI_SELECTION[@]})) || { info "no kernel selected"; return 0; }

    local line i
    local -a chosen=()
    for line in "${TUI_SELECTION[@]}"; do
        for i in "${!labels[@]}"; do
            if [[ ${labels[$i]} == "$line" ]]; then
                chosen+=("${packages[$i]}"$'\t'"${headers_list[$i]}")
            fi
        done
    done

    for line in "${chosen[@]}"; do
        IFS=$'\t' read -r kernel headers <<<"$line"
        info "installing kernel: $kernel"
        kernel_install_package "$kernel"
        info "installing headers: $headers"
        kernel_install_package "$headers"
        if any_dkms_installed; then
            ok "headers for $kernel installed; DKMS will rebuild modules on the next boot or upgrade"
        fi
    done

    printf '\n'
    warn "no kernel was removed; the running kernel and $FALLBACK_KERNEL_PACKAGE remain available"
    warn "DKMS support for xanmod bin packages is not guaranteed by upstream"
}

install_kernel() {
    local cpu level
    cpu="$(detect_cpu_level)"
    level="$(kernel_normalize_level "${KERNEL_LEVEL_ARG:-$cpu}")" || die "invalid kernel level: ${KERNEL_LEVEL_ARG} (expected v1, v2, v3 or v4)"

    kernel_confirm_level "$level"

    info "CPU supports x86-64-$cpu; selected kernel level x86-64-$level"
    if [[ $HOST_NAME == laptop ]]; then
        warn "laptop host: staying conservative, xanmod is not offered"
    fi

    if ! pacman -Qq "$FALLBACK_KERNEL_PACKAGE" >/dev/null 2>&1; then
        warn "$FALLBACK_KERNEL_PACKAGE is not installed; it will be offered as the fallback"
    fi

    kernel_report
    printf '\n'

    if (( ASSUME_YES )) || [[ ! -t 0 ]]; then
        info "kernel selection needs an interactive terminal; nothing installed"
        printf '  run: ./install.sh --kernel\n'
        return 0
    fi

    kernel_offer_menu "$cpu" "$level"

    printf '\n'
    info "Not run automatically (review and run manually):"
    printf '  sudo mkinitcpio -P\n'
    printf '  sudo grub-mkconfig -o /boot/grub/grub.cfg   # GRUB only\n'
    printf '  reboot and select the new kernel in the boot menu\n'
}
