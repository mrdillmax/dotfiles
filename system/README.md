# Opt-in system configuration

Everything here is installed **only** with:

```bash
sudo ./install.sh --system
```

Each file is shown and confirmed separately. Every replaced file is backed up
under `~/.dotfiles-backup/<timestamp>/` for the invoking user (resolved via
`SUDO_USER`) and listed in `manifest.tsv`.

The installer never starts or restarts a service and never runs
`grub-mkconfig` or `mkinitcpio -P`. It prints the commands to review manually.

## Files

| Source | Destination | Notes |
|--------|-------------|-------|
| `zram/zram-generator.conf` | `/etc/systemd/zram-generator.conf` | zram swap, `ram / 2`, zstd |
| `cpupower/cpupower` | `/etc/default/cpupower` | `governor='performance'` |
| `networkmanager/dns.conf` | `/etc/NetworkManager/conf.d/dns.conf` | only with Pi-hole + Unbound |
| `networkmanager/rc-manager.conf` | `/etc/NetworkManager/conf.d/rc-manager.conf` | only with Pi-hole + Unbound |
| `pihole/dnsmasq.conf` | `/etc/pihole/dnsmasq.conf` | `@IFACE@` is rendered from the default route or `--iface` |
| `pihole/pihole.toml.example` | `/etc/pihole/pihole.toml` | review secrets manually; `@IFACE@` is rendered |
| `unbound/unbound.conf` | `/etc/unbound/unbound.conf` | |
| `wait-iface/wait-iface.sh` | `/usr/local/bin/wait-iface.sh` | generic NIC detection |
| `systemd/...` | `/etc/systemd/system/...` | |
| `pacman/hooks/dotfiles-pkg-sync.hook` | `/etc/pacman.d/hooks/dotfiles-pkg-sync.hook` | marks package changes for a later review |
| `pkg-sync/dotfiles-pkg-sync-mark.sh` | `/usr/local/bin/dotfiles-pkg-sync-mark.sh` | writes `/var/lib/dotfiles/pkg-sync.stamp` |
| `grub/default-grub` | `/etc/default/grub` | extra critical confirmation |
| `mkinitcpio/mkinitcpio.conf` | `/etc/mkinitcpio.conf` | extra critical confirmation |
| `modprobe/*` | `/etc/modprobe.d/*` | |
| `sysctl/*` | `/etc/sysctl.d/*` | |

## Merge-only presets

These files are **not copied**. The installer shows a unified diff, asks for
confirmation, creates a backup, and changes only the listed lines:

- `pacman/pacman.conf.preset` — `Color`, `ILoveCandy`,
  `ParallelDownloads = $(nproc)`, `[multilib]`.
- `makepkg/makepkg.conf.preset` — `MAKEFLAGS="-j$(nproc)"`.

In non-interactive mode (`--yes`) the merge step is skipped. Apply it manually
if needed.

## Services

`services/services.conf` lists optional services. The installer offers a
checklist and runs only `systemctl enable`, never `start` or `restart`. In
non-interactive mode it is skipped.

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now irqbalance ananicy-cpp preload lactd
sudo systemctl enable --now paccache.timer fstrim.timer
```

Review the commands before running them. `lactd` belongs with the NVIDIA/AMD
GPU profile, not with `vm` or `software`.

## Pi-hole interface

`@IFACE@` is replaced with:

1. `--iface IFACE` when supplied;
2. the default-route interface from `ip route`;
3. an interactive prompt when both fail.

If none of these produce a value, the installer **skips the file with an
error**. It never silently substitutes `enp9s0`.

`enp9s0` is never stored in universal templates. If a specific host needs a
fixed interface name, keep it in that host's generated preset, not in `system/`.

## DNS safety net

Before installing the NetworkManager DNS files, keep a working resolver
configuration:

```bash
sudo cp -a /etc/resolv.conf /etc/resolv.conf.before-dotfiles
```

Only apply `dns=none` / `rc-manager=unmanaged` when both Pi-hole and Unbound
are installed and configured. If DNS breaks, restore the backup or set:

```bash
echo 'nameserver 1.1.1.1' | sudo tee /etc/resolv.conf
```

## UFW

UFW is documented separately in `ufw/README.md`. This repository does not
change firewall state or rules.
