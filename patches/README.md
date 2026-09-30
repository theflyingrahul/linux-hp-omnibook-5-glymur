# Patches

Kernel changes are split by who benefits:

| Directory | Contents | Upstream? |
|---|---|---|
| `kernel/upstream/qcom-next-acpi/` | Generic ACPI mechanisms for Snapdragon X2 (Glymur) laptops, as a `git format-patch` series against Qualcomm `qcom-next` (written on `a47c4c5aa`, applied since kernel `-5` on `e428097a36d`) | Yes, candidates |
| `kernel/upstream/qcom-next/` | Generic fixes against `qcom-next`, not ACPI-specific (since kernel `-6`) | Yes, candidates |
| `kernel/upstream/mainline/` | Submission-ready series against current mainline (only `Signed-off-by` missing) | Yes, ready |
| `kernel/backports/` | Fixes by others, posted or already in mainline, carried on our qcom-next base until qcom-next picks them up | Already posted or merged |
| `kernel/glymur-bringup/` | Interim Glymur code, applied on top of the upstream series | No; replaced later |
| `kernel/drafts/` | Upstream-form drafts not yet used in a build | Future |
| `kernel/archive/` | Superseded diagnostics, kept for the record | No |
| `util-linux/` | Userspace (`lscpu` part ID) | Yes, candidate |

Board-specific values (pin lists, controller lists, the DSDT override,
Wi-Fi board data, firmware) are not kernel code. They live in
`boards/hp-omnibook-5-16-bf1xxx/`.

## Boot series (built by `scripts/linux/build-qcom-next-glymur.sh`)

Apply to qcom-next `6b4daa845239` (the qcom-next tip on 2026-09-30, from
kernel `-8`; it was `e428097a36d` for `-5` to `-7` and `a47c4c5aa` up to
`-4`) in order:
`upstream/qcom-next-acpi/0001–0003`, `upstream/qcom-next/0001–0005`,
`glymur-bringup/0001–0002`, then `backports/0001–0012`
(`scripts/linux/prepare-qcom-next-glymur.sh`). Kernel `-4` carried
backports 0001–0002; `-5` carries all twelve; `-6` adds
`upstream/qcom-next/0001`; `-7` adds `upstream/qcom-next/0002`; `-8` moves
to the new base and adds `upstream/qcom-next/0003`; `-9` adds `0004`–`0005`
(the HP EC; qcom-next was still `6b4daa845239` when fetched before it);
`-10` reworks `0005` (backlight timeout instead of a level LED, EC events
and hotkeys; qcom-next unchanged again). A fresh `prepare`
reproduces the build tree's source exactly.

Base move for `-8` (2026-09-30): the 52 new qcom-next commits are all
Nord (Ethernet, display, eDP PHY, an ADSP remoteproc flag). The ones in
drivers we use (`dp_display.c`, `qcom_q6v5_pas.c`, the QMP v8 header) only
add or rename Nord entries, and no Glymur/Mahua device tree changed. The
one collision is `phy-qcom-edp.c`: the Nord eDP PHY series replaced the `is_nord` branches with
optional `phy_ver_ops` hooks (`phy_tx_lane_cfg`, `phy_tx_res_cfg`) and
`phy_status_reg`/`bias1_en_2lane` config fields, so `backports/0001–0002`
were re-ported: a three-way merge of our `-7` file with the new base, the
same three conflicts resolved in both patches, and the v46 callbacks now
use those hooks. The v8 (Glymur) code is unchanged: the new `0002` delta
is byte-identical to the `-7` one. Every other patch applies unchanged.
After `-8` was built, the comments in `upstream/qcom-next/0002` and `0003`
were shortened (no code change); `-8`'s source differs from a fresh
`prepare` only in those two comments.

Upstream submissions: `upstream/mainline/0001`–`0005` were signed off and
sent on 2026-09-30 (`docs/upstreaming-2026-09-30.md` has the message IDs). `0004` and `0005` are the mainline
versions of `upstream/qcom-next/0001` and `0002`. qcom-next was
fetched again before `-6` (2026-09-29) and before `-7` (2026-09-30): its
tip is still `e428097a36d`. Mainline (v7.3-rc5+37 on 2026-09-30) and
msm-next (`d33622598496`, 2026-09-26) have nothing new for these drivers,
and neither changes how msm reports GMEM.

