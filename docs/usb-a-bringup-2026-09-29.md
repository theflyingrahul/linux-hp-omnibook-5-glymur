# USB-A on Device-Tree Boots, September 29, 2026

Device-tree boots have no USB, so every install from the USB stick needs a
reboot into an ACPI entry and back. This stages the right-hand USB-A
port, which holds the stick, as a device-tree-only test on the installed
kernel `-5`.

## Which controller: HP's ACPI tables against `glymur.dtsi`

**ACPI boots.** The kernel log of every ACPI boot shows two xHCI
controllers:

- `QCOM0FEF` at `0x0a200000` has bus 1 with one high-speed device.
- `QCOM0F9A` at `0x0a000000` has buses 2 and 3; the USB stick enumerates
  on bus 3 at 5 Gb/s.

**HP DSDT, `\_SB.USB2` (`QCOM0F9A`).**

- `_CRS` is memory `0x0a000000` plus GIC interrupts 903 and 402, which are
  SPI 871 and SPI 370. Those are `usb_2`'s `dwc_usb3` and `pwr_event` in
  `glymur.dtsi`.
- `RHUB.PRT0` and `PRT1` return `\_SB.UUPC.UPC3` = `{1, 0x03, 0, 0}`:
  connectable, **USB 3 Standard-A**.
- `_DEP` includes `\_SB.UCS0`, and `PRT1` names a `usb4-host-interface`.
  Neither matters for a USB-A host port.
- `PHYC` returns two register writes into the USB3 PHY's range:
  `0x088E5158 = 0xA0` and `0x088E5178 = 0x90`. These are HP's tuning,
  which Windows applies and Linux does not.

**HP PEP, `\_SB.USB2`, D0.**

- **Footswitches:** `gcc_usb30_tert_gdsc` and `gcc_usb_2_phy_gdsc`. These
  are `usb_2`'s and `usb_2_qmpphy`'s power domains.
- **Clocks:** the `gcc_usb30_tert_*` and `gcc_usb3_tert_phy_*` clocks,
  `tcsr_usb4_2_clkref_en` (`usb_2_qmpphy` "ref") and
  `tcsr_usb2_4_clkref_en` (`usb_2_hsphy` "ref"). This is exactly the clock
  set of `usb_2` and its PHYs in `glymur.dtsi`.
- **Rails:**

  | Rail | Voltage |
  |---|---|
  | S7F | 1.2 V |
  | L15B | 1.8 V |
  | L4C | 0.912 V |
  | L7B | 3.072 V |
  | L4F | 1.2 V |
  | L1C | 0.912 V |
  | L2F | 0.88 V |
  | L1F | 0.904 V |

- **No GPIO and no repeater** in the PEP entry, and no eUSB2 repeater or
  redriver anywhere in the DSDT.

So the port is `usb_2` (`dwc3` @ `0x0a000000`), with PHYs `usb_2_hsphy`
(M31 eUSB2 @ `0x088e0000`) and `usb_2_qmpphy` (QMP USB3/DP @ `0x088e1000`).

The camera controller `QCOM0FEF` is `usb_hs` @ `0x0a200000`. This DSDT
has no PEP entry for it, so it is not part of this step.

## The test device tree

`dts/qcom/mahua-hp-omnibook-5-bf1xxx-usb.dts` is the GPU test device tree
plus:

- `&usb_2`: `dr_mode = "host"`, `usb-role-switch` removed, `okay`;
- `&usb_2_hsphy` and `&usb_2_qmpphy`: `okay`.

The decompiled DTB differs from the GPU test DTB only in those lines and
the model. It passes the GPIO allow-list check (no pins are added).

Deliberately not declared yet:

- **Supplies.** There are no RPMh regulators in this device tree, the same
  as for the working eDP PHY. The rails stay as firmware left them, and
  they are on, because GRUB boots from this port. The PHY drivers take
  dummy regulators. The PEP rails above are the evidence for declaring
  them later.
- **The eUSB2 repeater.** HP's tables do not describe one, UEFI sets it
  up, and `phy-qcom-m31-eusb2` treats the repeater as optional
  (`devm_phy_optional_get`).
- **HP's USB3 tuning (`PHYC`).** SuperSpeed may train worse without it;
  high speed does not depend on it.

