# Display Lab and Re-assessment, September 28, 2026

The full device tree reached userspace but left the OLED dark: eDP link
training failed at clock recovery, the panel asked for more voltage swing
until msm hit "max v_level reached", and msm gave up (`ret=-11`, then
`Failed link training`). See `docs/device-tree-first-boot-2026-09-28.md`.
This document re-assesses that boot against what Windows does on the same
machine, and describes the display lab: one boot that captures the
firmware's working eDP setup and tries every candidate fix at runtime.

## What Windows does (evidence from this laptop)

- **Panel.** The EDID in the Windows registry is SDC 0x4214
  "ATNA60KJ02-0", 1920x1200 at 60 Hz, pixel clock 149.76 MHz, 8 bpc, about
  3.6 Gbit/s. Windows runs it at 60 Hz only. Any lane/rate combination
  carries that, so a panel that fails clock recovery is not seeing a usable
  signal at all.
- **Power recipe** (HP's PEP, `\_SB.GPU0` component 0, F-state 0), in order:
    1. display clocks, including `tcsr_edp_clkref_en` and the MDP clock at
       660 MHz;
    2. GPIO 70 high (panel power);
    3. five rails, all in PEP mode 7 (high-power mode):
        - LDO1_F_E1 0.880 V, LDO2_F_E1 0.880 V, LDO4_F_E1 1.200 V
        - LDO8_B_E0 3.300 V, LDO18_B_E0 1.200 V
    4. GPIO 119 as `edp0_hot`;
    5. GPIO 18 high.

  There are no delays in this component; the delays in the recipe belong to
  components 12 and 13.
- **The rails are shared, and one differs from the CRD.** L2F_E1 and
  L4F_E1 are also voted by PCI3, PCI4 (the Wi-Fi PHY), PCI6, PCI7, UFS and
  USB2. On the Glymur/Mahua CRD, L1F/L2F/L4F feed the eDP reference-clock
  chain (TCSR QREF TX1, repeater 0, RX0 and refgen 3) and the eDP PHY. The
  CRD runs L8B at 1.504 V for another consumer; HP votes it at 3.3 V, so CRD
  values must not be copied.
- **Panel configuration XML** (`GPU0._ROM`): generic Qualcomm templates
  whose override EDIDs are other panels (an SDC 0x41A6 OLED and an AUO
  B133HAN05.8 LCD). `EDPOverrideMode` is 2 and Windows shows the real
  EDID, so the forced DPCD values describe the template panels, not ours.
  All templates set `EDPEnableSSC` to 1.
- **Display extension.** HP installs Qualcomm's CRD display extension
  (`qcdxext_crd8480`, `qcdxkmext8480_CRD.bin` as `AcpiExtFile` for
  `DEV_0FF5&SUBSYS_8F47103C`): power-state tables with the same votes, and
  no PHY or link settings.

## Re-assessment of the proposed fixes

- **Two-rail eDP fix (`7d6f532`): reverted.**
    - Its premise, that dummy regulators left the PHY unpowered, is
      contradicted by the boot itself. The firmware framebuffer stays lit on
      the minimal DT, and the Wi-Fi PCIe PHY runs on the same L2F/L4F rails
      with no Linux regulator declared.
    - As written, every eDP PHY shutdown would vote off rails the Wi-Fi PHY
      and the reference-clock repeaters share.
    - It declared two of the five rails Windows votes.

  The remaining power question, whether the rails are still in high-power
  mode after the firmware hands over, is now lab variant V1, with all five
  rails at HP's values and always-on.
- **Bluetooth: HP's files are for this controller.**
    - The header of HP's `clnbtfw10.tlv` says product 0x20, ROM build
      0x0101: ROM 1.1, which the controller reports.
    - HP ships a board-specific `clnbtnv10.b17` for the board ID (0x17) the
      driver asks for.
    - `install-firmware.sh` installed them as ROM "10", which btqca never
      requests; it now installs `ornbtfw11.tlv` and `ornnv11.*`. The lab
      tests HP's pair against linux-firmware's and keeps whichever works.
- **"`install-firmware.sh` was never run"** (in the first-boot doc) is
  wrong: the ADSP booted from `qcom/glymur/HP/…`, a path only that script
  creates. That doc looked in `/lib/firmware/qca/`, not
  `/lib/firmware/updates/qca/`.
- **Ruled out from the source:**
    - The Mahua TCSR models the eDP clock reference at the same offset
      (0x60).
    - msm reads eDP 1.4 link-rate tables and enables SSC when the DPCD
      advertises downspread.
    - The Mahua CRD drives a sibling Samsung OLED (ATNA60CL08) through the
      same controller, PHY configuration and panel driver.

## Candidate causes the lab distinguishes

- **What the driver does differently from the firmware.**
  `phy-qcom-edp.c`'s power-on writes fixed values the firmware may have set
  differently: lane polarity (`TX_POL_INV` = 0), drive-level offset,
  resistor codes, TX band, the eDP LDO setting, and the generic eDP swing
  tables.
- **Link parameters and power.** Lane count or lane mapping on HP's board,
  link rate, SSC, and rail mode.

The firmware's own values for all of these are readable while its picture
is still on screen.

## The lab (one boot)

Kit: `scripts/linux/glymur-lab/`, built and statically checked by
`build-lab.sh` (overlays applied offline with `fdtoverlay` and each merged
tree checked by `check-dt-gpio-allowlist.py`; module vermagic
`7.3.0-rc2-glymur-3`). It is staged on the USB in `glymur-tools/lab/`, with
the GRUB entry "Ubuntu on SSD: display lab (device tree)".

- **Boot.** The lab DTB is the full DT with dispcc, MDSS, the DP3 PHY and
  the panel supply disabled, plus overlay symbols. It boots like the minimal
  DT with the ADSP, CDSP and PMIC GLink added, so the firmware keeps the
  panel lit.
- **`glymur_lab.ko`** (debugfs):
    - a read-only snapshot of the TCSR eDP reference clock, dispcc DP3
      clocks and RCGs, TLMM 18/70/119, and, only when dispcc reports the
      MDSS GDSC and DP3 clocks on, the DP3 controller (not its AUX FIFO)
      and PHY registers;
    - overlay apply and remove;
    - runtime edits of the eDP endpoint's `data-lanes` and
      `link-frequencies`.
- **`phy-qcom-edp-lab.ko`**, generated from the pinned driver by
  `make-phy-edp-lab.py` with asserted edits:
    - it logs the firmware's PHY registers at probe, before anything
      reprograms them;
    - it logs every swing decision and a register dump after each power-on;
    - runtime knobs: swing table, SSC, and reuse of the firmware's TX,
      polarity, offset and band values.
- **Session** (`start-lab.sh`, run as the transient service `glymur-lab`,
  output in `/var/log/glymur/lab-<time>/`):
    1. baseline of every subsystem;
    2. firmware eDP snapshot, decoded by `analyze-fw-snapshot.py` into lane
       count, lane map, rate from Mvid/Nvid, and TX values;
    3. Bluetooth HP pair against linux-firmware;
    4. PMIC GLink/battery and SCMI cpufreq diagnostics;
    5. display: stop the desktop, apply the display overlay, then try the
       variants in the table below until the panel trains.

  Each variant records the kernel log with DRM DP debug, DPCD dumps, the
  connectors, clocks, regulators and registers. A dead-man timer reboots
  after 30 minutes; if nothing trains, the lab reboots when done.

| Variant | Change |
|---|---|
| V0 | full-DT display path as booted before |
| V1 | HP's five display rails, always-on, high-power mode |
| V2 | SSC off |
| V3 | SSC forced on |
| V4 | DP swing tables |
| V5 | firmware TX values, polarity, offsets and band |
| V6 | 2 lanes |
| V7 | RBR/HBR only |
| V8 | lane map 3,2,1,0 |
| V9 | the firmware's lanes, map and rate, with its TX values |

**Reboots needed:** one, into the lab entry, then whatever the owner boots
next. Nothing in the lab writes to the SSD outside `/var/log/glymur`,
`/run` and `/lib/firmware/updates/qca` (Bluetooth, reverted if HP's pair
fails).
