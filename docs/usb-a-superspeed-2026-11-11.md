# USB-A SuperSpeed failures and a log sweep, November 11, 2026

The USB stick in the right-hand USB-A port has failed at SuperSpeed on two
boots. This note collects what the logs show, the likely cause (HP's PHY
tuning, which Linux never applied), what kernel `-23` changes, and how to
test it. The second half lists everything else unusual in the `-20` and
`-21` kernel logs.

## The two failures

| Boot | What happened |
| --- | --- |
| `-14`, 2026-10-17 (test device tree) | From the first kernel lines, `usb3-port1: Cannot enable` and `error -71` for about 13 minutes (141 lines saved). Then the stick came up on the port's high-speed bus (`usb 2-1`, 480 Mb/s) and stayed usable. SuperSpeed never came back that boot. |
| `-21`, 2026-11-11 14:39 (test device tree; the boot of the drain-cycle freeze) | In the first 15 seconds the stick enumerated at SuperSpeed six times. Each time it failed within 1 to 3 seconds of `usb-storage` starting: `Device not responding to setup address`, `device not accepting address N, error -71`, `reset SuperSpeed USB device`. After `Cannot enable` and `attempt power cycle` it never came back that boot, not even at high speed. This was 20 minutes before the first suspend. |

Every other boot with a kernel log has a clean link: three on `-18`, four
on `-20`, four on `-21`. The stick enumerated once, at SuperSpeed, with no
link errors. The `-20` boot's four `reset SuperSpeed` lines are the
ordinary reset-resume after suspend. That makes two failures in the 13 boots
from `-14` on whose USB-A enumeration is in `captures/`. Both were with the same stick
(SanDisk Ultra, `0781:558a`) in the same port.

## What the port is and what Linux does differently

The port is `usb_2` (`dwc3` at `0x0a000000`). SuperSpeed goes through
`usb_2_qmpphy`, the USB3/DP combo PHY at `0x088e1000`
(`qcom,glymur-qmp-usb3-dp-phy`). Its reference clock is
`tcsr_usb4_2_clkref_en` (`docs/usb-a-bringup-2026-09-29.md`).

**HP's PHY tuning.** HP's DSDT gives `\_SB.USB2` a `PHYC` method. It returns
register writes for the OS's USB driver to apply after the PHY's init
sequence:

| Address | Offset in lane A (`0x088e5000`) | Register | HP | Linux |
| --- | --- | --- | --- | --- |
| `0x088e5158` | `0x158` | `QSERDES_V8_LALB_RX_MODE_RATE_0_1_B1` | `0xa0` | `0xa2` |
| `0x088e5178` | `0x178` | `QSERDES_V8_LALB_RX_MODE_RATE2_B1` | `0x90` | `0x93` |

Lane A sits at `txa = 0x4000` in the driver's `qmp_combo_usb43dp_offsets_v8`.
A Type-A port without an orientation switch runs on lane A. Both registers
are receiver mode settings. Their meaning is not public, and neither is
which line rate each "rate" field covers. The `PHYC` packages of both USB-C
controllers (`URS0`, `URS1`, and their peripheral functions) are empty. So
HP tuned only this port's receiver, and only the lane it uses.

Linux has never written these values. `backports/0083` (Qualcomm's newer
hardware-guide table, since `-20`) changed `RATE2_B1` from `0xc4` to
`0x93`, closer to HP's `0x90`. `RATE_0_1_B1` stays at the reference
`0xa2`. The `-21` failure happened with `0083` in place.

The failure fits a marginal receiver. The link trains, the descriptors read
correctly, and then the first bulk transfers fail with `-71` (protocol
errors). Each retry trains again and fails again. On most boots the margin
is enough. This is the best-evidenced cause, but it is not proven: the
failure cannot be produced on demand.

**Other candidates, and why they come second.**

- **The QREF/REFGEN supplies of the PHY's reference clock.** Linux uses
  dummy regulators for them. The rails stay as the firmware left them, and
  they are on, because UEFI and GRUB read from this port on every boot. HP's
  PEP votes for `USB2` include L1F 0.904 V, L2F 0.88 V and L4F 1.2 V. These
  match the Mahua CRD's `tcsr` supplies (L1F_E1, L2F_E1, L4F_E1), but the
  votes do not say which PMIC instance each rail is on. Declaring them would
  be the first RPMh regulators in our tree, and the repo's rule asks for
  every rail to be evidenced first. Not changed.
- **The stick.** Only this one SuperSpeed device has been on this port. The
  test below should also run with a second USB 3 device if one is at hand.

## Kernel `-23`

