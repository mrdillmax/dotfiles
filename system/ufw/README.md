# UFW notes (documentation only)

This repository does **not** enable, disable, reset, or modify UFW. It does not
add or remove rules. Use these commands manually after reviewing them.

## Observed live state

At the time of the audit:

- `/etc/ufw/ufw.conf`: `ENABLED=yes`
- `systemctl is-enabled ufw`: `enabled`
- `systemctl is-active ufw`: `active`
- default incoming policy: `DROP`
- default outgoing policy: `ACCEPT`

Live rules include:

| Port | Protocol | Purpose |
|------|----------|---------|
| 53 | tcp + udp | DNS (Pi-hole) |
| 80 | tcp + udp | local invite site |
| 25565 | tcp + udp | Minecraft (no listener at audit time) |
| 51515 | tcp + udp | optional service (no listener at audit time) |
| 8384 | tcp + udp | Syncthing web UI (listens on 127.0.0.1 only) |
| 47984, 47989, 47990, 48010 | tcp | Sunshine |
| 47998, 47999, 48000 | udp | Sunshine |
| 22000 | tcp + udp | Syncthing |
| 21027 | udp | Syncthing discovery |

Port 5335 (Unbound) is **not** open in the live rules and only listens on
`127.0.0.1`. Opening it to the LAN is normally unnecessary.

## Manual examples

Review the current state first:

```bash
sudo ufw status verbose
sudo ufw show added
```

Add only the rules you actually need:

```bash
sudo ufw allow 53
sudo ufw allow 80
sudo ufw allow 25565
sudo ufw allow 51515
sudo ufw allow 8384
```

Do not enable UFW remotely without first allowing your SSH port. Do not run
`ufw reset` unless you have a local console or another way back in.

## Why there is no preset

UFW state is security-sensitive and depends on what is actually running. The
owner confirmed that this repository should not touch it. The live state above
is recorded for reference only.
