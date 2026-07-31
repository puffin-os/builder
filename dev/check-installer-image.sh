#!/bin/sh
set -eu

image=${1:?image path required}
table=$(sfdisk --json "$image")

printf '%s\n' "$table" | grep -q '"name": "puffin_installer_esp"'
printf '%s\n' "$table" | grep -q '"name": "puffin_installer_.*_root"'
printf '%s\n' "$table" | grep -q '"name": "puffin_installer_.*_verity"'
printf '%s\n' "$table" | grep -q '"name": "puffin_installer_.*_verity_sig"'
printf '%s\n' "$table" | grep -q '"name": "puffin_etc"'
printf '%s\n' "$table" | grep -q '"name": "puffin_var"'

start=$(printf '%s\n' "$table" |
    awk '/"start":/ { value=$2; gsub(/,/, "", value) }
         /"name": "puffin_installer_.*_root"/ { print value; exit }')
test -n "$start"

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT INT TERM
fsck.erofs --offset="$((start * 512))" --extract="$work/root" "$image" >/dev/null

test -x "$work/root/usr/bin/puffin-install"
test -x "$work/root/usr/bin/gum"
test -f "$work/root/usr/lib/puffin/puffin-server-x86-64.raw.zst"
test "$(systemctl --root="$work/root" is-enabled puffin-installer.service)" = enabled
sh -n "$work/root/usr/bin/puffin-install"
"$work/root/usr/bin/puffin-install" --self-test
grep -q 'list-keymaps' "$work/root/usr/bin/puffin-install"
grep -q 'list-timezones' "$work/root/usr/bin/puffin-install"

echo "Installer image checks passed"
