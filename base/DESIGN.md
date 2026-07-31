# Base design

## Purpose

Produce the smallest useful common Puffin image: bootable on x86-64 UEFI,
capable of exercising a verified root with overlay-backed persistent `/etc` and `/var` in
QEMU, and suitable as the shared
definition for later physical-machine derivatives.

## Packages

Use Arch's `base` group, the standard `linux` kernel, common
`linux-firmware`, and both `amd-ucode` and `intel-ucode`. The firmware and
microcode cost is intentional: every physical derivative needs them.

Build-only tools do not enter the image.

## Enabled facilities

- systemd-journald
- systemd-networkd and systemd-resolved
- systemd-tmpfiles and systemd-sysusers
- systemd-repart and systemd-growfs
- serial and virtual console gettys

No display server, SSH, firewall, containers, Flatpak, Homebrew, mise, or
installer belongs in this layer.

## Development profile

The `dev` profile installs a boot check unit that emits `PUFFIN_BOOT_OK` after
verifying a dm-verity read-only root, writable OverlayFS `/etc` with persistent
backing, and writable persistent `/var`.

The base owns signed-manifest sysupdate transfers and boot assessment. Its
health service waits for `multi-user.target`; derivatives append only their
critical service checks. Updates stage automatically and reboot manually.
Root remains locked and no console uses automatic login.
