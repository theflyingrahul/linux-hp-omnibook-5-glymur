# Patches

Kernel changes are split by who benefits:

| Directory | Contents | Upstream? |
|---|---|---|
| `kernel/upstream/qcom-next-acpi/` | Generic ACPI mechanisms for Snapdragon X2 (Glymur) laptops, as a `git format-patch` series against Qualcomm `qcom-next` `a47c4c5aa` | Yes, candidates |
| `kernel/upstream/standalone/` | Independent generic fixes | Yes, candidates |
| `kernel/glymur-bringup/` | Interim Glymur code, applied on top of the upstream series | No; replaced later |
| `kernel/drafts/` | Upstream-form drafts not yet used in a build | Future |
| `kernel/archive/` | Superseded diagnostics, kept for the record | No |
| `util-linux/` | Userspace (`lscpu` part ID) | Yes, candidate |

Board-specific values (pin lists, controller lists, the DSDT override,
Wi-Fi board data, firmware) are not kernel code. They live in
`boards/hp-omnibook-5-16-bf1xxx/`.

## Boot series (built by `scripts/linux/build-qcom-next-glymur.sh`)

Apply to `a47c4c5aa` in order: `upstream/qcom-next-acpi/0001–0003`, then
`glymur-bringup/0001–0002`.

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

The series was verified to reproduce the build tree exactly, except for
those two board defaults, which moved to the board's command line.

## Standalone upstream candidates

- `upstream/standalone/0001-soc-qcom-geni-se-acpi-missing-se-clock.patch`:
  an absent ACPI `se` clock becomes `NULL` and the OPP clock name is
  skipped, so the existing `QCOM0220`/`QCOM0411` ACPI IDs can probe again.
  See `docs/repository-audit-2026-09-26.md`.
- `upstream/standalone/0004-i2c-qcom-geni-balance-pm-on-rate-error.patch`:
  releases the runtime-PM reference when `set_rate()` fails.

## Drafts and archive

- `drafts/0002`, `drafts/0003`: the pinctrl-msm route to ACPI GPIO with PDC
  translation. They compiled in an isolated worktree but were never booted.
- `archive/0005`: the default-off `QCOM0F10` register inspection path, which
  the out-of-tree modules have superseded.

None of these patches carries a `Signed-off-by`; add it when submitting.

## Old flat numbering (used by dated reports before 2026-09-27)

| Old path under `patches/kernel/` | Now |
|---|---|
| `0001-soc-qcom-geni-se-acpi-missing-se-clock.patch` | `upstream/standalone/` (same file) |
| `0001-i2c-qcom-geni-reject-missing-se-clock.patch` | Removed on 2026-09-26; see the audit |
| `0002-pinctrl-qcom-glymur-draft-acpi-match.patch` | `drafts/` |
| `0003-gpio-acpi-glymur-pdc-translation-rfc.patch` | `drafts/` |
| `0004-i2c-qcom-geni-balance-pm-on-rate-error.patch` | `upstream/standalone/` |
| `0005-i2c-qcom-geni-glymur-acpi-inspect-rfc.patch` | `archive/` |
| `0006-ACPI-GED-Support-GpioInt-event-resources.patch` | `upstream/qcom-next-acpi/0001` |
| `0007-glymur-acpi-gpi-and-geni-i2c-wip.diff` | `upstream/qcom-next-acpi/0002`, `0003`, plus `glymur-bringup/0002` |
| `0008-glymur_acpi_gpio-intree-wip.c` | `glymur-bringup/0001` |
