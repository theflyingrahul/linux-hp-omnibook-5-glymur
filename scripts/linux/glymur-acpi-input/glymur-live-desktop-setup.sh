#!/usr/bin/env bash

# Interactive Ubuntu live desktop with internal input and Wi-Fi.
# Loads the hash-pinned ACPI GPIO and GENI I2C test modules (keyboard I2C1,
# touchpad I2C5, touchscreen I2C9; proven in the second input-test run), gives
# the ath12k QCC2072 its upstream firmware plus the private HP board data in
# the RAM root, blocks suspend/hibernate (untested), then starts the normal
# graphical session. If the kit carries them, it also binds the EC bus IC10
# through the QGP1 GPI DMA engine (glymur_gpi_dma.ko, glymur_geni_i2c_gsi.ko),
# which gives the ACPI thermal zones and other EC-backed AML their bus. It
# never writes internal storage and leaves the machine running. Only in workstation mode
# (persistent boot) does it write, and then only to the installer's casper-rw
# persistence (the first-boot repository unpack).
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

EXPECTED_KERNEL=7.0.0-30-generic
KIT=/cdrom/glymur-tools/acpi-input
LOG=/run/glymur-live-desktop.log
GPIO_SHA256=@GPIO_SHA256@
I2C_SHA256=@I2C_SHA256@
GPI_SHA256=@GPI_SHA256@
GSI_SHA256=@GSI_SHA256@
GED_SHA256=@GED_SHA256@
WIFI_BOARD_SHA256=@WIFI_BOARD_SHA256@
FW_SRC=/cdrom/glymur-tools/firmware/ath12k/QCC2072/hw1.0/firmware-2.bin
FW_SHA256=4c6a1be1f5bfad76319755ff76904abb21c4c7ece5293cc5f33a20b1f4c35254
FW_DEST=/lib/firmware/ath12k/QCC2072/hw1.0
BUSES="0xb80000,0xb90000,0xa80000"

say() {
    printf 'glymur-desktop: %s\n' "$*" | tee -a "$LOG" >/dev/console
}

hash_ok() {
    [ "$(sha256sum "$1" 2>/dev/null | cut -d ' ' -f 1)" = "$2" ]
}

start_desktop() {
    say "$1"
    systemctl start --no-block graphical.target
    exit 0
}

say 'Preparing internal keyboard, touchpad, touchscreen, and Wi-Fi.'
if [ "$(uname -r)" != "$EXPECTED_KERNEL" ]; then
    start_desktop "Unexpected kernel $(uname -r); starting the desktop without the modules."
fi

# Suspend and hibernate are untested with these modules; block them.
systemctl mask --runtime sleep.target suspend.target hibernate.target \
    hybrid-sleep.target suspend-then-hibernate.target >>"$LOG" 2>&1

if hash_ok "$KIT/glymur_acpi_gpio.ko" "$GPIO_SHA256" &&
    hash_ok "$KIT/glymur_geni_i2c.ko" "$I2C_SHA256"; then
    # GPIO 66 is the EC event interrupt (ECGE, PDC pin 768) and GPIO 92 the
    # lid (LIGE, pin 960); both reach _EVT through glymur_acpi_ged.ko.
    insmod "$KIT/glymur_acpi_gpio.ko" enable=1 pins=3,51,66,67,92 >>"$LOG" 2>&1
    say "GPIO module status $?."
    insmod "$KIT/glymur_geni_i2c.ko" allow="$BUSES" >>"$LOG" 2>&1
    say "I2C module status $?."
    modprobe i2c_hid_acpi >>"$LOG" 2>&1
    modprobe hid_multitouch >>"$LOG" 2>&1
else
    say 'Module hash mismatch; internal input stays disabled.'
fi

# EC bus: QGP1 (QCOM0F88:01) must be bound before anything else can claim its
# channels, then IC10 (QCOM0F10:04, QUP1 SE1) in GSI mode. Proven live on
# 2026-09-26 (docs/cpuidle-and-ec-bus-results-2026-09-26.md).
EC_GPI=/sys/bus/platform/devices/QCOM0F88:01
EC_DEV=/sys/bus/platform/devices/QCOM0F10:04
if [ "$GPI_SHA256" = none ]; then
    say 'EC bus modules not in this kit; IC10 left unbound.'
elif hash_ok "$KIT/glymur_gpi_dma.ko" "$GPI_SHA256" &&
    hash_ok "$KIT/glymur_geni_i2c_gsi.ko" "$GSI_SHA256" &&
    [ "$(cat "$EC_GPI/firmware_node/path" 2>/dev/null)" = '\_SB_.QGP1' ] &&
    [ "$(cat "$EC_DEV/firmware_node/path" 2>/dev/null)" = '\_SB_.IC10' ] &&
    [ ! -e "$EC_GPI/driver" ] && [ ! -e "$EC_DEV/driver" ]; then
    insmod "$KIT/glymur_gpi_dma.ko" allow=0xa04000 >>"$LOG" 2>&1
    say "EC GPI DMA module status $?."
    insmod "$KIT/glymur_geni_i2c_gsi.ko" allow=0xa84000 seid=1 >>"$LOG" 2>&1
    say "EC I2C module status $?."
