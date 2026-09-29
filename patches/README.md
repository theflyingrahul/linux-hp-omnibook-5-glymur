# Patches

Kernel changes are split by who benefits:

| Directory | Contents | Upstream? |
|---|---|---|
| `kernel/upstream/qcom-next-acpi/` | Generic ACPI mechanisms for Snapdragon X2 (Glymur) laptops, as a `git format-patch` series against Qualcomm `qcom-next` (written on `a47c4c5aa`, applied since kernel `-5` on `e428097a36d`) | Yes, candidates |
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

Apply to qcom-next `e428097a36d` (the qcom-next tip on 2026-09-28; the
base was `a47c4c5aa` up to kernel `-4`) in order:
`upstream/qcom-next-acpi/0001–0003`, `glymur-bringup/0001–0002`, then
`backports/0001–0012` (`scripts/linux/prepare-qcom-next-glymur.sh`).
Kernel `-4` carried backports 0001–0002; `-5` carries all twelve. A fresh
`prepare` reproduces the `-5` build tree's source exactly.

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
