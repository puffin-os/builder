#!/bin/sh
set -eu

image=${1:?image path required}
table=$(sfdisk --json "$image")

printf '%s\n' "$table" | grep -q '"name": "puffin_installer_esp"'
printf '%s\n' "$table" | grep -q '"name": "puffin_installer_.*_root"'
printf '%s\n' "$table" | grep -q '"name": "puffin_installer_.*_verity"'
printf '%s\n' "$table" | grep -q '"name": "puffin_etc"'
printf '%s\n' "$table" | grep -q '"name": "puffin_var"'

start=$(printf '%s\n' "$table" |
    awk '/"start":/ { value=$2; gsub(/,/, "", value) }
         /"name": "puffin_installer_.*_root"/ { print value; exit }')
test -n "$start"

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT INT TERM
fsck.erofs --offset="$((start * 512))" --extract="$work/root" "$image" >/dev/null

installer=$work/root/usr/bin/puffin-install
test -x "$installer"
test -x "$work/root/usr/bin/cage"
test -x "$work/root/usr/bin/seatd"
test -s "$work/root/usr/lib/puffin/puffin-desktop-x86-64.raw.zst"
test -s "$work/root/usr/lib/puffin/puffin-desktop-flatpaks-x86-64.tar.zst"
test "$(systemctl --root="$work/root" is-enabled puffin-desktop-installer.service)" = enabled

python -m py_compile "$installer"
"$installer" --self-test
grep -q 'MINIMUM_DISK = 33_822_867_456' "$installer"
grep -q -- '--tpm2-pcrs=7' "$installer"
grep -q 'puffin-desktop-flatpaks-x86-64.tar.zst' "$installer"
grep -q 'flatpak.chmod(0o755)' "$installer"
grep -q 'list-x11-keymap-layouts' "$installer"
grep -q 'list-timezones' "$installer"
grep -q '^Environment=LIBSEAT_BACKEND=seatd$' \
    "$work/root/usr/lib/systemd/system/puffin-desktop-installer.service"
test "$(systemctl --root="$work/root" is-enabled seatd.service)" = enabled

echo "Desktop installer image checks passed"
