#!/bin/sh
set -eu

image=${1:?image path required}
table=$(sfdisk --json "$image")

printf '%s\n' "$table" | grep -q '"name": "puffin_esp"'
printf '%s\n' "$table" | grep -q '"name": "puffin_.*_root"'
printf '%s\n' "$table" | grep -q '"name": "puffin_.*_verity"'
printf '%s\n' "$table" | grep -q '"name": "puffin_.*_verity_sig"'
printf '%s\n' "$table" | grep -q '"name": "puffin_etc"'
printf '%s\n' "$table" | grep -q '"name": "puffin_var"'
test "$(printf '%s\n' "$table" | grep -c '"name": "_empty"')" -eq 3

etc_device=$(LIBGUESTFS_BACKEND=direct guestfish --ro --format=raw -a "$image" \
    run : findfs-label puffin_etc)
test "$(LIBGUESTFS_BACKEND=direct guestfish --ro --format=raw -a "$image" \
    run : vfs-type "$etc_device")" = ext4
test "$(LIBGUESTFS_BACKEND=direct guestfish --ro --format=raw -a "$image" \
    run : mount-ro "$etc_device" / : ls /)" = lost+found

echo "Disk layout checks passed"
