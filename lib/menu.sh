# shellcheck shell=bash
# Interactive main menu. Every entry maps to an install.sh flag so the menu and
# the command line cannot drift apart.
[[ -n ${_DOTFILES_MENU:-} ]] && return 0
_DOTFILES_MENU=1

MENU_HOST="${MENU_HOST:-}"
MENU_GPU="${MENU_GPU:-}"

# Action id -> flags that perform the same action non-interactively.
declare -gA MENU_FLAG=(
    [profile]="--host --gpu"
    [modules]="--modules --no-packages"
    [apps]="--category --apps --packages --only-packages"
    [all]="--all"
    [monitors]="--monitors"
    [mouse]="--mouse"
    [cursor]="--cursor"
    [wallpaper]="--wallpaper"
    [theme-generate]="--theme"
    [theme-menu]="--theme-menu"
    [autostart]="--autostart"
    [idle-status]="--idle"
    [idle-apply]="--idle"
    [idle-configure]="--idle"
    [idle-watch]="--idle"
    [lid-status]="--lid"
    [lid-closed]="--lid"
    [lid-open]="--lid"
    [gamemode-status]="--gamemode"
    [gamemode-on]="--gamemode"
    [gamemode-off]="--gamemode"
    [gamemode-toggle]="--gamemode"
    [binds-plain]="--binds"
    [binds-rofi]="--binds"
    [binds-json]="--binds"
    [profiles-status]="--monitor-profiles"
    [profiles-apply]="--monitor-profiles"
    [profiles-watch]="--monitor-profiles"
    [system-all]="--system"
    [system-dns]="--system --system-components"
    [system-zram]="--system --system-components"
    [system-cpupower]="--system --system-components"
    [system-services]="--system --system-components"
    [system-pacman]="--system --system-components"
    [system-grub]="--system --system-components"
    [kernel-report]="--kernel"
    [kernel-install]="--kernel"
    [doctor]="--doctor"
    [dns-check]="--dns-check"
    [restore-list]="--restore"
    [restore-date]="--restore"
    [sync-status]="--sync"
    [sync-diff]="--sync"
    [sync-pull]="--sync"
    [sync-packages]="--sync"
    [pkg-sync-status]="--pkg-sync"
    [pkg-sync-check]="--pkg-sync"
    [pkg-sync-pull]="--pkg-sync"
    [hooks]="--hooks"
    [dryrun]="--dry-run"
)

menu_should_run() {
    (( !HAS_ACTION && !ASSUME_YES )) && [[ -t 0 ]]
}

menu_prerequisite_hint() {    local -a missing=()
    local tool
    for tool in gum jq git; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    ((${#missing[@]})) || return 0
    warn "missing tools: ${missing[*]}"
    info "on a fresh system run ./bootstrap.sh first; the menu falls back to plain bash"
}

# Empty output means the action is available; otherwise the reason is printed.
menu_unavailable_reason() {
    case "$1" in
        lid|lid-*)
            [[ ${MENU_HOST:-${HOST_NAME:-}} == laptop ]] || printf 'laptop host only'
            ;;
        system-grub)
            case "${MENU_GPU:-${GPU_PROFILE:-}}" in
                nvidia|hybrid) ;;
                *) printf 'NVIDIA or hybrid GPU only' ;;
            esac
            ;;
        system-*)
            if (( !DRY_RUN )) && (( EUID != 0 )) && ! command -v sudo >/dev/null 2>&1; then
                printf 'sudo not found'
            fi
            ;;
    esac
}

menu_title_for() {
    case "$1" in
        main)        printf 'Main menu' ;;
        install)     printf 'Installation' ;;
        settings)    printf 'Settings' ;;
        system)      printf 'System (/etc, sudo required)' ;;
        kernel)      printf 'Kernel' ;;
        maintenance) printf 'Maintenance' ;;
        theme)       printf 'Wallpaper and theme' ;;
        idle)        printf 'Idle and lock' ;;
        lid)         printf 'Lid switch' ;;
        gamemode)    printf 'Game mode' ;;
        restore)     printf 'Restore a backup' ;;
        sync)        printf 'Sync live changes' ;;
        binds)       printf 'Keybind cheatsheet' ;;
        profiles)    printf 'Monitor profiles' ;;
        pkg-sync)    printf 'Package drift' ;;
        *)           printf '%s' "$1" ;;
    esac
}

