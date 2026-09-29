# eDP Display Working: First Full-DT Boot With Native Graphics, September 29, 2026

Booted "Ubuntu on SSD: device tree (full, DRM debug)" on kernel
`7.3.0-rc2-glymur-4` (the WSL-built PHY backport,
`docs/edp-phy-backport-2026-09-29.md`). **The panel lit.** This is the
first successful full-DT boot with a working native display. Private logs:
`.work/edp-display-working-2026-09-29/` (boot report
`boot-20260929T153652-c1b5250d.txt`, full `journalctl -k -b`).

## The fix worked

`journalctl -k -b` has no `phy poweron failed` line at all (the previous
two boots — lab run 3 and the 2-lane test — both hit `-110` at this exact
point). Link training:

```
[drm:msm_dp_ctrl_on_link [msm]] rate=270000, num_lanes=2, pixel_rate=149761
[drm:msm_dp_ctrl_link_train_1_2 [msm]] link training #1 on phy 0 successful
[drm:msm_dp_ctrl_link_train_1_2 [msm]] link training #2 on phy 0 successful
```

2 lanes at 2.7 Gb/s (HBR) — exactly the firmware's link and the panel's own
DPCD ceiling (`docs/edp-2lane-test-run1-2026-09-29.md`) — trained on the
first attempt, on the **unmodified full DTS** (still declaring 4 lanes up
to 8.1 Gb/s as the ceiling; msm negotiated down to what the panel actually
supports and that now works, so the 2-lane DTS change is not needed). The
`max_lanes=4 max_link_rate=810000` debug line earlier in the log is the
DT-declared ceiling before negotiation, not a DPCD read; it should not be
confused with the panel's real 2-lane/2.7 Gb/s limit confirmed by raw DPCD
bytes in the 2-lane test.

`/sys/class/drm/card1-eDP-1`: `status=connected enabled=enabled`, mode
`1920x1200`. `/sys/class/backlight/dp_aux_backlight` exists and reads a
live brightness (409/2047) — DP-AUX backlight control works out of the box.

## Broad subsystem sweep (same boot, per the "minimize reboots" rule)

| Subsystem | Result |
|---|---|
| Native display (eDP, DPU) | **Working**: 1920x1200, DP-AUX backlight |
| GPU | Still disabled as designed: `msm_dpu: no GPU device was found`; `arm-smmu 3da0000.iommu` and `gxclkctl-kaanapali` still defer/-110 (expected, `CLK_GLYMUR_GPUCC` not built). `renderD128` exists but belongs to `msm_dpu` (`DRIVER=msm_dpu`), not an Adreno GPU node — no accidental GPU bring-up |
| Battery / AC / USB-C power | Working: `qcom-battmgr-bat` (64%, 11.76 V, discharging ~9.5 W, 16 cycles), `qcom-battmgr-ac`/`-usb`/`-wls`, two `ucsi-source-psy` supplies |
| Bluetooth | `hci0` present |
| Wi-Fi | Associated (`wlo1`) |
| ADSP / CDSP | Both `running`; SoCCP `attached` |
| Audio | No ALSA soundcard (`aplay -l`: none) — ADSP runs but SoundWire/LPASS isn't wired yet, as before |
| Thermal | 70 zones, as on the lab DT |
| USB | None (`lsusb` empty) — no USB controller in this DT, as documented |

Nothing here regresses anything the display-lab boot already proved; the
full DT with a working display now matches the lab DT's subsystem coverage
plus a native picture.

## What this changes

- The full DT is now bootable end-to-end with a real display, on the
  unmodified DTS (no lane/rate override needed in the DTS itself).
- The `-110` PHY power-on failure is resolved by Qualcomm's posted v8 PHY
  programming-sequence fix, backported into `7.3.0-rc2-glymur-4`
  (`patches/kernel/backports/`), for this panel's rate (2.7 Gb/s) and lane
  count (2). This is independent confirmation, alongside the ASUS Zenbook
  A16 report cited in the backport doc, that the fix's PLL/SSC rewrite is
  correct for 2-lane 2.7 Gb/s — a rate/lane combination nobody had
  previously confirmed with this series.
- The 2-lane test DTB and its GRUB entry are no longer the active path
  forward (already replaced by "full, DRM debug" per the backport doc);
  the plain "full" entry should work identically without the debug
  logging once this is confirmed stable.

## Next

- Boot the plain "Ubuntu on SSD: device tree (full)" entry (no
  `drm.debug`) to confirm the fix holds without the extra logging
  overhead, and check whether the boot-time firmware framebuffer hands off
  to msm cleanly with a visible desktop, not just a trained link.
- Audio (SoundWire/LPASS) is now the next open subsystem with the ADSP
  already up.
- Consider sending the upstream fix + Mahua/HP panel confirmation back to
  the linux-arm-msm thread (`docs/edp-phy-backport-2026-09-29.md`'s
  "Independent confirmation" section already tracks the related report).
