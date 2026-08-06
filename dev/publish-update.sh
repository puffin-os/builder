#!/bin/sh
set -eu

image=${1:?disk image required}
uki=${2:?signed UKI required}
image_id=${3:?IMAGE_ID required}
version=${4:?IMAGE_VERSION required}
destination=${5:?destination required}
gpg_key=${6:?GPG signing key required}

case "$image_id" in puffin-server|puffin-desktop|puffin-workstation) ;; *) exit 2 ;; esac
case "$version" in *[!0-9A-Za-z._~-]*|'') exit 2 ;; esac

# Verify the image was built with the requested version.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
start=$(sfdisk --json "$image" |
    awk '/"start":/ { value=$2; gsub(/,/, "", value) }
         /"name": "puffin_.*_root"/ { print value; exit }')
test -n "$start"
fsck.erofs --offset="$((start * 512))" --extract="$work/root" "$image" >/dev/null
grep -qx "IMAGE_VERSION=\"$version\"" "$work/root/usr/lib/os-release" ||
    { echo "image IMAGE_VERSION does not match requested version $version" >&2; exit 2; }

mkdir -p "$destination/$image_id/x86-64"
destination=$destination/$image_id/x86-64
table=$(sfdisk --json "$image")

extract() {
    label=$1
    output=$2
    start=$(printf '%s\n' "$table" | jq -r ".partitiontable.partitions[] | select(.name == \"$label\") | .start")
    size=$(printf '%s\n' "$table" | jq -r ".partitiontable.partitions[] | select(.name == \"$label\") | .size")
    test -n "$start" && test -n "$size"
    dd if="$image" of="$destination/$output" bs=512 skip="$start" count="$size" status=none
}

extract "puffin_${version}_root" "puffin-${version}.root.raw"
extract "puffin_${version}_verity" "puffin-${version}.verity.raw"
extract "puffin_${version}_verity_sig" "puffin-${version}.verity-sig.raw"
install -m 0644 "$uki" "$destination/puffin-${version}.efi"

(
    cd "$destination"
    sha256sum "puffin-${version}.root.raw" "puffin-${version}.verity.raw" \
        "puffin-${version}.verity-sig.raw" "puffin-${version}.efi" >SHA256SUMS
    export GNUPGHOME=$(mktemp -d)
    trap 'rm -rf "$GNUPGHOME"' EXIT INT TERM
    gpg --batch --import "$gpg_key"
    gpg --batch --yes --local-user 'dev@puffin.invalid' \
        --detach-sign --output SHA256SUMS.gpg SHA256SUMS
)