else
    say 'EC bus prerequisites not met; IC10 left unbound.'
fi

# ACPI event devices ECGE (EC events) and LIGE (lid) use GpioInt, which the
# built-in acpi-ged driver rejects; glymur_acpi_ged.ko is evged.c with
# GpioInt support. Load it after the EC bus: ECGE's _EVT reads the EC.
if [ "$GED_SHA256" = none ]; then
    say 'GED module not in this kit; lid and EC events stay off.'
elif hash_ok "$KIT/glymur_acpi_ged.ko" "$GED_SHA256"; then
    insmod "$KIT/glymur_acpi_ged.ko" >>"$LOG" 2>&1
    say "GED (lid and EC events) module status $?."
else
    say 'GED module hash mismatch; lid and EC events stay off.'
fi

PCI=/sys/bus/pci/devices/0004:01:00.0
if [ "$WIFI_BOARD_SHA256" != none ] && hash_ok "$FW_SRC" "$FW_SHA256" &&
    hash_ok "$KIT/wifi/board-2.bin" "$WIFI_BOARD_SHA256" &&
    [ "$(cat "$PCI/subsystem_device" 2>/dev/null)" = 0x8ef3 ] &&
    ! compgen -G "$FW_DEST/firmware-2.bin*" >/dev/null &&
    ! compgen -G "$FW_DEST/board-2.bin*" >/dev/null; then
    mkdir -p "$FW_DEST" && cp "$FW_SRC" "$KIT/wifi/board-2.bin" "$FW_DEST/"
    if [ ! -L "$PCI/driver" ] && [ -d /sys/bus/pci/drivers/ath12k_wifi7_pci ]; then
        timeout 45s bash -c 'printf 0004:01:00.0 > /sys/bus/pci/drivers/ath12k_wifi7_pci/bind' \
            >>"$LOG" 2>&1
        say "Wi-Fi bind status $?."
    fi
else
    say 'Wi-Fi prerequisites not met; Wi-Fi left as is.'
fi

# Workstation mode (glymur.workstation=1, persistent boot only): on first boot,
# unpack the repository and its private .work evidence
# into the live user's persistent home. Never overwrites an existing checkout.
bootstrap_workstation() {
    local bundle=/cdrom/glymur-workstation/workstation-bundle.tar.gz
    local sums=/cdrom/glymur-workstation/SHA256SUMS
    local user home repo
    user="$(getent passwd 1000 | cut -d: -f1)"
    home="$(getent passwd 1000 | cut -d: -f6)"
    repo="$home/linux-hp-omnibook-5-glymur"
    if ! grep -qw persistent /proc/cmdline || ! findmnt -rn -S LABEL=casper-rw >/dev/null; then
        say 'Workstation: casper-rw persistence is not mounted; nothing unpacked.'
        return
    fi
    if [ -z "$user" ] || [ ! -d "$home" ]; then
        say 'Workstation: live user home not found; nothing unpacked.'
        return
    fi
    if [ -e "$repo" ]; then
        say "Workstation: $repo already exists; left unchanged."
        return
    fi
    if ! (cd /cdrom/glymur-workstation && sha256sum --quiet -c SHA256SUMS) >>"$LOG" 2>&1; then
        say "Workstation: bundle hash check failed ($sums); nothing unpacked."
        return
    fi
    tar -xzf "$bundle" -C "$home" >>"$LOG" 2>&1 &&
        chown -R "$user:$user" "$repo" >>"$LOG" 2>&1
    say "Workstation: unpacked the repository to $repo (status $?)."
    # The bundle is made on Windows, whose tar marks files executable.
    runuser -u "$user" -- git -C "$repo" config core.filemode false >>"$LOG" 2>&1
}

if grep -qw 'glymur.workstation=1' /proc/cmdline &&
    grep -qw persistent /proc/cmdline && findmnt -rn -S LABEL=casper-rw >/dev/null; then
    bootstrap_workstation
    # casper always boots /casper/vmlinuz from the FAT partition; a kernel
    # upgraded into persistence would leave /lib/modules out of step with it.
    dpkg-query -W -f '${Package}\n' 'linux-image-*' 'linux-modules-*' \
        'linux-generic*' 'linux-headers-generic*' 'linux-signed-*' 2>/dev/null |
        xargs -r apt-mark hold >>"$LOG" 2>&1
    say "Workstation: kernel packages held (status $?)."
fi

start_desktop 'Starting the desktop. Suspend is disabled; do not close the lid to sleep.'
