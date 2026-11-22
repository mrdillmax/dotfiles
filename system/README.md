# Opt-in system configuration

Everything here is installed **only** with:

```bash
sudo ./install.sh --system
```

Each file is shown and confirmed separately. Every replaced file is backed up
under `~/.dotfiles-backup/<timestamp>/` for the invoking user (resolved via
`SUDO_USER`) and listed in `manifest.tsv`.

Selected services are enabled and started with `systemctl enable --now`
(`irqbalance` and `ananicy-cpp` are preselected); `cpupower` is enabled when
its component runs. After a GRUB or mkinitcpio file is installed, the system
step runs `grub-mkconfig` and `mkinitcpio -P`. Failures warn; they do not abort
the run.

The GRUB, mkinitcpio and `modprobe/nvidia.conf` files are installed only when
the selected GPU profile is `nvidia` or `hybrid`. Other GPU profiles skip them
and keep their existing boot and initramfs configuration.

The getty autologin drop-in is rendered from `--autologin-user`, `SUDO_USER`
or the invoking login. It always requires a separate confirmation.

## Files

| Source | Destination | Notes |
|--------|-------------|-------|
| `zram/99-dotfiles.conf` | `/etc/systemd/zram-generator.conf.d/99-dotfiles.conf` | zram swap, `ram / 2`, zstd |
| `cpupower/cpupower` | `/etc/default/cpupower` | `governor='performance'`; `cpupower.service` is enabled |
| `networkmanager/dns.conf` | `/etc/NetworkManager/conf.d/dns.conf` | only with Pi-hole + Unbound |
| `networkmanager/rc-manager.conf` | `/etc/NetworkManager/conf.d/rc-manager.conf` | only with Pi-hole + Unbound |
| `pihole/dotfiles-dnsmasq.conf` | `/etc/dnsmasq.d/dotfiles.conf` | extra dnsmasq settings; FTL reads it when `misc.etc_dnsmasq_d` is true |
| `pihole/adlists.txt` | gravity database | URLs inserted by `install.sh`; `pihole -g` runs once when something was added |
| `unbound/pi-hole.conf` | `/etc/unbound/unbound.conf.d/pi-hole.conf` | validated with `unbound-checkconf`; the stock config is untouched |
| `wait-iface/wait-iface.sh` | `/usr/local/bin/wait-iface.sh` | generic NIC detection |
| `systemd/...` | `/etc/systemd/system/...` | |
| `pacman/hooks/dotfiles-pkg-sync.hook` | `/etc/pacman.d/hooks/dotfiles-pkg-sync.hook` | marks package changes for a later review |
| `pkg-sync/dotfiles-pkg-sync-mark.sh` | `/usr/local/bin/dotfiles-pkg-sync-mark.sh` | writes `/var/lib/dotfiles/pkg-sync.stamp` |
| `grub/99-dotfiles.cfg` | `/etc/default/grub.d/99-dotfiles.cfg` | kernel cmdline; nvidia/hybrid only; extra critical confirmation |
| `mkinitcpio/99-dotfiles.conf` | `/etc/mkinitcpio.conf.d/99-dotfiles.conf` | MODULES/HOOKS; nvidia/hybrid only; extra critical confirmation |
| `modprobe/nvidia.conf` | `/etc/modprobe.d/nvidia.conf` | nvidia/hybrid only |
| `modprobe/*` | `/etc/modprobe.d/*` | other modprobe files |

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
error**. It never silently substitutes a fixed interface name.

Universal templates contain only `@IFACE@`. If a specific host needs a fixed
interface name, keep it in that host's generated preset, not in `system/`.

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
