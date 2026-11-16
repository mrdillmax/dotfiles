# Per-host input overrides for laptops, loaded from hyprland.lua.
# The mouse tuner (./install.sh --mouse) can add touchpad settings here.

hl.config({
    input = {
        sensitivity = 0.0,
        touchpad = {
            natural_scroll = true,
            tap_to_click = true,
            disable_while_typing = true,
        },
    },
})
