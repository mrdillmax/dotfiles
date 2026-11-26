-- Optional: lock the session at startup, before the desktop is usable.
local runtime = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
local marker_path = runtime .. "/dotfiles-greeter.lock"
-- Clear any stale marker from a previous crashed session.
os.remove(marker_path)
-- Write the marker so autostart.sh knows to wait for unlock.
local marker = io.open(marker_path, "w")
if marker then
    marker:write("1\n")
    marker:close()
end
hl.on("hyprland.start", function()
    hl.exec_cmd("bash -c 'greeter.sh'")
end)
