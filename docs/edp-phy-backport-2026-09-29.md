# eDP PHY Fix Backport and a Functional Minimal DT, September 29, 2026

The 2-lane test (`docs/edp-2lane-test-run1-2026-09-29.md`) and lab run 3
(`docs/display-lab-run3-2026-09-28.md`) both show the eDP PHY failing its
own power-on (`phy poweron failed --> -110`) before link training. The
panel's DPCD caps it at 2 lanes and 2.7 Gb/s. This records the upstream fix
for that failure, its backport into kernel `7.3.0-rc2-glymur-4`, and a
minimal device tree that keeps everything the lab boot proved working.

## The upstream fix

Bjorn Andersson (Qualcomm) posted "phy: qcom: edp: Update v8 programming
sequence" v1 to linux-arm-msm on 2026-06-22
(`20260622-glymur-edp-phy-v1-0-814b45089ac9@oss.qualcomm.com`). His cover
letter says the initial v8 (Glymur) support worked only at 4 lanes and
8.1 Gb/s: 2-lane 5.4 Gb/s failed link training, and at 2.7 and 1.62 Gb/s
the PLL did not lock. The series rewrites the v8 sequence from the
programming guide and Qualcomm's Windows driver:

- PLL and SSC values per rate;
- per-lane TX setup before the PLL starts;
- AUX-less/PCS timing;
- the LDO setting per rate;
- TSYNC and DCC calibration after lock;
- the v8 PHY status register (0x110, not 0x0e0);
- v8 swing tables.

His commit message says the PHY "has been validated to lock" at all four
rates with 2 and 4 lanes. It reports successful link training only for
4-lane 8.1 Gb/s and 2-lane 5.4 Gb/s. Konrad Dybcio
reviewed it against the programming guide and flagged ordering and
duplicate-write differences, "1 or 2" of which he thought might matter. No
v2 was found, and qcom-next `a47c4c5aa` (our base) does not carry it.

Independent confirmation, from lkml, "glymur eDP PHY (v8): link trains only
at HBR3, all lower rates fail", August 2026:

- On an ASUS Zenbook A16 (Glymur, Samsung ATNA60HR07 OLED), RBR and HBR
  failed with `-110`, and HBR2 passed clock recovery but failed
  equalization.
- Konrad pointed the reporter to this series. With it, the panel trained
  at HBR2, its maximum.

Nobody has reported link training at 2-lane 2.7 Gb/s, our panel's
configuration, with this series. The evidence covers PLL lock at 2.7 Gb/s
(the cover letter) and training at other rates.

## Why it fits this laptop

- The same failure: `-110` at 2.7 Gb/s, then again at 1.62 Gb/s after
  msm's rate fallback. Those are the two rates where the cover letter says
  the PLL does not lock, and our panel supports nothing faster.
- **The registers match lab run 3.** At 2.7 Gb/s, run 3 compared the
  firmware's live PLL registers with the old driver:
    - 10 differed: `DEC_START`, `DIV_FRAC_START2`/`3`, `LOCK_CMP1`,
      `CORECLK_DIV`, `VCO_TUNE1`/`2`, `BIN_VCOCAL_CMP_CODE1`/`2` and
      `SSC_STEP_SIZE1`;
    - 3 matched: `DIV_FRAC_START1`, `LOCK_CMP2`, `SSC_STEP_SIZE2`.

  The series changes exactly those 10 at 2.7 Gb/s and leaves those 3
  alone. It also sets `LOCK_CMP_EN`, which run 3 does not report.
- The new 2.7 Gb/s divider is 0x46 + 0x050000/2^20 = 70.3125. Times a
  38.4 MHz reference, that is exactly 2700 MHz. The 38.4 MHz is taken from
  the driver's Nord PLL table comment ("CXO = 38.4 MHz"), not measured
  here.

The firmware's actual values were not saved in run 3, so this shows the
same registers are wrong. It does not show that the firmware's values
equal the series' values.

## The backport (`patches/kernel/backports/`)

- The series is written against mainline. qcom-next adds Nord PHY support
  to the same file, so patch 1 conflicts in 4 places.
- Each commit is Bjorn's patch applied to mainline and then three-way
  merged with qcom-next's Nord delta:
    - register defines: union of both;
    - Nord's resistor-code branch: kept;
    - the `_v46` final status poll: keeps Nord's status register;
    - Nord's ops: given the `_v46` callbacks, which carry its `is_nord`
      branches, so Nord runs the sequence it ran before. This relies on
      patch 1 being a no-op refactor, which Konrad's review confirmed.
