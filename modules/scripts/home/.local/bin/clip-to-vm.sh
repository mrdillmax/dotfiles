#!/bin/sh
SOCK=/var/lib/libvirt/qemu/clip.sock
while true; do
  if [ -S "$SOCK" ]; then
    sudo setfacl -m u:"$USER":rw "$SOCK"
    socat -u EXEC:"wl-paste --type text --watch $HOME/.local/bin/clip-emit.sh" UNIX-CONNECT:"$SOCK"
  fi
  sleep 2
done
