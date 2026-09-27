# First Boot of the qcom-next Kernel on the SSD Install: September 27, 2026

The staged install from `docs/qcom-next-ssd-install-2026-09-27.md` was booted
for the first time: `7.3.0-rc2-glymur` from `/dev/nvme0n1p4` (`glymur-root`,
SSD partition 5, ext4), via the USB's "Ubuntu on SSD: qcom-next
7.3.0-rc2-glymur" GRUB entry. Evidence below is from
`journalctl -k -b` and live inspection on the running system (boot ID
`d31ecbc8`, `/var/log/glymur/boot-20260727T204515-d31ecbc8.txt` — the July 27
date is the known RTC issue, not a stale boot; `/proc/uptime` confirms this
was a fresh boot). No root was needed except where noted.

## Working, same as the 2026-09-26 stock-Ubuntu results, now confirmed on the boot kernel

- **Input**, through the in-kernel `geni_i2c` and `glymur_acpi_gpio` paths
  driven entirely by the board command line (no out-of-tree modules, as
  intended for this kernel): keyboard (`QTEC0001`), touchpad and its
  consumer-control device (`ELAN0189`), touchscreen (`ELAN2513`), all bound
  cleanly with PDC IRQ routing (pins 3, 51, 66, 67, 92 → GPIOs 3, 51, 66, 67,
  92). One warning: `i2c_hid_acpi ELAN2513:00: IRQ triggered but there's no
  data`, once at boot; touch itself was not exercised interactively this run.
- **EC bus (IC10, `QCOM0F10:04`)**: bound via `geni_i2c`, thermal zones
  `\_SB_.TZ31`–`TZ34` register and read real temperatures, `acpi_fan`
  (`PNP0C0B`) reads live RPM. See the fan/thermal comparison below.
- **CPU idle**: both `LPI-0`/`LPI-1` states are in active use
  (`cpuidle/state*/usage` incrementing under normal desktop load).
- **Lid**: `/proc/acpi/button/lid/*/state` reads `open` correctly.

## New: full Wi-Fi association (beyond the previous scanning-only result)

`wlo1` associated and passed real traffic: SSID `rosara`, 6 GHz band (freq
6135), HE (Wi-Fi 6E), 160 MHz, 2 spatial streams, -44 dBm, DHCP lease
obtained, hundreds of MB transferred over the session. This is a step beyond
the 2026-09-26 result, which only confirmed scanning. One boot-time warning
did not block it: `ath12k_wifi7_pci 0004:01:00.0: failed to get ACPI BDF EXT:
-2` — the board-ID lookup failed but firmware still associated, presumably on
a fallback board file. Worth understanding before relying on this path,
since the "wrong" board data could mean suboptimal RF calibration rather than
the HP-specific `board-2.bin` payload from `ath12k-board-add.py`.

## Still absent, as documented

- USB-C (`USBC000` `_STA` still 0), the native GPU (`card0` is still
  `simple-framebuffer`, no render node; `\_SB.GPU0._CLS` warning persists),
  Bluetooth (protocol stack loads, no controller), audio, battery/AC/RTC
  (PMIC GLink), TPM (`/dev/tpm*` absent), CPU frequency scaling (no `_CPC`
  table found).
- Suspend remains masked; not tested.

## New findings

**RTC error storm from chrony's polling of `acpi-tad`.** `chrony` (the only
time-sync service on this install; no `systemd-timesyncd`) repeatedly tries
to read/write `/dev/rtc0` (`acpi-tad` → `\_SB.PRTC._GRT`/`._SRT`), which
always fails immediately because `\_SB.PMGK`'s `GenericSerialBus` region
(`ROP1`, PMIC GLink) has no handler. The retry has no backoff: over a 14
minute uptime, `journalctl -k -b` already had roughly 260,000 matching
lines (`ACPI Error: ... GenericSerialBus ... has no handler`, `Aborting
method \_SB.PRTC._SRT/._GRT`, `Result stack is empty!`), several hundred
per second, sustained. This was anticipated qualitatively in
`qcom-next-ssd-install-2026-09-27.md` ("chrony sets the time over Wi-Fi")
but not the busy-loop rate. It does not appear to peg a CPU core
(`mpstat` showed no core pinned, no runaway process visible in `ps`), so
the likely cost is journal/disk I/O and log noise burying real
diagnostics, not a functional hang. **Not fixed here** — the real fix is
either the PMIC GLink RTC path landing, or (as a local workaround, not yet
applied) disabling chrony's RTC sync/measurement directive on this install
until then.

**`arm-smmu-v3.2` event/error IRQs failed to enable at boot**:
`genirq: Setting trigger mode 1 for irq 152/153 failed
(gic_set_type+0x0/0x220)`, so `arm-smmu-v3.2.auto` lost its `evtq` and
`gerror` interrupt handlers. This appears to be a diagnostics-only gap:
NVMe (root filesystem, PCI segment 5) and Wi-Fi (PCI segment 4) both work
normally, including NVMe writes throughout this session and the Wi-Fi
throughput above, so stage-1/stage-2 translation itself is unaffected. Two
other `arm-smmu` (v2) instances (`.0`, `.1`) probed without this problem.
Not yet root-caused; likely a GIC trigger-type mismatch for this specific
SMMUv3 instance's ACPI IORT entry.

**A `do_idle` WARN at boot** (`sched/idle.c:269`, CPU0, `swapper/0/0`) —
seen once, at boot, with a clean call trace (no oops). Not seen again
during the session. Not yet correlated with a specific cause.

## Fan/thermal profile (qcom-next boot kernel, on battery)

See the updated comparison in `docs/fan-thermal-windows-2026-09-27.md`.
Raw data: `.work/linux-fan-profile-20260927T141943.tsv` (private).

## Next

- Investigate the chrony/RTC error-storm workaround (disable RTC
  sync/measurement in chrony's config on this install) so future journals
  stay readable; confirm with the owner before changing a system service.
- Root-cause the `arm-smmu-v3.2` IRQ trigger-type failure via its IORT
  entry; low priority since translation works today.
- Confirm the `ath12k` ACPI BDF failure doesn't mean degraded RF
  calibration; compare against the `board-2.bin`/`ath12k-board-add.py`
  path from `docs/status.md`.
- Interactively test touch (the one `i2c_hid_acpi` IRQ-without-data
  warning), keyboard, and touchpad on this kernel, not just enumeration.
- Everything already known-missing (USB-C, GPU, Bluetooth, audio, battery,
  TPM, CPU DVFS, suspend) still needs the device-tree path; unchanged by
  this boot.
