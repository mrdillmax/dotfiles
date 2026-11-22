# UFW policy

`./install.sh --system` (component `services`) applies one small policy and
then enables UFW:

- default **deny incoming**
- default **allow outgoing**
- `22/tcp` only when `sshd` exists
- `22000/tcp` and `22000/udp` only when `syncthing` exists

Nothing else is opened. Pi-hole (53), unbound (5335), the Syncthing web UI
(8384) and CUPS (631) are local-only services and get no rule.

The policy lives in `lib/firewall.sh`. `ufw show added` is read before adding,
so a second run adds no duplicate rules.

## Review the current state

```bash
sudo ufw status verbose
sudo ufw show added
```

## Local-only services

Pi-hole and unbound listen on loopback; other devices reach DNS through
Pi-hole on the machine's LAN address only if you add a rule yourself. Keep the
Pi-hole admin page local. Do not expose it to the internet.

## Safety

Allow your SSH port before enabling UFW on a remote machine. The installer does
this automatically when `sshd` is installed. Do not run `ufw reset` unless you
have a local console or another way back in.
