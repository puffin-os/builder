# Workstation design

Workstation inherits the complete desktop hardware, GNOME, account, software
delivery, encryption, and graphical installer policy.

Its only distinction is an image-owned developer package set and developer
defaults. Add packages only for a concrete supported workflow; language and
project-specific toolchains continue to come from mise or Homebrew.

It inherits the desktop `/usr/etc` overlay contract, boot health gate, and
independent `/var/lib/flatpak` lifecycle, and uses its own stable update
repository when implemented.
