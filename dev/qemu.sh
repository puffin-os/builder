#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
flavor=${PUFFIN_FLAVOR:-base}
image="$root/out/puffin-$flavor-x86-64.raw"
state="$root/state"
overlay="$state/puffin-$flavor.qcow2"
vars="$state/OVMF_VARS-$flavor.fd"
mode=${1:-run}

find_firmware() {
    value=$1
    shift
    if test -n "$value"; then
        printf '%s\n' "$value"
        return
    fi
    for candidate do
        if test -f "$candidate"; then
            printf '%s\n' "$candidate"
            return
        fi
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

test -f "$image" || {
    echo "missing $image; run the matching task <component>:build" >&2
    exit 1
}

mkdir -p "$state"

new_overlay() {
    target=$1
    rm -f -- "$target"
    qemu-img create -q -f qcow2 -F raw -b "$image" "$target"
}

new_vars() {
    target=$1
    rm -f -- "$target"
    cp --reflink=auto "$vars_template" "$target"
}

run_vm() {
    disk=$1
    nvram=$2
    if test "${PUFFIN_GRAPHICS:-0}" = 1; then
        display='-device virtio-vga-gl -display gtk,gl=on'
    elif test "$flavor" = desktop-installer; then
        display='-device virtio-vga-gl -display egl-headless,gl=on -serial stdio'
    else
        display=-nographic
    fi
    # shellcheck disable=SC2086
    qemu-system-x86_64 \
        -machine q35,accel=kvm \
        -cpu host \
        -smp "${VM_CPUS:-2}" \
        -m "${VM_MEMORY:-4G}" \
        -uuid 8cc7bc2e-1313-4e8f-9f40-f403ec45c088 \
        -drive "if=pflash,format=raw,readonly=on,file=$code" \
        -drive "if=pflash,format=raw,file=$nvram" \
        -drive "if=none,id=os,format=qcow2,file=$disk,cache=writeback" \
        -device virtio-blk-pci,drive=os \
        -netdev user,id=net0 \
        -device virtio-net-pci,netdev=net0 \
        $display
}

wait_for_marker() {
    expected=$1
    log=$2
    disk=$3
    nvram=$4

    run_vm "$disk" "$nvram" >"$log" 2>&1 &
    pid=$!
    trap 'kill "$pid" 2>/dev/null || true' EXIT INT TERM

    attempts=0
    while test "$attempts" -lt 120; do
        if grep -q "PUFFIN_BOOT_OK $expected" "$log"; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            trap - EXIT INT TERM
            return
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid" || true
            cat "$log" >&2
            exit 1
        fi
        attempts=$((attempts + 1))
        sleep 1
    done

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    cat "$log" >&2
    echo "timed out waiting for $expected boot marker" >&2
    exit 1
}

if test "$mode" = "--check"; then
    check_overlay="$state/check.qcow2"
    check_vars="$state/check-vars.fd"
    check_log="$state/check.log"
    new_overlay "$check_overlay"
    new_vars "$check_vars"
    wait_for_marker initial "$check_log" "$check_overlay" "$check_vars"
    if test "$flavor" = desktop-installer; then
        attempts=0
        while ! grep -Eq 'PUFFIN_INSTALLER_UI_OK|Modesetting with' "$check_log"; do
            test "$attempts" -lt 30 || {
                cat "$check_log" >&2
                echo "timed out waiting for graphical installer" >&2
                exit 1
            }
            attempts=$((attempts + 1))
            sleep 1
        done
    fi
    wait_for_marker persistent "$check_log" "$check_overlay" "$check_vars"
    rm -f -- "$check_overlay" "$check_vars" "$check_log"
    echo "QEMU boot and /var persistence checks passed"
    exit
fi

test "$mode" = "run" || {
    echo "usage: $0 [run|--check]" >&2
    exit 2
}

test -f "$overlay" || qemu-img create -q -f qcow2 -F raw -b "$image" "$overlay"
test -f "$vars" || cp --reflink=auto "$vars_template" "$vars"
run_vm "$overlay" "$vars"
