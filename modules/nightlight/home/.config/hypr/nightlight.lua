-- Optional: hyprsunset night light, restored from the helper's saved state.
-- The watcher applies the optional timer/sunset schedule once a minute; it
-- keeps a single instance across config reloads.
hl.exec_cmd("hyprsunset")
hl.exec_cmd("nightlight.sh restore")
hl.exec_cmd("nightlight.sh watch")
