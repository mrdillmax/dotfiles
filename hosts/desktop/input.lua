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

-- Four-finger horizontal swipe moves the active window to the next or previous
-- workspace without following it. Accumulate the delta so a short accidental
-- swipe does not move anything.
local four_finger_x = 0
hl.gesture({
    fingers = 4,
    direction = "horizontal",
    action = {
        start = function()
            four_finger_x = 0
        end,
        update = function(e)
            four_finger_x = four_finger_x + e.delta.x
        end,
        finish = function(e)
            if e.cancelled then return end
            local target
            if four_finger_x < -120 then
                target = "e+1"
            elseif four_finger_x > 120 then
                target = "e-1"
            else
                return
            end
            hl.dispatch(hl.dsp.window.move({ workspace = target }))
        end,
    },
})
