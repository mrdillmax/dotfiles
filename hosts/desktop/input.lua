# Per-host input overrides, loaded from hyprland.lua via pcall(dofile, ...).
# The mouse tuner (./install.sh --mouse) writes this file after confirmation.
# Example two-monitor preset ("dill-desktop"): global pointer sensitivity.

hl.config({
    input = {
        sensitivity = -0.3,
    },
})
