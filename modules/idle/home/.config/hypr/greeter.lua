-- Optional: lock the session at startup, before the desktop is usable.
-- Enable with: ./install.sh --greeter on
local config_home = os.getenv("XDG_CONFIG_HOME") or (HOME .. "/.config")
local greeter_enabled = io.open(config_home .. "/dotfiles/greeter-on", "r")
if greeter_enabled then
    greeter_enabled:close()
    local runtime = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
    local marker = io.open(runtime .. "/dotfiles-greeter.lock", "w")
    if marker then
        marker:write("1\n")
        marker:close()
    end
    hl.on("hyprland.start", function()
        hl.exec_cmd("greeter.sh")
    end)
end
