-- Hyprland — compositor, binds and window rules.
--
-- The palette comes from colors.lua (matugen). Host-specific monitors come
-- from monitors.lua. Optional modules are probed at startup, so a missing
-- helper never breaks the session.

-- --- MONITORS --------------------------------------------------------------

local HOME = os.getenv("HOME")

-- Rendered by install.sh from hosts/<host>/monitors.conf.sh. The generated
-- file calls hl.monitor()/hl.workspace_rule() and returns a list of monitors.
local monitors = {}
local monitors_ok = pcall(function()
    monitors = dofile(HOME .. "/.config/hypr/monitors.lua")
end)

if not monitors_ok or type(monitors) ~= "table" or #monitors == 0 then
    -- Safe fallback: let Hyprland choose preferred mode for every output.
    hl.monitor({
        output   = "",
        mode     = "preferred",
        position = "auto",
        scale    = "auto",
    })
    monitors = {}
end


-- --- VAR -------------------------------------------------------------------


local colors_ok, colors = pcall(require, "colors")
if not colors_ok then
    -- matugen has not been run yet: neutral fallback palette.
    colors = {
        primary           = "0xff82d5c9",
        outline_variant   = "0xff3f4947",
        shadow            = "0xff000000",
    }
end

local terminal    = "kitty"
local fileManager = "dolphin"
local dmenu       = "rofi -show drun"
local menu        = "rofi -show run"
local powermenu   = os.getenv("HOME") .. "/.local/bin/powermenu.sh"
local history     = os.getenv("HOME") .. "/.local/bin/dunst-history.sh"
local picker      = "hyprpicker -a"
local calc        = "qalculate-gtk"
local procsmng    = "kitty btop"


local mainMod     = "SUPER"

-- Optional: the control-center module renders this bind and its launcher.
pcall(dofile, HOME .. "/.config/hypr/control-center.lua")
-- Optional: osd, recorder and emoji add their binds only when installed.
pcall(dofile, HOME .. "/.config/hypr/osd.lua")



-- --- AUTOSTART -------------------------------------------------------------


hl.on("hyprland.start", function()
    -- Starts the entries enabled in ~/.local/state/dotfiles/autostart.tsv.
    -- Manage them with: autostart.sh list|enable|disable|pick
    hl.exec_cmd("command -v autostart.sh >/dev/null && autostart.sh run")
end)


-- --- LOOK AND FEEL ---------------------------------------------------------


hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 5,
        border_size = 2,

        col = {
            active_border   =  colors.primary,
            inactive_border = colors.outline_variant,
        },

        resize_on_border = false,
        allow_tearing = false,
        layout = "dwindle",
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2,

        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = colors.shadow,
        },

        blur = {
            enabled   = true,
            size      = 1,
            passes    = 4,
            vibrancy  = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },
})

hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })

hl.curve("easy",           { type = "spring", mass = 1, stiffness = 238.1191, dampening = 24.21279333 })

hl.animation({ leaf = "global",        enabled = true,  speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 4.1,  spring = "easy",         style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true,  speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7,    bezier = "quick" })

hl.config({
    dwindle = {
        preserve_split = true,
    },
})


-- --- MISC ------------------------------------------------------------------


hl.config({
    misc = {
        force_default_wallpaper  = 1,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true
    },
})


-- --- INPUT -----------------------------------------------------------------


hl.config({
    input = {
        kb_layout  = "us,ua",
        kb_variant = "",
        kb_model   = "",
        kb_options = "grp:caps_toggle,compose:ralt",
        kb_rules   = "",

        follow_mouse = 1,

        sensitivity = -0.3,
    },
})

-- Per-host overrides written by the interactive mouse tuner.
pcall(dofile, HOME .. "/.config/hypr/input.lua")


-- --- KEYBINDINGS -----------------------------------------------------------


hl.bind(mainMod .. " + C", hl.dsp.exec_cmd(calc))
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + SHIFT + Escape", hl.dsp.exec_cmd(procsmng))

hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(dmenu))
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd(menu))
-- theme-menu is optional; the bind does nothing when it is not installed.
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.exec_cmd("theme-menu.sh"))
-- binds-cheatsheet is optional; same rule.
hl.bind(mainMod .. " + SHIFT + K", hl.dsp.exec_cmd("binds-cheatsheet.sh --rofi"))
-- gamemode is optional; toggles animations, blur, shadows and rounding.
hl.bind(mainMod .. " + SHIFT + G", hl.dsp.exec_cmd("gamemode.sh toggle"))
-- idle is optional; this does nothing when the module is not installed.
hl.bind(mainMod .. " + SHIFT + I", hl.dsp.exec_cmd("idle-tune.sh toggle"))
-- monitor-profiles is optional; re-applies the dock layout on demand.
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exec_cmd("monitor-profiles.sh apply"))

-- autostart is optional; toggles login applications in a small menu.
hl.bind(mainMod .. " + SHIFT + A", hl.dsp.exec_cmd("autostart.sh pick"))

-- Lid switch: disable the internal panel only when another monitor is active,
-- otherwise suspend. Opening the lid always restores the internal panel.
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("lid-handler.sh closed"))
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("lid-handler.sh open"))

hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("clipboard-menu.sh"))
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd(powermenu))
hl.bind(mainMod .. " + H", hl.dsp.exec_cmd(history))
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd(picker))