menu_items_for() {
    case "$1" in
        main)
            printf '%s\n' \
                'menu:install|Installation|modules, packages, host and GPU profile' \
                'menu:settings|Settings|monitors, input, theme, session helpers' \
                'menu:system|System (/etc)|DNS, zram, cpupower, services, boot' \
                'menu:kernel|Kernel|CPU-level aware kernel selection' \
                'menu:maintenance|Maintenance|doctor, DNS check, restore, sync, hooks'
            printf '%s|%s|%s\n' dryrun \
                "Dry run: $([[ ${DRY_RUN:-0} == 1 ]] && printf 'on' || printf 'off')" \
                'toggle for every action'
            printf '%s\n' 'exit|Exit|leave without doing anything'
            ;;
        install)
            printf '%s\n' \
                'profile|Host and GPU profile|detected values can be overridden' \
                'modules|Configuration modules|link or render dotfiles into your home directory' \
                'apps|Applications|choose package groups and alternative apps' \
                'all|Everything|all modules and all package groups'
            ;;
        settings)
            printf '%s\n' \
                'monitors|Monitors|detect and write the monitor layout' \
                'mouse|Mouse and touchpad|interactive sensitivity tuner' \
                'cursor|Cursor|theme and size' \
                'menu:theme|Wallpaper and theme|set wallpaper, regenerate colours' \
                'autostart|Autostart|manage applications started at login' \
                'menu:idle|Idle and lock|laptop power profiles' \
                'menu:lid|Lid switch|actions when the lid closes or opens' \
                'menu:gamemode|Game mode|on, off, toggle or status' \
                'menu:profiles|Monitor profiles|apply, watch or status' \
                'menu:binds|Keybind cheatsheet|plain table, rofi menu or JSON'
            ;;
        system)
            printf '%s\n' \
                'system-all|Everything|review every /etc file one by one' \
                'system-dns|DNS (Pi-hole and Unbound)|resolver chain and NetworkManager' \
                'system-zram|zram|compressed swap in RAM' \
                'system-cpupower|cpupower|CPU governor' \
                'system-services|System services|units and the pacman hook' \
                'system-pacman|pacman and makepkg|parallel downloads, MAKEFLAGS' \
                'system-grub|GRUB and mkinitcpio|NVIDIA boot flags, dangerous'
            ;;
        kernel)
            printf '%s\n' \
                'kernel-report|Show CPU level|read-only report' \
                'kernel-install|Install a kernel|offer kernels at or below the CPU level'
            ;;
        maintenance)
            printf '%s\n' \
                'doctor|Doctor|read-only health check' \
                'dns-check|DNS check|resolv.conf -> Pi-hole -> unbound' \
                'menu:restore|Restore|list backups and restore one' \
                'menu:sync|Sync|status, diff, pull or packages' \
                'menu:pkg-sync|Package drift|compare installed packages with the lists' \
                'hooks|Git hooks|install the repository pre-commit hook'
            ;;
        theme)
            printf '%s\n' \
                'wallpaper|Set wallpaper|store a path and apply it' \
                'theme-generate|Regenerate colours|matugen from the current wallpaper' \
                'theme-menu|Theme menu|wallpaper, mode and scheme in one menu'
            ;;
        idle)
            printf '%s\n' \
                'idle-status|Status|show the active profile' \
                'idle-apply|Apply|apply the current profile now' \
                'idle-configure|Configure|prompt for every timeout' \
                'idle-watch|Watch|re-apply when AC or battery changes'
            ;;
        lid)
            printf '%s\n' \
                'lid-status|Status|show the current behaviour' \
                'lid-closed|Lid closed|apply the closed action' \
                'lid-open|Lid open|apply the open action'
            ;;
        gamemode)
            printf '%s\n' \
                'gamemode-status|Status|show the current mode' \
                'gamemode-on|On|enable game mode' \
                'gamemode-off|Off|disable game mode' \
                'gamemode-toggle|Toggle|switch the current mode'
            ;;
        restore)
            printf '%s\n' \
                'restore-list|List backups|show backups and file counts' \
                'restore-date|Restore one|enter the backup date'
            ;;
        sync)
            printf '%s\n' \
                'sync-status|Status|files that differ from the repository' \
                'sync-diff|Diff|unified diffs for those files' \
                'sync-pull|Pull|copy live changes back after confirmation' \
                'sync-packages|Packages|compare installed packages with packages/catalog.tsv'
            ;;
        binds)
            printf '%s\n' \
                'binds-plain|Plain table|aligned cheatsheet in the terminal' \
                'binds-rofi|Rofi menu|searchable keybind menu' \
                'binds-json|JSON|machine-readable output'
            ;;
        profiles)
            printf '%s\n' \
                'profiles-status|Status|configured layout and detected monitors' \
                'profiles-apply|Apply|apply the configured layout once' \
                'profiles-watch|Watch|apply on hotplug events'
            ;;
        pkg-sync)
            printf '%s\n' \
                'pkg-sync-status|Status|report drift' \
                'pkg-sync-check|Check|exit non-zero when lists drift' \
                'pkg-sync-pull|Pull|append installed-but-unlisted packages'
            ;;
    esac
}

