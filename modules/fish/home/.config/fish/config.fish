# Interactive fish configuration.
#
# Sourced after ~/.config/fish/conf.d/*.fish. Sections are grouped: aliases
# that replace core utils, small helpers, then tool initialisation. Machine
# specific paths belong in conf.d/ or a local file, not here.

if status is-interactive
    set -g fish_greeting
    zoxide init fish | source

    # === UNIX program alternative ===
    alias cat='bat'
    alias mkdir='mkdir -p'
    alias cd='z'
    alias find='fd'
    alias grep='rg'
    
    # === Other ===
    alias cp='cp -i'
    
    alias ..='cd ..'
    alias ...='cd ../..'
    alias ....='cd ../../..'
    alias .....='cd ../../../..'
    
    alias c='clear'

    alias hyprconf='micro ~/.config/hypr/hyprland.lua'
    alias fishconf='micro ~/.config/fish/config.fish'

    
    # === Extract ===
	function ex
        if test -f $argv[1]
            switch $argv[1]
                case '*.tar.bz2'  ; tar xjf $argv[1]
                case '*.tar.gz'   ; tar xzf $argv[1]
                case '*.bz2'      ; bunzip2 $argv[1]
                case '*.rar'      ; unrar x $argv[1]
                case '*.gz'       ; gunzip $argv[1]
                case '*.tar'      ; tar xf $argv[1]
                case '*.tbz2'     ; tar xjf $argv[1]
                case '*.tgz'      ; tar xzf $argv[1]
                case '*.zip'      ; unzip $argv[1]
                case '*.Z'        ; uncompress $argv[1]
                case '*.7z'       ; 7z x $argv[1]
                case '*'          ; echo "'$argv[1]' cannot be extracted via ex()"
            end
        else
            echo "'$argv[1]' is not a valid file"
        end
    end

    # === ls alternative ===
    alias ls='eza --icons --group-directories-first'
    alias l='ls -l --total-size'
    alias la='ls -a'
    alias lla='ls -la --total-size'
    alias ltg='ls -T'
    alias lt='ls -T'
    alias ltag='ls -Ta'
    alias lta='ls -Ta'

    # === Pacman and yay control ===
    alias ys='yay -S'
    alias yss='yay -Ss'
    alias yqs='yay -Qs'
    alias yr='yay -Rns'
    
    alias pas='sudo pacman -S'
    alias pqs='pacman -Qs'
    alias pss='pacman -Ss'
    alias pr='sudo pacman -Rns'
    
    function fc
        sudo rm -rf /var/cache/pacman/pkg/download-*
        yay -Yc
        sudo pacman -Scc
        yay -Scc
        sudo journalctl --vacuum-time=2d
    end
    alias fu='yay -Syu; and yay -Yc'
    alias rmpkg="pacman -Qq | fzf -m --preview 'pacman -Qi {}' | xargs -ro sudo pacman -Rns"

    alias interpreter="$HOME/.local/venvs/interpreter/bin/interpreter"

end

if status is-interactive; and test -n "$WAYLAND_DISPLAY"
    # === In terminal autostart ===
    fastfetch
end

# === Autologin ===
# Start the desktop from tty1 only when no session is running yet. uwsm
# knows whether this is a safe moment; checking WAYLAND_DISPLAY alone missed
# the case where the user already logged in on another VT.
if uwsm check may-start; and string match -q '/dev/tty1' (tty)
    clear
    exec uwsm start hyprland-uwsm.desktop > /dev/null 2>&1
end

fish_add_path $HOME/.local/bin
fish_add_path $HOME/.spicetify
