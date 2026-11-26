# Opt-in system configuration

These files are installed **only** with:

```bash
sudo ./install.sh --system
```

Each file is shown and confirmed individually. Every replaced file is backed
up under `~/.dotfiles-backup/<timestamp>/` and listed in a manifest.

## How it works

Selected services are enabled with `systemctl enable --now`
(`irqbalance` and `ananicy-cpp` are preselected). When GRUB or mkinitcpio
files are installed, `grub-mkconfig` and `mkinitcpio -P` are run.
Failures warn but do not abort.

The GRUB, mkinitcpio and `modprobe/nvidia.conf` files are installed only
when the GPU profile is `nvidia` or `hybrid`. Other profiles skip them.

The getty autologin drop-in uses `--autologin-user`, `SUDO_USER` or the
invoking login. It always requires separate confirmation.

## Components

| Component | What it does |
|-----------|-------------|
| **DNS** | Pi-hole (ad-blocking DNS) + unbound (DNS-over-TLS resolver) |
| **zram** | Compressed swap device in RAM |
| **cpupower** | CPU frequency scaling governor (ondemand/performance) |
| **Services** | irqbalance (IRQ distribution), ananicy-cpp (priority auto-tuning) |
| **Pacman** | [multilib] repository + pacman hooks (snapper, reflector) |
| **GRUB** | Bootloader config (NVIDIA/hybrid only) |
| **mkinitcpio** | Initramfs hooks (NVIDIA/hybrid only) |
| **Autologin** | Getty autologin drop-in |
| **UFW** | Firewall with minimal policy (see [UFW README](ufw/README.md)) |

## Safety

- No service is restarted except those explicitly listed above
- No bootloader is regenerated except grub-mkconfig / mkinitcpio -P
- Every file is backed up before replacement
- You can review each file before it is installed
- Run `./install.sh --doctor` for a read-only check

## After installation

Check the status of key services:

```bash
systemctl status irqbalance ananicy-cpp power-profiles-daemon
sudo ufw status verbose
pihole status
```