menu_summary() {
    local monitors cpu
    monitors="$(detect_monitors 2>/dev/null | wc -l)"
    cpu="$(detect_cpu_level)"
    tui_header 'dotfiles'
    printf 'host: %s   gpu: %s   monitors: %s   CPU: x86-64-%s   dry run: %s\n\n' \
        "${MENU_HOST:-${HOST_NAME:-unknown}}" \
        "${MENU_GPU:-${GPU_PROFILE:-unknown}}" \
        "$monitors" \
        "$cpu" \
        "$([[ ${DRY_RUN:-0} == 1 ]] && printf 'on' || printf 'off')"
}

menu_decorate() {
    local entry="$1" id label description reason
    IFS='|' read -r id label description <<<"$entry"
    reason="$(menu_unavailable_reason "$id")"
    if [[ -n $reason ]]; then
        printf '%s|%s %s|unavailable: %s\n' "$id" "$(tui_symbol unavailable)" "$label" "$reason"
    else
        printf '%s|%s|%s\n' "$id" "$label" "$description"
    fi
}

menu_join() {
    local IFS=,
    printf '%s' "$*"
}

# Run install.sh with the same flag, preserving dry-run and the menu profile.
menu_run() {
    local -a args=("$@")
    (( DRY_RUN )) && args+=(--dry-run)
    [[ -n ${MENU_HOST:-} ]] && args+=(--host "$MENU_HOST")
    [[ -n ${MENU_GPU:-} ]] && args+=(--gpu "$MENU_GPU")
    "$DOTFILES_DIR/install.sh" "${args[@]}"
    local rc=$?
    (( rc == 0 )) || warn "action finished with status $rc"
    return 0
}

menu_system_run() {
    local component="$1"
    local -a args=(--system)
    [[ -n $component ]] && args+=(--system-components "$component")
    (( DRY_RUN )) && args+=(--dry-run)
    [[ -n ${MENU_HOST:-} ]] && args+=(--host "$MENU_HOST")
    [[ -n ${MENU_GPU:-} ]] && args+=(--gpu "$MENU_GPU")

    if (( !DRY_RUN )) && (( EUID != 0 )); then
        sudo "$DOTFILES_DIR/install.sh" "${args[@]}"
    else
        "$DOTFILES_DIR/install.sh" "${args[@]}"
    fi
    local rc=$?
    (( rc == 0 )) || warn "action finished with status $rc"
    return 0
}

