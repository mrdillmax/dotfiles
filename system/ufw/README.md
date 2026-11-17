# UFW notes

This repository does not manage UFW. It never enables, disables, resets or
changes rules. Review the current state and add rules manually.

## Review the current state

```bash
sudo ufw status verbose
sudo ufw show added
```

Check that the default policies match your setup before adding rules:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
```

## Add only the rules you need

Examples for common local services:

```bash
sudo ufw allow 22/tcp          # SSH
sudo ufw allow 53              # DNS on tcp and udp
sudo ufw allow 80/tcp          # local web service
```

Pi-hole and Unbound usually need port 53 on the LAN. Unbound on port 5335
listens on `127.0.0.1` and normally needs no rule. Keep the Pi-hole admin page
on the LAN or on localhost. Do not expose it to the internet.

## Safety

Allow your SSH port before enabling UFW on a remote machine. Do not run
`ufw reset` unless you have a local console or another way back in.

## Why there is no preset

Firewall rules depend on the services that actually run on the machine. The
repository documents the interaction only and leaves the rules to the operator.