`-5` already has every driver needed, as modules:

- `USB_DWC3_QCOM`, `USB_XHCI_PLATFORM`;
- `PHY_QCOM_QMP_COMBO`, `PHY_QCOM_M31_EUSB` (the M31 eUSB2 PHY);
- `USB_STORAGE`, `USB_UAS`.

No new kernel is needed.

## Staged

- **DTB:** `glymur-tools/usb-test/mahua-hp-omnibook-5-bf1xxx-usb.dtb` on
  the USB (SHA-256 `dbb6b25d…a866`, with its own `SHA256SUMS`), built with
  `glymur-lab/build-test-dtb.sh` against the `-5` build.
- **GRUB entry "Ubuntu on SSD: device tree (GPU and USB-A test)":** the
  installed `-5` kernel with this DTB. It prefers a copy in
  `/boot/glymur-dtb` once a kernel package ships one. `grub.cfg` backup:
  `.work/grub-before-usbtest-20260929.cfg`.
- **`check-usb.sh`** on the USB. It records the controller and PHY
  messages, bound drivers, USB topology with link speeds, and block
  devices. `--previous` reads the last boot's log instead.
- **`install-from-usb.sh`** now also runs from this boot once the port
  works, so installing no longer needs an ACPI reboot.

## Test

1. Boot "device tree (GPU and USB-A test)".
2. If the stick appears in the file manager, open a terminal and run:
    - `sudo bash "/media/$USER/UBUNTU 26_0/glymur-tools/kernels/check-usb.sh"`
    - `bash "/media/$USER/UBUNTU 26_0/glymur-tools/kernels/install-from-usb.sh"`

   The second one installs the Mesa build, the cpufreq service and the
   test tools without a reboot into ACPI.
3. If the stick does not appear, the desktop is otherwise the GPU test
   boot. From any later boot that can see the stick, run
   `sudo bash .../check-usb.sh --previous`.

Possible outcomes, and what each means:

| Result | Meaning |
|---|---|
| Stick at 5000 Mb/s | Port works as on ACPI |
| Stick at 480 Mb/s only | High speed works; SuperSpeed needs HP's `PHYC` tuning or a lane/orientation setting on the combo PHY |
| No device, PHY or controller errors in the log | Evidence for the next step: supplies, repeater, or the PHY reset sequence |

## Live test, September 29: USB-A works; eDP failed on the very next reboot

Booted twice back-to-back, same DTB, same kernel (`-5`), no other change.

**First boot (~21:33, `usb-test-20260929T213337.txt`, `boot-20260929T213352-723bbc98.txt`): everything worked.**
`qcom-m31eusb2-phy` and `qcom-qmp-combo-phy` both bind at `0x088e0000`/
`0x088e1000`, `dwc3_qcom`/`xhci_plat_hcd` come up, and the boot USB stick
itself enumerates through the new internal controller:

```
2-1          speed=5000   SanDisk Ultra
usb2         speed=10000  ... xHCI Host Controller
```

`lsusb -t` shows it as `Bus 002.Port 001: ... Driver=usb-storage, 5000M` —
the right-hand USB-A port works as a host port at full SuperSpeed, with no
supplies, repeater or `PHYC` tuning declared. This is the first working
USB on any device-tree boot. The same boot's saved connector state also
shows `card1-eDP-1 status=connected enabled=enabled mode=1920x1200` — GPU,
cpufreq, eDP and USB-A all live together on one boot for the first time.

**Second boot (~21:35, two minutes later, `journalctl -b` on this
machine): blank screen, keyboard responsive.** Identical DTB and kernel.
This time:

```
[    2.407006] [drm:msm_dp_ctrl_link_train_1_2 [msm]] *ERROR* link training #2 on phy 0 failed. ret=-110
[    2.407035] [drm:msm_dp_ctrl_setup_main_link [msm]] *ERROR* link training on sink failed. ret=-110
```

This is **not** the old `phy poweron failed --> -110` bug the v8 backport
fixed (`docs/edp-phy-backport-2026-09-29.md`) — the PHY itself came up
fine this time; link training got underway and then timed out partway
through. `gdm`/`gnome-shell` started normally afterwards (`Added device
'/dev/dri/card1' (msm)`, `GPU /dev/dri/card1 selected primary from
builtin panel presence`) — the whole session came up, including a working
console/keyboard, exactly as the owner reported. There is simply no
connector to show it on, because training never completed. `check-usb.sh`
was not run this boot, so whether USB-A itself still worked is unconfirmed
for this attempt.