1. `ACPI: GED: Support GpioInt event resources`: lets GED devices use
   `GpioInt` resources, which is what lid and EC event interrupts use on
   these laptops. Applies to mainline too.
2. `dmaengine: qcom: gpi: add ACPI support for the Glymur GPI engine`:
   `QCOM0F88` match data plus `gpi_acpi_request_chan()` for `_DEP` clients.
3. `i2c: qcom-geni: support firmware-owned ACPI controllers (QCOM0F10)`:
   - `CLKD` timing;
   - ACPI child bus speed;
   - a firmware-state gate;
   - wrapper-free FIFO depth;
   - GSI transfers through the `_DEP` GPI engine.
4. `gpio: add an interim Glymur ACPI TLMM driver (bring-up)`: a standalone
   OpenBSD-style driver with PDC translation. It is default-off and touches
   only pins named on the command line. The upstream route is
   `drafts/0002` (pinctrl-glymur ACPI match) plus `drafts/0003` (PDC
   translation in the GPIO ACPI core).
5. `i2c: qcom-geni: bring-up allow-list for firmware-owned controllers`:
   binds only the MMIO bases listed in `i2c_qcom_geni.acpi_buses`; the
   default binds none.

`upstream/qcom-next/`:

- `soc: qcom: pmic_glink_altmode: acknowledge notifications on undescribed
  ports`. The driver enables the firmware's USB-C port notifications but
  acknowledged only those for ports with a connector node. On this laptop
  an unacknowledged one left the firmware reporting no connection on
  either port (`docs/usb-c-ports-2026-09-29.md`). Notifications for other
  ports are now acknowledged from a work item. Not ACPI- or board-specific.
- `drm/msm/a8xx: report the GMEM size of the active slices`. msm told
  userspace the catalog GMEM size for all four slices (21 MB) while this
  X2-85 runs three. Mesa then put tiles and its CCU caches past the end of
  real GMEM, and GPU-rendered output was corrupted
  (`docs/gpu-corruption-2026-09-30.md`). Qualcomm's KGSL reports
  `gmem_size / 4 × active slices` (15.75 MB here); msm now does the same
  when it reads the slice mask. Not board-specific: any partial-slice A8xx.
  Confirmed on `-7`: clean desktop, `glmark2` 11570.
- `phy: qcom: eusb2-repeater: check the parent PMIC before using it`. For
  the SMB2370, the repeater driver checks that its parent PMIC reports the
  SMB2370 subtype before registering the PHY, and logs what it found. A
  board device tree places repeaters by SPMI slave ID; this makes a wrong
  placement refuse instead of writing to another PMIC. It lets the USB
  test DT declare the reference design's repeaters
  (`docs/eusb2-repeater-2026-09-30.md`). Generic.
- `dt-bindings: embedded-controller: add HP OmniBook 5 16 EC` and
  `platform: arm64: add HP OmniBook 5 16 embedded controller driver`
  (from `-9`). Board-specific, but upstreamable like the other
  `drivers/platform/arm64` EC drivers: hwmon for the fan speed and four
  thermistors, the mute LEDs, the keyboard backlight timeout and the F9/F11
  hotkeys, over HP's EC mailbox and event line
  (`docs/ec-2026-09-30.md`). Unproven until `-9` boots.

Backports (`backports/`), from Bjorn Andersson's "phy: qcom: edp: Update v8
programming sequence" v1 (linux-arm-msm, 2026-06-22,
`20260622-glymur-edp-phy-v1-0-814b45089ac9@oss.qualcomm.com`; reviewed by
Konrad Dybcio, not merged as of qcom-next `a47c4c5aa`):

- `phy: qcom: edp: split power-on sequencing by PHY version`;
- `phy: qcom: edp: update v8 power-on programming sequence`.

The series says the v8 PHY's PLL does not lock at 1.62 or 2.7 Gb/s
without it. This panel's maximum is 2.7 Gb/s, and its power-on fails with
`-110` at both rates, consistent with that. The series has not yet been
shown to train a link at 2-lane 2.7 Gb/s. The series is written against mainline. The backport resolves it
against qcom-next's Nord PHY support: Nord keeps its existing sequence
through the `_v46` callbacks, and Glymur's v8 code is exactly the posted
code. See `docs/edp-phy-backport-2026-09-29.md`.

