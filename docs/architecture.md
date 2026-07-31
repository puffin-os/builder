# Puffin architecture

## Image model

Puffin builds complete, versioned images. The base is a shared build and
filesystem contract, not a writable parent layer at runtime. Derivatives reuse
the base configuration and add only their packages and policy.

Arch packages come from a committed Arch Linux Archive snapshot. `pacman` may
remain available for inspection, but the running system is not updated by
mutating its package database. Image replacement is the OS update mechanism.

The boot payload is a signed Unified Kernel Image. Two equal EROFS root slots
and their dm-verity metadata form an A/B update set. `systemd-sysupdate` stages
signed root, Verity, Verity signature, and UKI resources without rebooting.
The UKI is committed last with three boot attempts; systemd-boot falls back to
the retained release unless the new boot reaches `boot-complete.target`.

Development keys are local and disposable. Production release keys, firmware
enrollment, and enforced Secure Boot are release-stage work.

## Filesystem contract

- `/` is EROFS and dm-verity protected.
- Factory configuration is versioned below `/usr/etc` in each immutable root.
- `/etc` is a writable OverlayFS mounted by the initrd. Its lower layer is the
  booted root's `/usr/etc`; persistent `upper/` and `work/` directories live on
  the ext4 `puffin_etc` partition mounted privately at `/run/puffin-etc`.
- `/var` is persistent and writable and grows to available disk space.
- Homes and root's home are stored in `/var/home` and `/var/roothome`.
- Persistent journals, application data, containers, and Flatpaks remain in
  their standard `/var` locations.
- `/run`, `/tmp`, `/dev`, `/proc`, and `/sys` are ephemeral Linux/systemd
  runtime exceptions.
- The ESP is normally unmounted. Update tooling may mount it below
  `/var/lib/puffin/esp`.

Untouched and reverted factory files follow the selected root. Local file
replacements, deletions, users, passwords, SSH host keys, installer settings,
and cloud-init output persist in the upper layer. Releases N and N-1 must both
accept the same `/etc` upper layer and `/var` state; irreversible migrations
must not run before boot blessing. Existing full-copy development `/etc`
partitions are not migrated and require reinstalling or recloning.

`/etc/machine-id` is empty in the factory tree and becomes persistent on first boot.
Hostname, timezone, local users, network configuration, SSH keys, and service
overrides use their standard locations below `/etc`.

## Configuration and services

System units, presets, sysusers, and tmpfiles definitions remain vendor content
under `/usr/lib`. Image presets provide defaults; administrators may persist
runtime enablement and overrides below `/etc`.

Actual per-user services use `/usr/lib/systemd/user` for vendor definitions and
the user's configuration below `/var/home`. Privileged daemons remain system
services. Installers stage a password hash and account intent; a first-boot
unit creates a conventional local account in `/etc/passwd` and `/etc/shadow`.

## Installation and storage

Installers offer one deliberate path: select a whole disk, confirm destructive
overwrite, apply the predefined GPT layout, and install. There is no manual
partition editor or dual-boot mode.

The common minimum layout is a 1 GiB ESP, two 8 GiB root slots with verity
metadata, a 256 MiB `/etc` filesystem, and `/var` using the remainder. Desktop
and workstation always encrypt `/var` with LUKS2. Server defaults to encryption
but permits an explicit opt-out. Immutable roots, `/etc`, and the ESP are not
encrypted.

The server receives a text installer. Desktop and workstation share a graphical
installer.

## Software delivery

- Flatpak supplies desktop/workstation applications.
- mise and Homebrew supply desktop/workstation CLI tools.
- Server supplies mise plus full Podman and Docker engines with runc.
- Core OS, drivers, desktop shell, and security components remain image-owned
  Arch packages.

## Stages

1. Build and boot the immutable base locally.
2. Add the server flavour and text installer.
3. Add the desktop flavour and graphical installer.
4. Add the workstation developer package layer.
5. Add production signing and update publication plus hardware
   installation/recovery validation.

## Updates and rollback

Stable repositories are separated by `IMAGE_ID` (`puffin-server`,
`puffin-desktop`, and `puffin-workstation`) and architecture. Every shared,
monotonically increasing `IMAGE_VERSION` publishes an EROFS root, Verity hash,
Verity signature, Secure-Boot-signed UKI, `SHA256SUMS`, and
`SHA256SUMS.gpg`. The repository base URL is release configuration and must
replace the `.invalid` placeholder before publication.

The automatic sysupdate timer stages at most two complete versions and never
reboots. `/var`, including desktop Flatpaks, is not reseeded. Boot health checks
only the immutable filesystem contract and flavour-critical services; optional
unit failures do not block blessing. Manual rollback remains available from
the systemd-boot menu or `bootctl`; damage to persistent state requires
recovery media.

Release artifacts are produced with `task publish-update FLAVOR=server|desktop
VERSION=<version> DESTINATION=<repository-root> GPG_KEY=<signing-key>`. The
command extracts only the populated version-labelled partitions, copies the
matching signed UKI, and signs their checksum manifest.
