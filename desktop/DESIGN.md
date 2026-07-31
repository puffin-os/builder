# Desktop design

- Ship the standard GNOME experience and preserve GNOME integration conventions.
- Target broad desktop/laptop hardware rather than a single reference device.
- Use the shared graphical installer and mandatory LUKS2 encryption of `/var`.
- Create conventional local users in persistent OverlayFS `/etc/passwd` and
  `/etc/shadow`; untouched defaults continue to follow `/usr/etc` in the
  selected root.
- Flatpak supplies the official GNOME Core application set and Bazaar as the
  application store. Refs and runtimes are locked to exact Flathub commits for
  reproducible, offline installation; normal Flatpak updates are allowed after
  installation.
- mise supplies CLI tools. Homebrew is deferred until it can be installed
  reproducibly without a network-dependent installer.
- Keep drivers, GNOME, login, portals, accessibility, and security integration
  image-owned rather than moving them into Flatpak.
- Bless a newly selected root only after graphical.target, GDM, and any staged
  first-boot provisioning succeed. Flatpaks below `/var/lib/flatpak` are not
  part of OS update staging.
