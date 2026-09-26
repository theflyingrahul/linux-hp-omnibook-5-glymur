# Whole-System Live Inventory

Use the existing Ubuntu ARM64 installer only as a diagnostic environment;
Fedora ARM64 remains the intended installed OS. Select the default-off
**Glymur whole-system inventory (RAM live)** GRUB entry with the installer
in the right USB-A port. Do not remove the installer. The entry requires a
successful `toram nopersistent` boot and checks the installer's FAT UUID and
USB serial before writing logs. Connect the charger before booting. It never
mounts the internal NVMe.

The collector uses a text progress screen on virtual terminal 6. It reports
the current capture, saved checkpoint, and countdown during waits. Graphical
services run in the background; the progress screen returns to the foreground
after they start. No keyboard input is required. The only optional action is
connecting a USB-C device when a port window appears. Keep the installer USB
connected until the machine powers off automatically. The entry uses Casper's
`noprompt` option so the live image does not ask for Enter during shutdown;
remove the installer only after power is off.

The collector first saves an `EARLY` snapshot under
`glymur-logs/system-inventory-*` on the installer. It then shows two optional
30-second USB-C windows: try a known-working USB-C device in the left port
nearest the display hinge, then in the other left port. Keep the installer in
USB-A. Each window records USB enumeration, kernel messages, Type-C roles,
and USB roles. If a port holds the charger, skip that port; do not disconnect power.
After the port windows it starts the live image's ordinary graphical services,
and saves a `GRAPHICAL_START` marker. After a two-minute wait it saves a
`LATE_CORE` marker with the kernel log, journal, and graphical service status.
It then captures device, driver, firmware, journal, service, and power state,
saves `LATE`, performs the Wi-Fi trial, saves `WIFI` and `COMPLETE`, and powers
off. A black screen during graphical startup is not a reason to force power
off; allow several minutes.

After the baseline capture, it also makes **one** QCC2072 Wi-Fi probe with
SHA-256-verified upstream `firmware-2.bin` and `board-2.bin`, copied only into
the live system's RAM-backed filesystem. It checks the HP's exact PCI IDs,
will not overwrite distribution firmware, and saves a separate `WIFI` marker.
The upstream board database does not visibly contain this HP subsystem ID,
so a successful radio is not expected; the result should identify the next
driver or board-data gap without another reboot. The original firmware files
and vendor notice are staged only on the installer USB, not in Git. They came
from the [upstream linux-firmware QCC2072 directory](https://gitlab.com/kernel-firmware/linux-firmware/-/tree/main/ath12k/QCC2072/hw1.0).

The capture covers DRM/GPU and Mesa probes, Wi-Fi firmware and network state,
Bluetooth, audio, battery/thermal/CPU power, USB-C, input, storage, and ACPI
driver binding. It does **not** install to the internal disk, inject a DTB,
force suspend, flash persistent firmware, or prove long-term stability. The
GRUB clock/power workarounds remain in effect, so suspend and normal
power-gating behavior require separate validation. Logs may contain device
identifiers and network metadata; keep them private and out of Git.

## Partial September 26 run

The first run saved `EARLY` and `PORTS` but was manually powered off within
five minutes of reaching the GUI, before `WIFI` or `COMPLETE` appeared. The
owner connected USB-C storage to both left ports during the respective
windows. The saved USB event monitor was empty, and the early, hinge-port, and
other-port kernel logs were identical. The storage did not visibly enumerate
in this run; the logs do not identify why. The early DRM device was
`simpledrm` on `simple-framebuffer.0`, with no native GPU render node shown.
The revised collector saves additional checkpoints around graphical startup
to make the next run easier to assess.

The subsequent run completed every checkpoint on September 26. See
`docs/system-inventory-results-2026-09-26.md` for the sanitized findings.
