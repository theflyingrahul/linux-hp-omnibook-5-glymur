This directory distinguishes between patches intended for the kernel (`patches/kernel/`) and patches for Linux firmware (`patches/linux-firmware/`).

The `0001-soc-qcom-geni-se-acpi-missing-se-clock.patch` file replaces the
earlier `0001-i2c-qcom-geni-reject-missing-se-clock.patch`. The old patch was
unreachable in qcom-next, because `devm_pm_opp_set_clkname()` fails first.
In v7.0 it would have made every ACPI GENI I²C device fail probe. The new
patch treats an absent ACPI `se` clock as firmware-owned: it stores `NULL`
and skips the OPP clock name, so ACPI GENI devices can probe again and the
I²C driver falls back to its 19.2 MHz table. It adds no HP ID. It
cross-compiles with Qualcomm's config, and 0001–0005 apply in order. See
`docs/repository-audit-2026-09-26.md`.

The keyboard/touchpad live test does not use these patches. It loads
out-of-tree modules into the stock Ubuntu kernel; see
`scripts/linux/glymur-acpi-input/` and `docs/acpi-input-test-2026-09-26.md`.

The `0002-pinctrl-qcom-glymur-draft-acpi-match.patch` file is an RFC ACPI
match for `GIO0`, compiled but not boot-tested. Its GPIO count comes from
this HP's ACPI table. It does **not** translate the keyboard/touchpad's
PDC-encoded GPIO numbers and cannot restore those devices. GPIO events and
power behavior still need review; do not stage it on the live USB.

The `0003-gpio-acpi-glymur-pdc-translation-rfc.patch` file depends on
`0002`. It adds an ACPI GPIO-core translation hook and derives PDC pin
mapping from `GIO0._CRS` and the firmware `_DSM`. Affected ARM64 objects
cross-compiled in an isolated worktree, and reverse application was checked.
It has **not** been booted, cannot make the unbound I²C controllers work,
and must not be staged on the installer USB. The ACPI TLMM IRQ path,
suspend/wake behavior, and device interactions still need validation.

The `0004-i2c-qcom-geni-balance-pm-on-rate-error.patch` file fixes a
runtime-PM reference leak if I²C bus-rate setup fails. It applies to the
pinned Qualcomm tree, cross-compiles with the other RFCs, and adds no HP
ACPI ID. It does not resolve the clock, wrapper, or power-state gaps.

The `0005-i2c-qcom-geni-glymur-acpi-inspect-rfc.patch` file adds an
opt-in `QCOM0F10` inspection path for this HP's `I2C1` and `I2C5` MMIO
windows. The default path does not map or read their registers. When
explicitly enabled, it reads protocol, FIFO, and SE clock indicators,
logs them, and returns without registering an I²C adapter or transferring
data. Its ARM64 object cross-compiled in the isolated worktree. An MMIO
read can still fault if the engine is unpowered; this is unbooted research,
not an input driver or an approved USB boot image.
The first planned live inspection uses the independent module in
`scripts/linux/qcom0f10-inspect/` with Ubuntu's already bootable kernel;
it does not require this Qualcomm kernel patch.
