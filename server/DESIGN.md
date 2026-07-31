# Server design

## Image

`server/mkosi.conf` includes the base configuration and reuses its initrd,
repart definitions, signed UKI, EROFS roots, and dm-verity policy. The server
adds OpenSSH, firewalld, Docker, Podman, runc, mise, sudo, Vim, Nano, and common
diagnostic tools for processes, networking, hardware, storage, and filesystems.
Graphical UI packages, Flatpak, Homebrew, GNOME, and developer bundles remain
excluded. The server boots to a standard virtual-console login, and Vim is the
default editor. `getty@tty1.service` is explicitly enabled for the local login.

Cloud-init accepts Proxmox's NoCloud configuration drive. Its default `puffin`
administrator has a locked password, key-backed SSH access, and passwordless
sudo; Proxmox may replace the username, password hash, SSH keys, hostname, and
network configuration per clone. Cloud-init renders network intent for
systemd-networkd and does not resize the immutable root filesystem.

## Persistent state and services

Vendor enablement defaults are baked in through
`/usr/lib/systemd/system-preset`; administrators may persist overrides in
writable OverlayFS `/etc` above the selected root's `/usr/etc`. OpenSSH,
firewalld, Docker, and systemd-networkd start by
default. Podman remains daemonless.

- SSH host keys and configuration use `/etc/ssh`. Root and password SSH logins
  are disabled; public keys use each user's `.ssh/authorized_keys`.
- Docker uses `/var/lib/docker`. Rootless Podman state and Quadlets live below
  `/var/home`; the installed administrator has lingering enabled.
- Docker's firewalld zone and forwarding policy are immutable vendor
  definitions under `/usr/lib/firewalld`; Docker starts after firewalld.
- Administrator firewalld policy is stored normally below `/etc/firewalld`.
- Installer-created administrators use password-backed sudo; the locked
  cloud-init administrator uses passwordless sudo with key-backed SSH access.
- DHCP is the vendor default. Installer network intent is materialized as
  `/etc/systemd/network/20-puffin.network`; Proxmox cloud-init intent takes
  precedence from writable `/etc` before systemd-networkd starts.
- Hostname, console keyboard layout, and timezone use `/etc/hostname`,
  `/etc/vconsole.conf`, and `/etc/localtime`.

## Installer

The bootable raw installer contains a compressed server disk image. It accepts
one whole disk of at least 32 GiB, rejects the installer medium and mounted
targets, and requires a destructive yes/no confirmation that defaults to No.

The Gum-based text wizard collects hostname, console keyboard layout, timezone,
a conventional administrator, optional SSH key, Ethernet DHCP or static IPv4
settings, and encryption policy. It overwrites the disk with the fixed GPT
layout and grows `/var`.

LUKS2 encryption defaults on. The passphrase remains a recovery method and
TPM2 enrollment binds automatic unlock to PCR 7. Missing or failed TPM2
enrollment is a warning and leaves passphrase-only unlock. Encryption may be
explicitly disabled.

Initial machine and user intent is written below `/var/lib/puffin/provision`.
On the first installed boot, an image-owned unit writes standard `/etc`
configuration, creates the user with `useradd`, sets the staged SHA-512 password
hash, adds `wheel` and `docker` membership, installs the SSH key, enables
lingering, and removes the one-shot record. The plaintext account password is
never written to disk.

Boot blessing waits for completed installer provisioning when staged and for
OpenSSH. When a NoCloud datasource is detected it also requires successful
cloud-init completion; later Proxmox metadata availability is not required.
