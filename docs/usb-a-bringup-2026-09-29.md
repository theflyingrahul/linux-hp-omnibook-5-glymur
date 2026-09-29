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
