#!/bin/sh
set -eu

image=${1:?image path required}
manifest=${2:?manifest path required}
project=$(realpath "$(dirname "$0")/..")

"$project/dev/check-image.sh" "$image"

for package in \
    bind cloud-init dmidecode docker ethtool firewalld htop iotop-c jq less lsof mise \
    nano nvme-cli openssh podman rsync runc smartmontools strace sudo tcpdump \
    tmux tree vim; do
    grep -q "\"name\": \"$package\"" "$manifest" ||
        { echo "missing package: $package" >&2; exit 1; }
done
for package in awesome flatpak gnome-shell greetd greetd-agreety linuxbrew ttf-dejavu xorg-server xorg-setxkbmap xorg-xinit xterm; do
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
    usr/etc/cloud/cloud.cfg.d/90-puffin.cfg \
    usr/etc/crypttab \
    usr/etc/environment \
    usr/etc/ssh/sshd_config.d/10-puffin.conf \
    usr/etc/sudoers.d/10-puffin-wheel \
    usr/lib/firewalld/policies/docker-forwarding.xml \
    usr/lib/firewalld/zones/docker.xml \
    usr/lib/puffin/provision-user \
    usr/lib/systemd/system/docker.service.d/puffin.conf; do
    test -f "$work/root/$path" || { echo "missing image path: /$path" >&2; exit 1; }
done
test -x "$work/root/usr/lib/puffin/provision-user"
test -x "$work/root/usr/lib/puffin/check-boot-health"
test -x "$work/root/usr/lib/puffin/check-server-health"
grep -qx 'IMAGE_ID="puffin-server"' "$work/root/usr/lib/os-release"
grep -qx 'IMAGE_VERSION="0.1.0"' "$work/root/usr/lib/os-release"
test -f "$work/root/usr/lib/systemd/import-pubring.gpg"
test -d "$work/root/etc"
test -z "$(find "$work/root/etc" -mindepth 1 -print -quit)"
podman run --rm -v "$work:/check:Z" localhost/puffin-builder:26 \
    sh -c 'rmdir /check/root/etc && ln -s usr/etc /check/root/etc'
for service in \
    cloud-config.service \
    cloud-final.service \
    cloud-init-local.service \
    cloud-init-main.service \
    cloud-init-network.service \
    docker.service \
    firewalld.service \
    getty@tty1.service \
    puffin-boot-health.service \
    puffin-provision.service \
    sshd.service \
    systemd-networkd.service \
    systemd-sysupdate.timer; do
    test "$(systemctl --root="$work/root" is-enabled "$service")" = enabled ||
        { echo "service is not enabled: $service" >&2; exit 1; }
done
test "$(systemctl --root="$work/root" is-enabled systemd-homed.service 2>/dev/null || true)" = disabled

test ! -e \
    "$work/root/usr/lib/systemd/system/serial-getty@ttyS0.service.d/autologin.conf"
grep -q '^PermitRootLogin no$' "$work/root/usr/etc/ssh/sshd_config.d/10-puffin.conf"
grep -q '^PasswordAuthentication no$' "$work/root/usr/etc/ssh/sshd_config.d/10-puffin.conf"
grep -q '^datasource_list: \[NoCloud\]$' \
    "$work/root/usr/etc/cloud/cloud.cfg.d/90-puffin.cfg"
grep -q '^    name: puffin$' "$work/root/usr/etc/cloud/cloud.cfg.d/90-puffin.cfg"
grep -q '^resize_rootfs: false$' "$work/root/usr/etc/cloud/cloud.cfg.d/90-puffin.cfg"
grep -q 'LABEL=puffin_var_luks' "$work/root/usr/etc/crypttab"
grep -q 'useradd --create-home' "$work/root/usr/lib/puffin/provision-user"
grep -q 'chpasswd --encrypted' "$work/root/usr/lib/puffin/provision-user"
! grep -q 'homectl\\|systemd-homed' "$work/root/usr/lib/puffin/provision-user"
grep -q '^%wheel ALL=(ALL:ALL) ALL$' "$work/root/usr/etc/sudoers.d/10-puffin-wheel"
grep -q '^EDITOR=vim$' "$work/root/usr/etc/environment"
grep -q '<zone target="ACCEPT">' "$work/root/usr/lib/firewalld/zones/docker.xml"
grep -q '<ingress-zone name="ANY"/>' \
    "$work/root/usr/lib/firewalld/policies/docker-forwarding.xml"
grep -q '^After=firewalld.service$' \
    "$work/root/usr/lib/systemd/system/docker.service.d/puffin.conf"
test "$(readlink "$work/root/usr/etc/localtime")" = /usr/share/zoneinfo/UTC

echo "Server image checks passed"