hl.bind(mainMod .. " + SHIFT  + S", hl.dsp.exec_cmd('GRIMBLAST_EDITOR="swappy -f" grimblast --freeze edit area'))
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd("grimblast --freeze copy area"))

hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.exec_cmd("hyprctl kill"), { dont_inhibit = true })
hl.bind(mainMod .. " + Z", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + SHIFT  + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mainMod .. "  + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))

hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

hl.bind("SUPER + Y", hl.dsp.workspace.toggle_special("cam"))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })


-- --- SWITCH WORKSPACES -----------------------------------------------------
-- Workspace ranges are defined in ~/.config/hypr/monitors.lua (generated).
local max_ws = 10
for _, m in ipairs(monitors) do
    max_ws = math.max(max_ws, tonumber(m.ws_count) or 10)
end

-- switch-workspace.sh is installed by the optional workspaces-split module. Without
-- it, fall back to the native workspace dispatchers so a single-monitor setup
-- still gets working SUPER+1..0 bindings.
local switch_ws = HOME .. "/.local/bin/switch-workspace.sh"
local ws_handle = io.open(switch_ws, "r")
local has_switch_ws = ws_handle ~= nil
if ws_handle then ws_handle:close() end

for i = 1, max_ws do
    local key = i % 10

    if has_switch_ws then
        hl.bind(mainMod .. " + " .. key, function()
            hl.exec_cmd(switch_ws .. " focus " .. i)
        end, { dont_inhibit = true })

        hl.bind(mainMod .. " + SHIFT + " .. key, function()
            hl.exec_cmd(switch_ws .. " move " .. i)
        end)
    else
        hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }), { dont_inhibit = true })
        hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
    end
end


-- --- WINDOWS AND WORKSPACES ------------------------------------------------

-- Optional per-host workspace targets (see hosts/<host>/monitors.conf.sh)
local app_ws = monitors.app_workspaces or {}

local function app_workspace(key, fallback)
    local value = app_ws[key]
    if type(value) == "number" and value > 0 then
        return value
    end
    return fallback
end


-- Hyprland emits maximize events that make some games flicker; drop them.
local suppressMaximizeRule = hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

-- Xwayland drag proxies have no class or title; keep them out of focus.
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- imv is a quick image viewer; float it instead of claiming a workspace.
hl.window_rule({
    match = { class = "imv" },
    float = true,
})

-- mpv floats so a video does not rearrange the workspace layout.
hl.window_rule({
    match = { class = "mpv" },
    float = true,
})

-- Obsidian reopens on its own workspace so notes are always in the same place.
hl.window_rule({
    match = { class = ".*[Oo]bsidian.*" },
    workspace = tostring(app_workspace("obsidian", 5)) .. " silent",
})

-- Vesktop belongs on workspace 6, next to the other chat windows.
hl.window_rule({
    match = { class = ".*[Vv]esktop.*" },
    workspace = tostring(app_workspace("vesktop", 6)) .. " silent",
})

-- iriun turns a phone into a webcam; keep the preview on a special workspace.
hl.window_rule({
    match = { class = "^iriunwebcam$" },
    workspace = "special:cam silent",
})

-- Steam dialogs float; the main Steam window still tiles normally.
hl.window_rule({
    match = {
        class = "steam",
        title = "negative:^Steam$",
    },
    float = true,
})

-- Qalculate is a small calculator and works best as a floating window.
hl.window_rule({
    match = {
        class = "qalculate-gtk",
        title = "Qalculate!",
    },
    float = true,
})

-- GTK file dialogs from portals must float above the application.
hl.window_rule({
    match = {
        class = "xdg-desktop-portal-gtk",
    },
    float = true,
})

-- Protontricks is a one-shot dialog and should not tile.
hl.window_rule({
    match = {
        class = "zenity",
        title = "Protontricks",
    },
    float = true,
})

-- qBittorrent dialogs float; the main window keeps tiling.
hl.window_rule({
    match = {
        class = "org.qbittorrent.qBittorrent",
        title = "negative:qBittorrent",
    },
    float = true,
})

-- ProtonUp-qt is a small utility window.
hl.window_rule({
    match = {
        class = "net.davidotek.pupgui2",
    },
    float = true,
    size = {800, 600},
})

-- The remove-tools confirmation is tiny; give it the exact size it expects.
hl.window_rule({
    match = {
        class = "net.davidotek.pupgui2",
        title = "negative:Remove compatibility tools?",
    },
    float = true,
    size = {376, 101},

})

-- Zoom's annotation toolbar belongs on the camera workspace.
hl.window_rule({
    match = {
        class = "zoom",
        title = "annotate_toolbar",
    },
    workspace = "special:cam silent",
})

-- Control center helpers run in floating terminals so fzf, nmcli and the
-- package tools do not take over a workspace.
hl.window_rule({
    name = "dotfiles-control-center-float",
    match = { class = "^dotfiles-control-center$" },
    float = true,
    center = true,
    size = { 860, 560 },
})

-- Volume control floats above the focused window.
hl.window_rule({
    name = "pavucontrol-float",
    match = { class = "^(pavucontrol|org.pulseaudio.pavucontrol)$" },
    float = true,
    center = true,
    size = { 900, 600 },
})

-- nwg-look is a settings window and stays floating.
hl.window_rule({
    name = "nwg-look-float",
    match = { class = "^nwg-look$" },
    float = true,
    center = true,
    size = { 760, 700 },
})
