# Puffin

Puffin is an immutable Arch Linux distribution family:

- **base** provides the common bootable foundation;
- **server** targets console-managed server workloads;
- **desktop** targets everyday GNOME users;
- **workstation** adds developer tooling to the desktop.

The base, server, and desktop image stages are implemented.
See [docs/architecture.md](docs/architecture.md) for the system contract and
each flavour's `DESIGN.md` for its decisions.

## Requirements

- Podman
- QEMU with KVM and OVMF
- [Task](https://taskfile.dev/)
- [vendir](https://carvel.dev/vendir/)

The image builder itself runs in a privileged, project-owned Podman container,
so immutable hosts do not need mkosi or pacman installed.

Fetch the component repositories after cloning the builder:

```sh
task sync
```

## Use

```sh
task build
task run
task check
```

`task run` boots `state/puffin-base.qcow2`, a persistent overlay backed by the
pristine raw image in `out/`. Delete only that VM state with `task reset`.

Build and validate the server derivative:

```sh
task server:build
task server:check
task server:run
```

Build and validate the GNOME desktop derivative:

```sh
task desktop:build
task desktop:check
task desktop:run
```

The desktop build installs the locked GNOME Core Flatpaks and Bazaar
system-wide. Refresh those pins explicitly with `task desktop:flatpaks:lock`.

Build and boot its installer with a disposable 40 GiB QEMU target:

```sh
task server:installer:build
task server:installer:check
task server:installer:run
```

After installation finishes, close the installer VM and boot the installed
target with:

```sh
task server:installer:installed-run
```

Build and boot the graphical desktop installer:

```sh
task desktop:installer:build
task desktop:installer:check
task desktop:installer:run
```

After installation, boot its encrypted target with:

```sh
task desktop:installer:installed-run
```

Optional overrides:

```sh
VM_CPUS=4 VM_MEMORY=8G task run
OVMF_CODE=/path/to/OVMF_CODE.fd OVMF_VARS=/path/to/OVMF_VARS.fd task run
```

## Components

The canonical image definitions live in separate `puffin-os` repositories and
are not tracked by the builder repository. Fetch or refresh the local component
directories with:

```sh
task sync
```

Commit only the resulting `vendir.lock.yml` change when advancing component
revisions.

The development image has root autologin on the serial console. This is a
development profile only; the normal base keeps root locked.
