# Puffin server

The console-managed Puffin server image and its text installer.

This repository is consumed by
[`puffin-os/builder`](https://github.com/puffin-os/builder). Run its tasks from
the assembled builder workspace:

```sh
task server:build
task server:check
task server:installer:build
```

See [DESIGN.md](DESIGN.md) for the image decisions.
