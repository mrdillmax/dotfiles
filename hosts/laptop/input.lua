-- Per-host input overrides for laptops, loaded from hyprland.lua.
-- The mouse tuner (./install.sh --mouse) can add touchpad settings here.

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

-- Three-finger horizontal swipe switches workspaces.
hl.config({
    gestures = {
        workspace_swipe_distance = 300,
        workspace_swipe_cancel_ratio = 0.5,
        workspace_swipe_min_speed_to_force = 5,
    },
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})