**Reading this:** the same DTB link-trained cleanly once and failed two
minutes later on an immediate reboot, with a different failure signature
than the pre-backport bug. That is evidence against "the USB-A addition
broke eDP" as a deterministic DT-level regression — a real regression
would be expected to fail the same way every time. It looks more like the
same class of marginal, boot-to-boot power/reference-clock sequencing
flakiness already seen in the USB-C charging investigation
(`docs/usb-c-charging-2026-09-29.md`): the eDP PHY and the new
`usb_2_qmpphy` are both combo/reference-clock consumers off the same
`tcsrcc-glymur` reference-generator block, and everything here still runs
on dummy regulators with no PEP-evidenced rail sequencing. Not yet
isolated:

- Whether the plain "GPU test" DT (no USB-A) shows the same reboot-to-
  reboot eDP flakiness on its own — if so, USB-A is unrelated. If eDP is
  reliable on "GPU test" but flaky on "GPU and USB-A test" across several
  back-to-back reboots of each, that would point at the shared
  reference-clock theory instead.
- Whether USB-A itself is equally intermittent, or only eDP is affected.

**Bottom line for the owner:** USB-A bring-up succeeded — this is a real,
new result, not a failure. The blank screen on the second boot was the
eDP panel not training, and the machine was fully alive underneath it
(hence the keyboard responding); it was not a hang and nothing here
needs a fresh DTB or kernel change yet.

## Follow-up: what enabling `usb_2_qmpphy` changes for the display

A lead for the eDP flake, not a conclusion.

In `glymur.dtsi`, `usb_2_qmpphy` is a clock parent of:

- the display clock controller (`<&usb_2_qmpphy QMP_USB43DP_DP_LINK_CLK>`
  and `..._DP_VCO_DIV_CLK`, the dp2 inputs);
- GCC (`QMP_USB43DP_USB3_PIPE_CLK`).

While the PHY was disabled, those parents were simply absent. With it
enabled, fw_devlink makes the display clock controller wait for
`phy-qcom-qmp-combo`, which is a module loaded from the root filesystem.
So on this DT the eDP bring-up starts later and at a boot-dependent time.

The eDP itself runs on `mdss_dp3` with its own PHY and does not use
`usb_2_qmpphy` clocks. The failing boot's error is link training timing
out (`-110`) after the PHY powered on. That matches a known failure after
the same PHY fix: the ASUS Zenbook A16 report saw a black screen with
`-110` in about 1 of 3 boots. FixItFoundry/zenbook-a16-linux carries
unposted eDP `LINK_RATE_SET` patches for it, and our panel uses that eDP
1.4 rate-table path (`docs/upstream-patch-survey-2026-09-29.md`). The
likelier explanation is that intermittency, independent of USB-A. Those
patches are the next thing to review for eDP.

The comparison the doc already suggests would settle it: several
back-to-back boots of "GPU test" and of "GPU and USB-A test". If only the
USB-A entry flakes, the next step is building `PHY_QCOM_QMP_COMBO` into
the kernel so the dependency resolves at the same point every boot.

## Update: USB-C connector nodes added to the same DTB

The "GPU and USB-A test" DTB now also carries bare USB-C connector nodes
under `pmic-glink`, so that port notifications from the firmware are
acknowledged (`docs/usb-c-charging-2026-09-29.md`, last section).

- New DTB SHA-256: `398b335e…6543`.
- The USB-A part is unchanged.
- The connector nodes add no pins, and the DTB still passes the GPIO
  allow-list check.

## Kernel `-14`: the boot stick's SuperSpeed port failed to enumerate for an entire boot

On the kernel `-14` test DT boot used for the audio crash
(`docs/audio-headset-path-2026-10-17.md`), the USB-A SuperSpeed port
holding the boot stick never once enumerated: from the very first kernel
log lines (`usb usb3-port1: Cannot enable. Maybe the USB cable is bad?`,
starting in the pre-NTP boot timestamps) through the rest of the boot,
the port cycled continuously:

