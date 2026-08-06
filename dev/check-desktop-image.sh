#!/bin/sh
set -eu

image=${1:?image path required}
manifest=${2:?manifest path required}
project=$(realpath "$(dirname "$0")/..")

"$project/dev/check-image.sh" "$image"

for package in \
    firewalld flatpak gdm glibc-locales gnome-console gnome-control-center \
    gnome-disk-utility gnome-shell gnome-system-monitor mise nautilus \
    networkmanager orca pipewire plymouth sudo wireplumber \
    xdg-desktop-portal-gnome; do
    grep -q "\"name\": \"$package\"" "$manifest" ||
        { echo "missing package: $package" >&2; exit 1; }
done
for package in \
    docker gnome-software podman runc system-config-printer; do
    ! grep -q "\"name\": \"$package\"" "$manifest" ||
        { echo "forbidden package: $package" >&2; exit 1; }
done

start=$(sfdisk --json "$image" |
    awk '/"start":/ { value=$2; gsub(/,/, "", value) }
         /"name": "puffin_.*_root"/ { print value; exit }')
test -n "$start"

work=$(mktemp -d)
cleanup() {
    podman run --rm -v "$work:/check:Z" localhost/puffin-builder:26 \
        rm -rf -- /check/root 2>/dev/null || true
    rm -rf -- "$work"
}
trap cleanup EXIT INT TERM
if command -v fsck.erofs >/dev/null; then
    fsck.erofs --offset="$((start * 512))" --extract="$work/root" "$image" >/dev/null
else
    image=$(realpath "$image")
    case "$image" in
        "$project"/*) ;;
        *) echo "image must be below $project" >&2; exit 1 ;;
    esac
    podman run --rm \
        -v "$project:/work:Z" -v "$work:/check:Z" \
        localhost/puffin-builder:26 \
        fsck.erofs --offset="$((start * 512))" --extract=/check/root \
        "/work/${image#"$project"/}" >/dev/null
fi

for path in \
    usr/etc/crypttab \
    usr/etc/sudoers.d/10-puffin-wheel \
    usr/lib/NetworkManager/conf.d/10-puffin-dns.conf \
    usr/lib/puffin/provision-user \
    usr/lib/systemd/system/puffin-provision.service \
    usr/share/flatpak/remotes.d/flathub.flatpakrepo; do
    test -f "$work/root/$path" ||
        { echo "missing image path: /$path" >&2; exit 1; }
done
test -x "$work/root/usr/lib/puffin/provision-user"
test -x "$work/root/usr/lib/puffin/check-boot-health"
test -x "$work/root/usr/lib/puffin/check-desktop-health"
grep -qx 'IMAGE_ID="puffin-desktop"' "$work/root/usr/lib/os-release"
grep -qx 'IMAGE_VERSION="0.1.0"' "$work/root/usr/lib/os-release"
test -f "$work/root/usr/lib/systemd/import-pubring.gpg"
test -d "$work/root/etc"
test -z "$(find "$work/root/etc" -mindepth 1 -print -quit)"
podman run --rm -v "$work:/check:Z" localhost/puffin-builder:26 \
    sh -c 'rmdir /check/root/etc && ln -s usr/etc /check/root/etc'

for path in \
    usr/share/applications/avahi-discover.desktop \
    usr/share/applications/bssh.desktop \
    usr/share/applications/bvnc.desktop \
    usr/share/applications/cups.desktop \
    usr/share/applications/lstopo.desktop \
    usr/share/applications/qv4l2.desktop \
    usr/share/applications/qvidcap.desktop; do
    test ! -e "$work/root/$path" ||
        { echo "forbidden image path: /$path" >&2; exit 1; }
done

for service in \
    NetworkManager.service \
    bluetooth.service \
    cups.socket \
    firewalld.service \
    gdm.service \
    puffin-boot-health.service \
    puffin-provision.service \
    systemd-resolved.service \
    systemd-sysupdate.timer; do
    test "$(systemctl --root="$work/root" is-enabled "$service")" = enabled ||
        { echo "service is not enabled: $service" >&2; exit 1; }
done
test "$(systemctl --root="$work/root" is-enabled systemd-networkd.service)" = disabled
test "$(systemctl --root="$work/root" is-enabled systemd-homed.service 2>/dev/null || true)" = disabled
test "$(systemctl --root="$work/root" is-enabled sshd.service 2>/dev/null || true)" != enabled

grep -q '^dns=systemd-resolved$' \
    "$work/root/usr/lib/NetworkManager/conf.d/10-puffin-dns.conf"
grep -q '^Url=https://dl.flathub.org/repo/$' \
    "$work/root/usr/share/flatpak/remotes.d/flathub.flatpakrepo"
grep -q 'useradd --create-home' "$work/root/usr/lib/puffin/provision-user"
grep -q 'chpasswd --encrypted' "$work/root/usr/lib/puffin/provision-user"
grep -q 'SystemAccount=false' "$work/root/usr/lib/puffin/provision-user"
! grep -q 'homectl\\|systemd-homed' "$work/root/usr/lib/puffin/provision-user"
grep -q 'dconf compile' "$work/root/usr/lib/puffin/provision-user"
test "$(readlink "$work/root/usr/etc/localtime")" = /usr/share/zoneinfo/UTC

var_device=$(LIBGUESTFS_BACKEND=direct guestfish --ro --format=raw -a "$image" \
    run : findfs-label puffin_var)
flatpak_state=$(LIBGUESTFS_BACKEND=direct guestfish --ro --format=raw -a "$image" <<EOF
run
mount $var_device /
ls /lib/flatpak/app
cat /lib/flatpak/repo/config
EOF
)
while IFS= read -r app; do
    printf '%s\n' "$flatpak_state" | grep -qxF "$app" ||
        { echo "missing default Flatpak: $app" >&2; exit 1; }
done <"$project/desktop/flatpaks.apps"
printf '%s\n' "$flatpak_state" | grep -q 'remote "flathub"'

echo "Desktop image checks passed"
