#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
mode=${1:-installer}
flavor=${PUFFIN_FLAVOR:-server}
state=$root/state
case "$flavor" in
    server)
        image=$root/out/puffin-server-installer-x86-64.raw
        medium=$state/puffin-server-installer.qcow2
        target=$state/puffin-server-target.qcow2
        vars=$state/OVMF_VARS-installer.fd
        tpm_state=$state/tpm
        tpm_socket=$state/swtpm.sock
        ;;
    desktop)
        image=$root/out/puffin-desktop-installer-x86-64.raw
        medium=$state/puffin-desktop-installer.qcow2
        target=$state/puffin-desktop-target.qcow2
        vars=$state/OVMF_VARS-desktop-installer.fd
        tpm_state=$state/tpm-desktop
        tpm_socket=$state/swtpm-desktop.sock
        ;;
    *)
        echo "unknown installer flavor: $flavor" >&2
        exit 2
        ;;
esac

find_firmware() {
    value=$1
    shift
    if test -n "$value"; then
        printf '%s\n' "$value"
        return
    fi
    for candidate do
        test -f "$candidate" && { printf '%s\n' "$candidate"; return; }
    done
    return 1
}

code=$(find_firmware "${OVMF_CODE:-}" \
    /usr/share/edk2/ovmf/OVMF_CODE.fd \
    /usr/share/OVMF/OVMF_CODE.fd)
vars_template=$(find_firmware "${OVMF_VARS:-}" \
    /usr/share/edk2/ovmf/OVMF_VARS.fd \
    /usr/share/edk2/ovmf/OVMF.qemuvars.fd \
    /usr/share/OVMF/OVMF_VARS.fd)

case "$mode" in
    installer)
        test -f "$image" ||
            { echo "missing $image; build the $flavor installer first" >&2; exit 1; }
        mkdir -p "$state" "$tpm_state"
        test -f "$medium" ||
            qemu-img create -q -f qcow2 -F raw -b "$image" "$medium"
        test -f "$target" || qemu-img create -q -f qcow2 "$target" 40G
        test -f "$vars" || cp --reflink=auto "$vars_template" "$vars"
        ;;
    installed)
        test -f "$target" ||
            { echo "missing installed target; run the $flavor installer first" >&2; exit 1; }
        test -f "$vars" && test -d "$tpm_state" ||
            { echo "missing installer firmware or TPM state" >&2; exit 1; }
        ;;
    *)
        echo "usage: $0 [installer|installed]" >&2
        exit 2
        ;;
esac
rm -f -- "$tpm_socket"

swtpm socket \
    --tpm2 \
    --tpmstate "dir=$tpm_state" \
    --ctrl "type=unixio,path=$tpm_socket" \
    --flags not-need-init,startup-clear \
    --daemon
trap 'rm -f -- "$tpm_socket"' EXIT INT TERM

set -- qemu-system-x86_64 \
    -machine q35,accel=kvm \
    -cpu host \
    -smp "${VM_CPUS:-2}" \
    -m "${VM_MEMORY:-4G}" \
    -drive "if=pflash,format=raw,readonly=on,file=$code" \
    -drive "if=pflash,format=raw,file=$vars"
if test "$mode" = installer; then
    set -- "$@" \
        -drive "if=none,id=installer,format=qcow2,file=$medium" \
        -device virtio-blk-pci,drive=installer,bootindex=1 \
        -drive "if=none,id=target,format=qcow2,file=$target" \
        -device virtio-blk-pci,drive=target,bootindex=2
else
    set -- "$@" \
        -drive "if=none,id=target,format=qcow2,file=$target" \
        -device virtio-blk-pci,drive=target,bootindex=1
fi

exec "$@" \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0 \
    -chardev "socket,id=chrtpm,path=$tpm_socket" \
    -tpmdev emulator,id=tpm0,chardev=chrtpm \
    -device tpm-tis,tpmdev=tpm0 \
    -device virtio-vga-gl \
    -serial stdio \
    -display gtk,gl=on
