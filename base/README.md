# Puffin base

The common boot, storage, firmware, networking, and systemd foundation for
Puffin images.

This repository is consumed by
[`puffin-os/builder`](https://github.com/puffin-os/builder). Run its tasks from
the assembled builder workspace:

```sh
task base:build
task base:check
task base:run
```

See [DESIGN.md](DESIGN.md) for the image decisions.