menu_action_modules() {
    MODULES=()
    # shellcheck disable=SC2034 # read by select_modules in install.sh
    MODULES_ARG=""
    # shellcheck disable=SC2034 # read by select_modules in install.sh
    ALL=0
    select_modules
    if ((${#MODULES[@]} == 0)); then
        info 'no modules selected'
        return 0
    fi
    menu_run --modules "$(menu_join "${MODULES[@]}")" --no-packages
}

menu_action_apps() {
    # shellcheck disable=SC2034 # read by select_categories/select_apps
    SELECTED_CATEGORIES=()
    # shellcheck disable=SC2034 # read by collect_packages
    SELECTED_APPLICATIONS=()
    select_categories
    select_apps

    local -a packages=()
    mapfile -t packages < <(collect_packages)

    if ((${#packages[@]} == 0)); then
        info 'no packages selected'
        return 0
    fi

    # The menu already resolved groups and apps; install the exact list.
    local list
    list="$(menu_join "${packages[@]}")"
    menu_run --only-packages --packages "$list"
}

menu_action_profile() {
    local host gpu
    host="$(tui_radio 'Host profile' desktop laptop)" || return 0
    gpu="$(tui_radio 'GPU profile' nvidia amd intel hybrid vm software)" || return 0
    MENU_HOST="$host"
    MENU_GPU="$gpu"
    HOST_NAME="$host"
    GPU_PROFILE="$gpu"
    info "profile: $host / $gpu"
}

menu_action_wallpaper() {
    local current='' path
    [[ -r $REAL_HOME/.config/hypr/wallpaper.path ]] && current="$(<"$REAL_HOME/.config/hypr/wallpaper.path")"
    path="$(tui_input 'Wallpaper path' "$current")" || return 0
    [[ -n $path ]] || return 0
    menu_run --wallpaper "$path"
}

menu_action_restore_date() {
    local date
    date="$(tui_input 'Backup date (YYYY-MM-DD_HHMMSS)' '')" || return 0
    [[ -n $date ]] || return 0
    menu_run --restore "$date"
}

menu_action() {
    case "$1" in
        profile)          menu_action_profile ;;
        modules)          menu_action_modules ;;
        apps)             menu_action_apps ;;
        all)              menu_run --all ;;
        monitors)         menu_run --monitors ;;
        mouse)            menu_run --mouse ;;
        cursor)           menu_run --cursor ;;
        wallpaper)        menu_action_wallpaper ;;
        theme-generate)   menu_run --theme ;;
        theme-menu)       menu_run --theme-menu ;;
        autostart)        menu_run --autostart pick ;;
        idle-status)      menu_run --idle status ;;
        idle-apply)       menu_run --idle apply ;;
        idle-configure)   menu_run --idle configure ;;
        idle-watch)       menu_run --idle watch ;;
        lid-status)       menu_run --lid status ;;
        lid-closed)       menu_run --lid closed ;;
        lid-open)         menu_run --lid open ;;
        gamemode-status)  menu_run --gamemode status ;;
        gamemode-on)      menu_run --gamemode on ;;
        gamemode-off)     menu_run --gamemode off ;;
        gamemode-toggle)  menu_run --gamemode toggle ;;
        system-all)       menu_system_run '' ;;
        system-dns)       menu_system_run dns ;;
        system-zram)      menu_system_run zram ;;
        system-cpupower)  menu_system_run cpupower ;;
        system-services)  menu_system_run services ;;
        system-pacman)    menu_system_run pacman ;;
        system-grub)      menu_system_run grub ;;
        kernel-report)    kernel_report; printf '\n' ;;
        kernel-install)   menu_run --kernel ;;
        doctor)           menu_run --doctor ;;
        dns-check)        menu_run --dns-check ;;
        restore-list)     menu_run --restore ;;
        restore-date)     menu_action_restore_date ;;
        sync-status)      menu_run --sync status ;;
        sync-diff)        menu_run --sync diff ;;
        sync-pull)        menu_run --sync pull ;;
        sync-packages)    menu_run --sync packages ;;
        pkg-sync-status)  menu_run --pkg-sync status ;;
        pkg-sync-check)   menu_run --pkg-sync check ;;
        pkg-sync-pull)    menu_run --pkg-sync pull ;;
        binds-plain)      menu_run --binds plain ;;
        binds-rofi)       menu_run --binds rofi ;;
        binds-json)       menu_run --binds json ;;
        profiles-status)  menu_run --monitor-profiles status ;;
        profiles-apply)   menu_run --monitor-profiles apply ;;
        profiles-watch)   menu_run --monitor-profiles watch ;;
        hooks)            menu_run --hooks ;;
        *)                warn "no action for menu item: $1" ;;
    esac
}

menu_loop() {
    local name="$1" title choice reason entry
    local -a entries=()
    title="$(menu_title_for "$name")"

    while true; do
        entries=()
        if [[ $name == main ]]; then
            menu_summary
        fi
        while IFS= read -r entry; do
            [[ -n $entry ]] && entries+=("$(menu_decorate "$entry")")
        done < <(menu_items_for "$name"; [[ $name != main ]] && printf 'back|Back|return to the previous menu\n')

        tui_menu "$title" "${entries[@]}" || return 0
        choice="$TUI_CHOICE"

        case "$choice" in
            back|exit) return 0 ;;
            dryrun)
                DRY_RUN=$((!DRY_RUN))
                info "dry run: $([[ $DRY_RUN == 1 ]] && printf 'on' || printf 'off')"
                ;;
            menu:*) menu_loop "${choice#menu:}" ;;
            *)
                reason="$(menu_unavailable_reason "$choice")"
                if [[ -n $reason ]]; then
                    warn "unavailable: $reason"
                    continue
                fi
                menu_action "$choice"
                ;;
        esac
    done
}

menu_main() {
    MENU_HOST="${MENU_HOST:-$HOST_NAME}"
    MENU_GPU="${MENU_GPU:-$GPU_PROFILE}"
    menu_prerequisite_hint
    menu_loop main
}

# Used by tests: every menu id with its flags.
menu_flag_map() {
    local id
    for id in "${!MENU_FLAG[@]}"; do
        printf '%s\t%s\n' "$id" "${MENU_FLAG[$id]}"
    done | sort
}

menu_menu_names() {
    printf '%s\n' main install settings system kernel maintenance theme idle lid gamemode restore sync binds profiles pkg-sync
}
