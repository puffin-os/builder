# Base scope

Read [DESIGN.md](DESIGN.md) and the shared
[architecture](https://github.com/puffin-os/builder/blob/main/docs/architecture.md).

The base owns only common boot, storage, firmware, networking, and systemd
policy. Do not add a desktop, installer, application distribution, container
engine, SSH daemon, or general-purpose CLI tooling here.
