#!/usr/bin/env bash
set -u

# Live (no reboot) EC bus test on the Glymur workstation boot. Run it once
# per boot, before anything else touches QGP1.
# Usage: sudo glymur-ec-gsi-live-test.sh <module-dir> <log-root> [--transfer]
#
# Binds the QGP1 GPI DMA engine (glymur_gpi_dma.ko) and then IC10, the EC's
# GSI-mode I2C engine (glymur_geni_i2c_gsi.ko). Linux's ACPI I2C OpRegion
# handler then runs IC10._REG, which only sets AVBL. With --transfer it also
# reads one byte from EC register 0xB2 at 0x76, the same access the lid
# _EVT handlers make through \_SB.IC10.CMB2. Neither module can be unloaded;
# a failure that wedges the bus needs a reboot.

MODDIR="${1:?usage: glymur-ec-gsi-live-test.sh <module-dir> <log-root> [--transfer]}"
LOGROOT="${2:?usage: glymur-ec-gsi-live-test.sh <module-dir> <log-root> [--transfer]}"
TRANSFER="${3:-}"
KREL=7.0.0-30-generic
GPI_DEV=QCOM0F88:01
EC_DEV=QCOM0F10:04
LOG="$LOGROOT/ec-gsi-live-$(date -u +%Y%m%dT%H%M%SZ)"

say() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$LOG/progress.log"; }
run() { local out="$1"; shift; say "run $out: $*"; "$@" >"$LOG/$out" 2>&1; say "status $out=$?"; }
tainted_die() { [ $(( $(cat /proc/sys/kernel/tainted) & 128 )) -ne 0 ]; }
snapshot() {
    local tag="$1"
    dmesg >"$LOG/$tag-dmesg.txt" 2>&1
    ls -l /sys/bus/i2c/devices/ >"$LOG/$tag-i2c.txt" 2>&1
    for d in /sys/bus/platform/devices/"$GPI_DEV" /sys/bus/platform/devices/"$EC_DEV"; do
        printf '%s driver=%s\n' "$d" "$(basename "$(readlink "$d/driver" 2>/dev/null)" 2>/dev/null)"
    done >"$LOG/$tag-binding.txt"
    grep -E 'gpi|glymur|GIC' /proc/interrupts >"$LOG/$tag-interrupts.txt" 2>&1
    cat /proc/acpi/button/lid/*/state >"$LOG/$tag-lid.txt" 2>&1
    cat /proc/sys/kernel/tainted >"$LOG/$tag-tainted.txt"
}
stop_if_oops() {
    if tainted_die || dmesg | grep -qE 'Internal error|Unable to handle kernel|BUG:|Oops'; then
        say "KERNEL OOPS after $1. Stopping. Save your work; a reboot is needed."
        snapshot oops
        exit 2
    fi
}

mkdir -p "$LOG" || exit 1
say "log directory $LOG"

# Stage 0: preconditions.
[ "$(id -u)" -eq 0 ] || { say "must run as root"; exit 1; }
[ "$(uname -r)" = "$KREL" ] || { say "kernel $(uname -r) is not $KREL"; exit 1; }
grep -qw glymur.workstation=1 /proc/cmdline || { say "not the workstation boot"; exit 1; }
tainted_die && { say "kernel already oopsed this boot; refusing"; exit 1; }
for m in glymur_gpi_dma glymur_geni_i2c_gsi; do
    [ -f "$MODDIR/$m.ko" ] || { say "missing $MODDIR/$m.ko"; exit 1; }
    [ "$(modinfo -F vermagic "$MODDIR/$m.ko" | cut -d' ' -f1)" = "$KREL" ] ||
        { say "$m.ko vermagic mismatch"; exit 1; }
done
sha256sum "$MODDIR"/*.ko | tee "$LOG/modules.sha256"
[ -e "/sys/bus/platform/devices/$GPI_DEV/driver" ] && { say "$GPI_DEV already bound"; exit 1; }
[ -e "/sys/bus/platform/devices/$EC_DEV/driver" ] && { say "$EC_DEV already bound"; exit 1; }
[ "$(cat /sys/bus/platform/devices/$GPI_DEV/firmware_node/path)" = '\_SB_.QGP1' ] ||
    { say "$GPI_DEV is not QGP1"; exit 1; }
[ "$(cat /sys/bus/platform/devices/$EC_DEV/firmware_node/path)" = '\_SB_.IC10' ] ||
    { say "$EC_DEV is not IC10"; exit 1; }
snapshot before
dmesg -n 1 2>/dev/null
say "stage 0 complete"

# Stage 1: bind QGP1. The driver only maps registers here; channels are
# allocated when the I2C driver requests them.
run insmod-gpi.txt insmod "$MODDIR/glymur_gpi_dma.ko" allow=0xa04000
sleep 1
stop_if_oops "GPI insmod"
snapshot gpi
readlink "/sys/bus/platform/devices/$GPI_DEV/driver" >/dev/null ||
    { say "QGP1 did not bind; see gpi-dmesg.txt"; exit 3; }
# No channel may be in use before IC10 asks for one. A public-channel client
# such as async_tx would start them with seid 0 and poison every GPII.
for c in /sys/class/dma/dma*chan*; do
    [ "$(basename "$(readlink -f "$c/device")")" = "$GPI_DEV" ] || continue
    [ "$(cat "$c/in_use")" = 0 ] || { say "$(basename "$c") was taken at registration; stopping"; exit 3; }
done
say "stage 1 complete: QGP1 bound"

# Stage 2: bind IC10 in GSI mode. This allocates the GPII channels, registers
# the adapter and installs the ACPI GenericSerialBus handler (IC10._REG).
run insmod-gsi.txt insmod "$MODDIR/glymur_geni_i2c_gsi.ko" allow=0xa84000 seid=1
sleep 2
stop_if_oops "GSI I2C insmod"
snapshot gsi
readlink "/sys/bus/platform/devices/$EC_DEV/driver" >/dev/null ||
    { say "IC10 did not bind; see gsi-dmesg.txt"; exit 3; }
ADAP=$(basename "$(ls -d /sys/bus/platform/devices/$EC_DEV/i2c-* 2>/dev/null | head -1)")
say "stage 2 complete: IC10 bound as ${ADAP:-<no adapter>}"

# Stage 3 (optional): one EC read, the same access as the lid _EVT handler.
if [ "$TRANSFER" = --transfer ] && [ -n "$ADAP" ]; then
    modprobe i2c-dev
    run transfer.txt timeout 10s i2ctransfer -y "${ADAP#i2c-}" w1@0x76 0xb2 r1@0x76
    sleep 1
    stop_if_oops "EC read"
    snapshot transfer
    say "stage 3 complete: $(cat "$LOG/transfer.txt")"
fi

say "COMPLETE"
touch "$LOG/COMPLETE"