- Check: removing the Nord delta from each result again gives exactly
  Bjorn's patched mainline file. The remaining differences are all Nord
  code. Glymur's v8 code is the posted code, unmodified.
- Patch 2 changes only v8 code. Comparing function bodies before and after
  it, only the v8 PLL and SSC functions change and 13 v8 functions are
  added. Every shared and `_v46` function is byte-identical.
- The `-4` build compiles the result. Nord is not our hardware and is not
  run here.
- `prepare-qcom-next-glymur.sh` applies `upstream/qcom-next-acpi`, then
  `backports`, then `glymur-bringup`. On a fresh worktree the series
  applies cleanly and reproduces the build tree, with the eDP driver as
  the only difference.

## Kernel `7.3.0-rc2-glymur-4`

- Built in WSL from the build tree plus the backport, with
  `GLYMUR_SUFFIX=-4`. Package SHA-256 `679dbb2f…21a5`.
- `phy-qcom-edp.ko` has vermagic `7.3.0-rc2-glymur-4` and the new
  `qcom_edp_finish_power_on_v8`.
- The full DTB is byte-identical to the one in the `-3` package, so the
  PHY driver is the only display change.
- On the USB in `glymur-tools/kernels/`, with copies of `install-kernel.sh`
  and `glymur-boot-report.sh` and `SHA256SUMS`.

## Minimal DT: now the lab configuration

The display-lab device tree (full DT with dispcc, MDSS, the DP3 PHY and the
panel supply disabled) is the only DT boot where battery and AC worked.
Its live check (`docs/lab-boot-state-2026-09-28.md`) found:

- **Working:** CPUs, NVMe, keyboard, touchpad, touchscreen, lid, cpuidle,
  Wi-Fi, Bluetooth, 70 thermal zones, and battery and AC over PMIC GLink.
- **Up, but not usable yet:** the ADSP and CDSP boot HP's signed images,
  but there is no audio. The two UCSI power supplies register, but the
  USB-C ports do not work without USB controllers and PHYs.
- **Not working:** USB, audio, GPU, TPM, fan RPM and EC thermistors, CPU
  frequency scaling, and suspend. RTC was not checked.

The old minimal DT had no remoteprocs or PMIC GLink, so no battery or AC. Its GRUB entry was removed on
2026-09-29 because of the lab's runtime display phase, not the DT itself.

`mahua-hp-omnibook-5-bf1xxx-minimal.dts` now includes the full DTS and
disables the same four display nodes. Compiled, it is identical to the lab
DTB (without overlay symbols) except for:

- the model;
- the GPIO allow-list, which also reserves the eDP pins 18, 70 and 119,
  since the firmware drives them and nothing in this tree does.

It passes the allow-list check (21 used, 230 reserved). `dispcc` stays
disabled, as the device-tree rules require. It ships in the `-4` package,
so it reaches `/boot/glymur-dtb` with the kernel.

## GRUB

- The finished 2-lane test entry is replaced by "Ubuntu on SSD: device tree
  (full, DRM debug)": the newest kernel and the installed full DTB, with
  `drm.debug=0x102 log_buf_len=16M`.
- The menu order is minimal, full, full (DRM debug), ACPI newest, ACPI
  previous, and the workstation, after the three stock entries.
- `grub.cfg` backup: `.work/grub-before-edp-backport-20260929.cfg`.

## Running it (two boots)

1. Boot "Ubuntu on SSD: ACPI, newest glymur kernel" (the USB is visible
   there). Install:
   ```
   K=$(ls -d /media/$USER/*/glymur-tools/kernels /run/media/$USER/*/glymur-tools/kernels 2>/dev/null | head -1)
   (cd "$K" && sha256sum -c SHA256SUMS)
   sudo bash "$K/install-kernel.sh" "$K/glymur-kernel-7.3.0-rc2-glymur-4.tar.gz"
   ```
   `-4` becomes the newest kernel and its DTBs (new minimal included) go
   behind `/boot/glymur-dtb`. `-3` stays as "previous".
2. Boot "Ubuntu on SSD: device tree (full, DRM debug)".

| Result | Meaning |
|---|---|
| Panel lights | Fixed. Check `journalctl -k -b` for `phy poweron failed` (should be absent) and the link rate and lanes. |
| Dark, no `-110` | The PHY now powers on; read the training steps in `journalctl -k -b -1`. The remaining candidates are Konrad's review points and swing levels. |
| Dark, `-110` again | The series does not cover this die (Mahua) or board. Compare the firmware's PLL registers with the series' values; the lab's `lab_fw_pll` instrumentation reads them. |

After a dark boot, wait three minutes before holding the power button, then
boot the minimal DT, which now includes battery and the remoteprocs.
