# QCOM0F10 First Controller Inspection

The September 25 Ubuntu live capture ran `7.0.0-30-generic` on this HP.
`scripts/linux/qcom0f10-inspect/` contains an out-of-tree module compiled
against the matching Ubuntu ARM64 headers, plus a GRUB entry for a focused
boot. The module is disabled by default. With `inspect=1`, it accepts only
`QCOM0F10` devices at the HP `I2C1` (`0x00B80000`) and `I2C5`
(`0x00B90000`) MMIO windows, each `0x4000` bytes. It reads the firmware
protocol, FIFO-disable bit, and master SE clock configuration, then returns
without binding a driver or registering an I²C adapter. It makes no
register writes or bus transfers. An MMIO read can still fault or hang if
firmware has left the engine unpowered.

The module was built in the private WSL directory
`/home/login/glymur-build/.work/qcom0f10-inspect/` with:

```bash
make -C /usr/src/linux-headers-7.0.0-30-generic \
    M=/home/login/glymur-build/.work/qcom0f10-inspect modules
```

The resulting `qcom0f10_inspect.ko` has AArch64 ELF format, no module
dependencies, and vermagic `7.0.0-30-generic SMP preempt mod_unload
modversions aarch64`. Its SHA-256 is
`4aadcd1896e02c54164702152ff789f646ab75b75a323996d2676797115d2adf`.
The focused collector checks both the running kernel version and this hash
before loading the module.
The module, collector, and GRUB snippet are also copied to the ignored
`.work/qcom0f10-inspect-kit/` directory. On September 25, the module and
collector were staged on the verified Ubuntu 26.04 ARM64 installer USB under
`/glymur-tools/`; their USB copies match the recorded hashes. The original
`/boot/grub/grub.cfg` was preserved as
`/boot/grub/grub.cfg.before-qcom0f10-20260925` before appending one menu entry.
The normal "Try or Install Ubuntu" entry remains first and is unchanged.
Windows reported the FAT volume's dirty flag, but a read-only `chkdsk E:` scan
found no file or folder errors. Eject the USB safely before the boot test;
do not unplug it while Windows is still writing.

The test boot used the right USB-A port and the separate
"Glymur QCOM0F10 inspection (Ubuntu live)" GRUB entry. No internal
installation or DTB replacement was involved. The collector checked the
exact `7.0.0-30-generic` kernel and module SHA-256 before `insmod`.
The collector records a synced `before-insmod` marker, loads the module,
then saves the kernel log under `/glymur-logs/qcom0f10-*/` on the USB and
powers off. After returning to Windows, inspect `progress.log`, `insmod.txt`,
and `dmesg-after.txt` in the newest such directory. If the module load stalls,
the marker should remain on the USB; photograph the screen and hold the power
button to shut down only if normal shutdown does not occur.

## September 25 result

The collector completed with `insmod` status 0 and saved
`/glymur-logs/qcom0f10-20260727T204532Z/` on the USB. The laptop's clock
reported July 27; use the September 25 collection date for provenance. A
hash-verified private copy is in `.work/qcom0f10-inspection-20260925/`.

| ACPI device | Firmware revision | Protocol | FIFO disabled | Master SE clock config |
|---|---:|---|---:|---:|
| `QCOM0F10:00` (`I2C1`) | `0x00000304` | I²C | 0 | `0x00000021` (clock enable=1) |
| `QCOM0F10:01` (`I2C5`) | `0x00000304` | I²C | 0 | `0x00000021` (clock enable=1) |

These are register observations at probe time, not proof that the full clock
tree, `PEP0` power transitions, interrupts, or bus transfers work. The module
returned `-ENODEV` from each probe, so no I²C adapter was registered. The
out-of-tree unsigned module tainted the live kernel as expected. The boot log
also reports that the FAT USB volume was not properly unmounted; retain the
private copy before any filesystem repair or further boot experiment.

## Next diagnostic gate

The observed clock register `0x21` has divider field 2. This matches the
divider in the HP `CLKD` 400-kHz row, but the effective bus rate cannot be
inferred without the clock source and SCL counters. The stock Qualcomm driver
would write clock and SCL registers, initialize GENI, request an IRQ, and
register an adapter; adding `QCOM0F10` to its match table is not a bounded
test. Adapter registration can trigger ACPI client activity immediately.