`backports/0003`: "drm/msm/dp: skip PUSH_IDLE when the link was never
enabled" (Jesse Casco; mainline `e249a6e2a1`, 7.3-rc4). On X2 Elite a
PUSH_IDLE write into a DP controller whose link never came up makes
TrustZone force-stop the SoCCP/ADSP and silently reset the SoC. qcom-next's
MST rework moved that write into `msm_dp_ctrl_push_vcpf()`, so the guard is
ported onto `->link_ready` (see the patch's backport note).

`backports/0004–0012`, mainline 7.3-rc3..rc5 fixes that qcom-next
`e428097a36d` lacks, cherry-picked unmodified:

- drm/msm: `ea9dadeac7` fbdev framebuffer as system memory; `6fbbf1e152`
  Adreno autosuspend cleanup; `58995b11df` DP link bandwidth with wide bus;
  `a5b5cc9099` DPU pending peripheral flush; `ba970587a0` longer GMU
  firmware init timeout; `01c8d1f385` RCU-free ring and VM objects;
  `b7c0f8436f` check PAS only when a zap shader is present (the Glymur
  GPU has none).
- `4e93c65f87` Bluetooth: hci_qca: no serial writes after close.
- `268aacb2e2` i2c: qcom-geni: release DMA channels on probe error.

Not taken: `cb97bf3d4f` "i2c: qcom-geni: Fix hardcoded clock index in
SE_GENI_CLK_SEL". It conflicts with our ACPI I²C patch and makes probe fail
unless the SE clock table has an exact 32 or 19.2 MHz entry. Input works on
both boot paths without it.

The series was verified to reproduce the build tree exactly, except for
those two board defaults, which moved to the board's command line.

## Mainline series (ready to send)

`upstream/mainline/` applies to mainline `fd179f8a05` (7.3-rc5 era) and
compiles cleanly with `W=1`. `checkpatch --strict` flags only the missing
`Signed-off-by`, which the author adds before sending. See
`docs/upstreaming-2026-09-27.md` for recipients and status.

1. `ACPI: GED: Support GpioInt event resources`: the same code as
   `qcom-next-acpi/0001`, tested on this laptop.
2. `soc: qcom: geni-se: don't fail ACPI probe on a missing SE clock`: a
   regression fix; `Fixes: 5b8a39dcf909`. It replaces the old
   `standalone/0001`.
3. `i2c: qcom-geni: release runtime PM reference when set_rate fails`: a
   leak fix; `Fixes: 10e74f4c5046`. It replaces the old `standalone/0004`.

## Drafts and archive

- `drafts/0002`, `drafts/0003`: the pinctrl-msm route to ACPI GPIO with PDC
  translation. They compiled in an isolated worktree but were never booted.
- `archive/0005`: the default-off `QCOM0F10` register inspection path, which
  the out-of-tree modules have superseded.

None of these patches carries a `Signed-off-by`; add it when submitting.

## Old flat numbering (used by dated reports before 2026-09-27)

| Old path under `patches/kernel/` | Now |
|---|---|
| `0001-soc-qcom-geni-se-acpi-missing-se-clock.patch` | `upstream/mainline/0002` |
| `0001-i2c-qcom-geni-reject-missing-se-clock.patch` | Removed on 2026-09-26; see the audit |
| `0002-pinctrl-qcom-glymur-draft-acpi-match.patch` | `drafts/` |
| `0003-gpio-acpi-glymur-pdc-translation-rfc.patch` | `drafts/` |
| `0004-i2c-qcom-geni-balance-pm-on-rate-error.patch` | `upstream/mainline/0003` |
| `0005-i2c-qcom-geni-glymur-acpi-inspect-rfc.patch` | `archive/` |
| `0006-ACPI-GED-Support-GpioInt-event-resources.patch` | `upstream/qcom-next-acpi/0001` |
| `0007-glymur-acpi-gpi-and-geni-i2c-wip.diff` | `upstream/qcom-next-acpi/0002`, `0003`, plus `glymur-bringup/0002` |
| `0008-glymur_acpi_gpio-intree-wip.c` | `glymur-bringup/0001` |
