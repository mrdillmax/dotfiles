-- Per-host input overrides, loaded from hyprland.lua via pcall(dofile, ...).
-- The mouse tuner (./install.sh --mouse) writes this file after confirmation.
-- Example two-monitor preset ("dill-desktop"): global pointer sensitivity.

hl.config({
    input = {
        sensitivity = -0.3,
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
