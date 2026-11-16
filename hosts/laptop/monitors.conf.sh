# shellcheck shell=bash disable=SC2034
# Monitor layout template for laptops. install.sh rewrites this file after
# detecting the built-in panel and any external outputs.
#
# Example (single 2880x1800 panel at 200% scale):
#   MON_COUNT=1
#   MON_NAME=("eDP-1")
#   MON_MODE=("2880x1800@120")
#   MON_POSITION=("0x0")
#   MON_SCALE=("2")
#   MON_WS_FIRST=(1)
#   MON_WS_COUNT=(10)

MON_COUNT=1
MON_NAME=("eDP-1")
MON_MODE=("preferred")
MON_POSITION=("0x0")
MON_SCALE=("1")
MON_WS_FIRST=(1)
MON_WS_COUNT=(10)

APP_WS_VESKTOP=2
APP_WS_OBSIDIAN=3