```
usb usb3-port1: Cannot enable. Maybe the USB cable is bad?
usb 3-1: Device not responding to setup address.
usb 3-1: device not accepting address N, error -71
usb usb3-port1: attempt power cycle
usb usb3-port1: unable to enumerate USB device
```

repeating for the entire session (178 occurrences of "Cannot enable" by
the time it was checked, still climbing). `lsusb -t` showed bus 3 (the
SuperSpeed root hub) present with zero child devices, and `lsblk` showed
no `sda` at all — the stick was simply never visible to Linux this boot.

**Not the audio crash's fault.** The failure loop started at the very
beginning of this boot's kernel log, well before the `21:15:53` Oops in
`wsa884x_runtime_suspend()` (`docs/audio-headset-path-2026-10-17.md`).
Separately: the controller and its PHYs (`a000000.usb`, the M31 eUSB2 PHY
and QMP combo PHY) probed completely normally — identical "supply ...
not found, using dummy regulator" lines to every previous good boot — so
this isn't a probe/driver-binding failure. It's a pure link-training
failure at the hardware level: the port repeatedly tries and fails to
bring the link up enough to even set a USB address.

The camera, on its own separate controller (`a200000.usb`, `usb_hs`), was
unaffected — this is isolated to the one physical USB-A port.

**Not touched:** the boot stick was not unplugged or reseated (per the
standing rule that it sits in the only working port and cannot be
removed). GRUB reads the kernel from the stick before Linux's own USB
driver initializes, so this Linux-level failure shouldn't by itself block
booting; a reboot's own hardware-level power cycle is a stronger reset
than the kernel's repeated in-driver retries (which never once
succeeded). Worth checking right after the next boot whether the port
enumerates cleanly again — if it fails identically from a fresh boot too,
that points at a kernel `-14` regression on this exact port rather than a
one-boot link-training glitch.

## The same boot: it recovered on its own, by falling back from SuperSpeed to High-Speed

No reboot happened. The failure loop above (`usb usb3-port1: Cannot
enable`) kept retrying continuously for about **13 minutes** (141
occurrences from `21:24:35` to `21:27:25`) and then stopped on its own:
at `21:27:26` the stick enumerated — but on `usb 2-1` (the same
controller's separate **High-Speed** bus), not `usb 3-1` (SuperSpeed).
`usb-storage` bound it normally and it mounted:

```
usb 2-1: new high-speed USB device number 6 using xhci-hcd
usb 2-1: Product: Ultra / Manufacturer: SanDisk
usb-storage 2-1:1.0: USB Mass Storage device detected
scsi 0:0:0:0: Direct-Access     SanDisk  Ultra            1.00 PQ: 0 ANSI: 6
sd 0:0:0:0: [sda] 120176640 512-byte logical blocks: (61.5 GB/57.3 GiB)
 sda: sda1 sda2
FAT-fs (sda1): Volume was not properly unmounted. Some data may be corrupt. Please run fsck.
```

No further `usb3-port1: Cannot enable` lines after `21:27:28` — the
SuperSpeed side simply gave up retrying, and the device stayed usable
afterward over the High-Speed pins of the same USB-A connector (`lsusb
-t`: bus 2 "480M" with the mass-storage device attached, bus 3 "10000M"
still a bare root hub with no device). The stick mounted at
`/run/media/rahul/UBUNTU 26_0`, 86% used, 7.4G/1.1G avail — readable and
otherwise normal, just at roughly 1/10th its usual SuperSpeed throughput,
and with the "not properly unmounted" FAT warning from the 13-minute gap
with no clean unmount in between.

**Reading:** this points at a transient SuperSpeed link-training problem
on this one boot, not a dead port or a dead stick or a kernel `-14`
regression that blocks USB-A outright — High-Speed (whose electrical
pins are physically separate from SuperSpeed's in a USB-A receptacle)
worked throughout, once the host stopped trying SuperSpeed. The
unrelated stuck `check-audio.sh` process (`docs/audio-headset-path-2026-10-17.md`)
is still stuck in `D` state after this recovery — that still needs a
reboot; this USB-A episode resolved itself without one. Worth checking
on the next boot whether SuperSpeed trains cleanly from the start, to
tell a one-boot glitch from something that recurs.
