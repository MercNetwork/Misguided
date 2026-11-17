# MisguidedArch

![MisguidedArch](misguidedarch.png)

An automated Arch Linux installer by **Mercury**. Boot the Arch ISO, run one
script, answer a few questions, and get a finished desktop running on the
**CachyOS optimised repositories**, with Erik Dubois' **Arch Linux Tweak Tool**
ready to go.

## What it does

- Partitions and formats the disk you choose (btrfs, ext4, or LUKS-encrypted btrfs)
- Installs Arch, then makes **CachyOS the main repo** (packages built for your CPU:
  x86-64-v3, x86-64-v4 or Zen 4/5, detected automatically)
- Adds **nemesis_repo** and installs **archlinux-tweak-tool (ATT)**
- Installs a desktop: KDE, GNOME, Cinnamon, Awesome, dwm, Hyprland, or a headless server
- Installs **Firefox**, **fastfetch**, an AUR helper of your choice, zsh + powerlevel10k
- Themes GRUB (CyberRe) and Plymouth (arch-glow), sets up snapper on btrfs

## Install

From the Arch ISO, connected to the internet:

```bash
pacman -Sy git
git clone https://github.com/MercNetwork/Misguided
cd Misguided
./misguidedarch.sh
```

> **Warning:** the disk you pick is wiped completely.

Logs are copied to `/home/<you>/` after install (`startup.log`, `0-preinstall.log`, …).

## Repositories added

| Repo | Where in `pacman.conf` | Why |
|---|---|---|
| `cachyos-<level>`, `cachyos-core-<level>`, `cachyos-extra-<level>`, `cachyos` | above `[core]` (highest priority) | CPU-optimised builds of Arch packages, CachyOS kernels and tools |
| `core`, `extra`, `multilib` | unchanged | Arch Linux |
| `nemesis_repo` | at the end | Arch Linux Tweak Tool, Erik Dubois' themes and configs |

You can say **No** to CachyOS in the installer menu to stay on plain Arch repos.
The old config is kept at `/etc/pacman.conf.pre-cachyos`.

## Project layout

```
misguidedarch.sh        entry point: runs each phase in order and logs it
scripts/
  startup.sh            menus; writes your answers to configs/setup.conf
  0-preinstall.sh       live ISO: mirrors, partitions, filesystems, pacstrap
  1-setup.sh            chroot (root): locale, repos, base packages, drivers, user
  repos.sh              library: CachyOS + nemesis_repo functions
  2-user.sh             chroot (your user): desktop + AUR packages, dotfiles
  3-post-setup.sh       chroot (root): GRUB, display manager, services, cleanup
  curl-install.sh       one-line bootstrapper
pkg-files/              one package per line; edit these to change what gets installed
configs/                dotfiles, themes, KDE profile, zsh config
```

## Guide

Everything (editing, learning bash, combining with MisguidedNemesis, your own repo, Ansible) is in one file: **`../MISGUIDED_HANDBOOK.md`** (also `../MISGUIDED_HANDBOOK.epub` for phone reading). Start with Part 2.

## Credits

- [CachyOS](https://cachyos.org) for the optimised repositories
- [Erik Dubois](https://github.com/erikdubois) for nemesis_repo and the Arch Linux Tweak Tool