An independent default-off follow-up module in
`scripts/linux/qcom0f10-snapshot/` reads clock selection, SCL counters,
status, line state, IRQ status, DMA mode, and FIFO parameters on the same two
exact MMIO windows. It has no register writes, I²C commands, or adapter.
It built against the matching Ubuntu headers and passed `checkpatch.pl` with
zero warnings. Its AArch64 module has matching `7.0.0-30-generic` vermagic,
no dependencies, and SHA-256
`c14606966ccf5c0cb94d3235756b2c15881752ae48559bb58285a9f9175b8106`.
The module, a kernel/hash-checking collector, and an optional GRUB entry are
packaged privately in `.work/qcom0f10-snapshot-kit/`. The collector passed
`bash -n`; the copies match the source hashes. On September 25, the module
and collector were copied to `/glymur-tools/` on the verified installer USB.
The then-current GRUB file was backed up as
`/boot/grub/grub.cfg.before-snapshot-20260925` before appending the optional
"Glymur QCOM0F10 timing snapshot (Ubuntu live)" entry. The existing entries,
including the default normal Ubuntu boot, remain unchanged. The USB copies,
collector hash pin, and GRUB prefix/snippet were verified after staging.
The second module was run from the right USB-A port on September 25. The FAT
volume still had a dirty flag despite a read-only `chkdsk E:` scan finding no
file or folder errors; the collector saved its result and a hash-verified
private copy is in `.work/qcom0f10-snapshot-20260925/`.

### Timing snapshot result

The collector completed with `insmod` status 0. Both devices reported the
same clock and SCL state:

| Device | Clock config | Clock select | SCL counters | GENI status | I/O state | IRQ status | DMA mode | TX HW parameter |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `I2C1` | `0x21` | `0` | `0x00503018` | `0` | `0x07` | `0x80` | `0` | `0x202029e8` |
| `I2C5` | `0x21` | `0` | `0x00503018` | `0` | `0x07` | `0x80` | `0` | `0x20202868` |

The SCL register decodes to high=5, low=12, cycle=24; the clock divider is
2. These four values exactly match the HP `CLKD` row labeled 400 kHz. If the
SE input clock is the 19.2 MHz listed by `PEP0.BSRC`, the driver's nominal
cycle formula gives 19.2 MHz / (2 × 24) = 400 kHz. This is a conditional
calculation, **not a measured SCL rate** or proof that power sequencing works.
Status 0 indicates no active GENI command at the snapshot. DMA mode 0 is
consistent with FIFO mode; the IRQ status `0x80` was only read, not cleared.
The captured kernel command line included `clk_ignore_unused
pd_ignore_unused`; this deliberately preserves otherwise-unused resources
and cannot establish whether a normal boot would keep I2C5 powered.
*(Correction 2026-09-26: no Linux clock, RPMh, or power-domain provider binds
in this ACPI boot, so those arguments were no-ops and firmware clock state
persists regardless. See `docs/repository-audit-2026-09-26.md`.)*

Qualcomm's pinned Linux driver uses `(div, high, low, cycle) = (2, 5, 11,
22)` for its own 19.2-MHz 400-kHz profile. If adapted to bind this ACPI
device, its transfer path would overwrite the HP's observed `(2, 5, 12, 24)`
timing. Preserve the HP values for any proposed ACPI path until the clock
source and device requirements are validated; an ID-only match remains unsafe.

The next step is to design a single-device, bounded FIFO transaction offline,
including exact target address, expected reply, stale-IRQ handling, timeout,
abort/recovery, and a power-state failure path. The ACPI-described touchpad
`TCPD` is a candidate on `I2C5` at 7-bit address `0x15`; its HID-I²C `_DSM`
returns descriptor register `0x0001`. That is static firmware description,
not proof that the device is powered or will respond. A future test must
target only that address, retain the observed HP timing, cap transfer size
and duration, and leave adapter/client auto-enumeration disabled. It must
define how to handle the pre-existing IRQ status `0x80` and how to abort a
stuck command before any hardware run. Do not run `i2cdetect` or scan other
addresses. Do not infer keyboard or touchpad support from register reads,
and do not boot the unfinished kernel RFC patches or reference CRD DTB.
The exact transaction and no-go gates are in
`docs/i2c-fifo-probe-design.md`.
