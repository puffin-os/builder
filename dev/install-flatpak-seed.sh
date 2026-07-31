#!/bin/sh
set -eu

image=$(realpath "${1:?image path required}")
archive=$(realpath "${2:?Flatpak seed archive required}")
test -s "$image"
test -s "$archive"

var_device=$(LIBGUESTFS_BACKEND=direct guestfish --ro --format=raw -a "$image" \
    run : findfs-label puffin_var)
LIBGUESTFS_BACKEND=direct guestfish --format=raw -a "$image" <<EOF
run
mount $var_device /
rm-rf /lib/flatpak
mkdir-p /lib/flatpak
tar-in $archive /lib/flatpak compress:zstd
umount-all
EOF
echo "Installed Flatpak seed into $image"
