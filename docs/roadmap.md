# Roadmap

## Stage 1 — base

Build a signed, verity-backed Arch disk; boot it through OVMF in QEMU; prove
that root is read-only and `/var` persists.

## Stage 2 — server

Add networking administration, SSH, firewalling, container engines, Awesome,
and the destructive text installer.

## Stage 3 — desktop

Add GNOME, broad desktop hardware support, Flatpak, CLI managers, local users,
and the graphical installer.

## Stage 4 — workstation

Extend desktop with developer-focused packages and defaults.

## Release work

Add protected signing infrastructure, Secure Boot enrollment, published
systemd-sysupdate metadata, rollback policy, recovery media, and physical
hardware qualification.
