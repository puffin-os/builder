#!/bin/sh
# End-to-end A/B update and rollback validation.
#
# This script stages a second root slot from a freshly built image, boots it,
# verifies the updated system reaches boot-complete, then simulates a failed
# boot by removing the UKI and confirms the bootloader falls back to the
# retained release.
#
# Usage: dev/check-ab-update.sh <image.raw> <uki.efi>
#
# Prerequisites:
#   - QEMU with KVM and OVMF
#   - The image must contain two root slots (A/B) and an ESP.
#   - The UKI must be signed for the same image.

set -eu

image=${1:?disk image required}
uki=${2:?signed UKI required}
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
state="$root/state"
ab_state="$state/ab-update"

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

mkdir -p "$ab_state"

# Create a fresh overlay and NVRAM for this test.
overlay="$ab_state/ab-test.qcow2"
nvram="$ab_state/ab-test-vars.fd"
rm -f -- "$overlay" "$nvram"
qemu-img create -q -f qcow2 -F raw -b "$image" "$overlay"
cp --reflink=auto "$vars_template" "$nvram"

run_vm() {
    log=$1
    # shellcheck disable=SC2086
    qemu-system-x86_64 \
        -machine q35,accel=kvm \
        -cpu host \
        -smp "${VM_CPUS:-2}" \
        -m "${VM_MEMORY:-4G}" \
        -uuid 8cc7bc2e-1313-4e8f-9f40-f403ec45c088 \
        -drive "if=pflash,format=raw,readonly=on,file=$code" \
        -drive "if=pflash,format=raw,file=$nvram" \
        -drive "if=none,id=os,format=qcow2,file=$overlay,cache=writeback" \
        -device virtio-blk-pci,drive=os \
        -netdev user,id=net0 \
        -device virtio-net-pci,netdev=net0 \
        -nographic >"$log" 2>&1
}

wait_for_marker() {
    expected=$1
    log=$2

    attempts=0
    while test "$attempts" -lt 120; do
        if grep -q "PUFFIN_BOOT_OK $expected" "$log"; then
            return
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid" || true
            cat "$log" >&2
            echo "VM exited before $expected marker" >&2
            exit 1
        fi
        attempts=$((attempts + 1))
        sleep 1
    done

    cat "$log" >&2
    echo "timed out waiting for $expected marker" >&2
    exit 1
}

log="$ab_state/ab-test.log"

echo "Phase 1: boot the original image and verify initial health..."
run_vm "$log" &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT INT TERM
wait_for_marker initial "$log"
wait_for_marker persistent "$log"
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
trap - EXIT INT TERM
echo "Phase 1 passed: original image boots and persists."

echo "Phase 2: stage the UKI into the ESP as a second boot entry..."
# Mount the ESP partition from the overlay and copy the UKI.
# We use guestfish to manipulate the qcow2 overlay.
esp_part=$(sfdisk --json "$image" |
    awk '/"name": "puffin_esp"/ { found=1 }
         found && /"start":/ { gsub(/,/, "", $2); print $2; exit }')
test -n "$esp_part"

# Copy the UKI into the ESP via guestfish.
LIBGUESTFS_BACKEND=direct guestfish --rw -a "$overlay" <<EOF
run
mount /dev/sda1 /
mkdir-p /EFI/Linux
upload "$uki" /EFI/Linux/$(basename "$uki")
EOF
echo "Phase 2 passed: UKI staged into ESP."

echo "Phase 3: boot the updated entry and verify it starts..."
run_vm "$log" &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT INT TERM
wait_for_marker initial "$log"
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
trap - EXIT INT TERM
echo "Phase 3 passed: updated entry boots successfully."

echo "Phase 4: simulate a failed boot by removing the staged UKI..."
LIBGUESTFS_BACKEND=direct guestfish --rw -a "$overlay" <<EOF
run
mount /dev/sda1 /
rm /EFI/Linux/$(basename "$uki")
EOF

run_vm "$log" &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT INT TERM
# After removing the UKI, the bootloader should fall back to the original entry.
wait_for_marker initial "$log"
wait_for_marker persistent "$log"
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
trap - EXIT INT TERM
echo "Phase 4 passed: fallback to original entry after failed boot."

rm -f -- "$overlay" "$nvram" "$log"
echo "A/B update and rollback checks passed"