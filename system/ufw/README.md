# UFW firewall

`./install.sh --system` (component `services`) applies a minimal firewall
policy and enables UFW:

- Default: **deny incoming**, **allow outgoing**
- `22/tcp` — only when `sshd` is installed
- `22000/tcp` and `22000/udp` — only when `syncthing` is installed

No other ports are opened. Pi-hole (53), unbound (5335), Syncthing web UI
(8384) and CUPS (631) are local-only services and get no rule.

## Check the status

```bash
sudo ufw status verbose
sudo ufw show added
```

## Safety

Always allow your SSH port **before** enabling UFW on a remote machine.
The installer does this automatically when `sshd` is installed. Do not
run `ufw reset` unless you have a local console or another way back in.
