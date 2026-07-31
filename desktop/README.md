# Puffin desktop

The GNOME Puffin desktop image, locked Flatpak seed, and graphical installer.

This repository is consumed by
[`puffin-os/builder`](https://github.com/puffin-os/builder). Run its tasks from
the assembled builder workspace:

```sh
task desktop:build
task desktop:check
task desktop:installer:build
```

See [DESIGN.md](DESIGN.md) for the image decisions.
