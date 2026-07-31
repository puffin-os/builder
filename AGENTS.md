# Puffin

Read [docs/architecture.md](docs/architecture.md) before changing an image.
Then read the `DESIGN.md` referenced by the nearest flavour `AGENTS.md`.

## Invariants

- Arch Linux, x86-64 first, systemd-native facilities preferred.
- `/` is immutable; `/etc` and `/var` are persistent writable filesystems.
- Vendor system units live in `/usr/lib/systemd/system`; vendor user units live
  in `/usr/lib/systemd/user`.
- Image changes are declarative and reproducible from a pinned Arch snapshot.
- Keep the base small. A package or service belongs in the first derivative
  that needs it.
- Implement stages in order: base, server, desktop, workstation.

## Commands

- `task build` builds the base disk image.
- `task run` boots a persistent local VM overlay.
- `task check` performs static and boot validation.
- `task server:build`, `server:run`, and `server:check` operate on the server.
- `task server:installer:build` and `server:installer:run` operate on its
  bootable installation medium.
- `task server:installer:installed-run` boots the disk produced by that installer.