- **`glymur-bringup/0006`:** an optional `qcom,usb3-lane-a-overrides`
  property on the combo PHY, given as `<offset value>` pairs in lane A, the
  same form as HP's `PHYC`. The pairs are written after the lane tables on
  every power-on, including resume. The first write is logged with a read-back:
  `USB3 lane A 0x158 = 0xa0 (read back 0xa0)`. Without the property nothing
  changes. This is bring-up code: a register list is not an upstream
  binding. Upstream, the values belong in the PHY's tables or in a described
  tuning property, like `qcom,hs-drv-slope` on the HS PHY.
- **The test device tree sets HP's two pairs. The daily tree does not.** So
  the same kernel gives an A/B pair: "test device tree" has HP's values,
  "Ubuntu on SSD" has Linux's.
- **The boot report** (`glymur-boot-report.sh`) has a new section, "USB-A
  (a000000.usb) link", on every boot. It shows whether the overrides are in
  the device tree, the kernel's read-back, where the stick is and at what
  speed, and a count of link errors. A failure like the two above shows
  there without anyone running a test.
- **`check-usb.sh --ss-stress [cycles]`** (default 20) asks before it
  unmounts the stick. It never writes to the stick. It does three things:
    - reads 1 GiB with `O_DIRECT`;
    - alternates a USB device reset (`USBDEVFS_RESET`) with powering the
      SuperSpeed port off and on, which makes the link train again;
    - reads 64 MiB after each cycle.

  For each cycle it records whether the stick came back at SuperSpeed, at
  high speed, or not at all, and the link errors. Coming back at high speed
  after the port power cycle may be normal device behaviour, so compare
  the two device trees rather than read the counts on their own.

## Everything else in the `-20` and `-21` logs

The sweep covered all nine kernel journals of `-20` and `-21`: warnings,
errors, timeouts, firmware failures, deduplicated.

**New, for the suspend work.** On every suspend with Wi-Fi up, PCIe 4 (the
Wi-Fi, `1bf0000.pcie`) logs `Timeout waiting for L2 entry! LTSSM: 0x11`.
The QCC2072 does not answer `PME_Turn_Off`. The link is still in L0 when
the controller powers it down, which the driver allows after 10 ms. PCIe 5
(NVMe) enters L2 cleanly. This is not a hang, and resume worked each time.
Whether the Wi-Fi's suspend state affects the SoC's sleep depth is one more
item for `docs/suspend-2026-11-10.md`. Not changed in `-23`.

**Known and tracked:**

| Message | Where | Status |
| --- | --- | --- |
| `video_cc_mvs0_gdsc status stuck at 'off'` (a `WARNING`, taints the kernel), Iris `power on failed`, `failed to suspend` | the `-test-av` tree and the video trials only | the Iris trials |
| `rtc-glink … all time sources failed`, `hctosys: unable to read` | every boot | the firmware's RTC service; `check-rtc.sh` |
| `GPI transfer failed`, `cannot tell the EC about resume` | once each in the two freeze boots | the EC's standby exit on resume (GPI DMA); it is retried |
| `nvme … failed to set target rate Gen5 (-11)` | `-20`, `-21` | `-22` builds without the feature |
| SDCA `SimpleJack` read errors | `-20` only | fixed by `upstream/qcom-next/0010` in `-21` (none in `-21`'s logs) |

**Expected or harmless:**
- `gen80100_sqe.fw` fails to load before the root filesystem, then "loaded
  from new location" the moment it is mounted. The GPU works.
- `qca/ornbcscal11.b17` is missing; the driver falls back to `.bin`
  (`docs/device-tree-first-boot-2026-09-28.md`).
- `pmic_glink: Failed to create device link` with the USB-C controllers
  and PHYs. USB-C works.
- `aux_bridge … failed to acquire drm_bridge`, once per boot (DisplayPort
  is off).
- Firmware notices: `psci: failed to set PC mode`, SCMI fast-channel and
  protocol-version notices, `remoteproc … shutdown_state`, `qcomtee`.
- Duplicate ath12k debugfs entries.
- AppArmor's `lsusb` profile denying `/sys/devices/platform/…/uevent` to
  `lsusb` run as the user.

**Housekeeping:**
- The stick's FAT reports "Volume was not properly unmounted" on almost
  every boot. GNOME mounts it read-write, and several boots ended in forced
  power-offs. The next staging checks the volume first, as the staging
  rules ask. Ejecting it in Files before a reboot avoids the dirty flag.
- systemd-journald renames a journal after each forced power-off. This is
  expected.

**Privacy.** The committed captures still carried two identifiers:
- the owner's login name in `/run/media/<name>` and `/home/<name>` paths:
  25 capture files, two docs, and one script default;
- the camera's serial-like USB manufacturer string: 15 files.

Both are now replaced in the working tree with `user` and `<id>`.
`sanitize-capture.sh`, `check-usb.sh` and the boot report redact them from
now on. The repository history still holds the old text.
