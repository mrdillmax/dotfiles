-- Optional: hyprsunset night light, restored from the helper's saved state.
-- nightlight.sh owns the daemon: it starts hyprsunset only when the filter is
-- on. Starting it here as well raced the restore and could leave two daemons
-- fighting over the same IPC socket.
-- The watcher applies the optional timer/sunset schedule once a minute; it
-- keeps a single instance across config reloads.
hl.exec_cmd("nightlight.sh restore")
hl.exec_cmd("nightlight.sh watch")
