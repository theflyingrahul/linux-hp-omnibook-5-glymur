# Repository Audit: September 26, 2026

The repository's scripts, patches, and bring-up analysis were re-checked
against the pinned kernel sources: Ubuntu `linux-source-7.0.0` 7.0.0-31.31,
whose GENI files are byte-identical to Linux v7.0, and Qualcomm `qcom-next`
`a47c4c5aa`. They were also checked against the private DSDT and the
September 25/26 live captures. The findings below are corrected in the tree;
older dated documents keep their history but now point here where they were
wrong.

## Analysis errors

### 1. The "ID-only I²C patch" hazard depends on the kernel

`docs/qualcomm-acpi-gap-2026-09-25.md` said that adding `QCOM0F10` would
reach `clk_get_rate()` with an error pointer. This is true only for **Linux
v7.0 / Ubuntu 7.0.0-30**. That kernel's `geni_i2c_probe()` tolerates a
missing ACPI `se` clock, then `geni_i2c_clk_map_idx()` dereferences the
error pointer. The existing `QCOM0220`/`QCOM0411` ACPI IDs have the same
latent fault.

In the pinned **qcom-next** tree the clock code moved to
`geni_se_resources_init()`. That function calls
`devm_pm_opp_set_clkname(dev, "se")` unconditionally, which fails with
`-ENOENT` on an ACPI device without a clock provider. There, an ID-only
match fails probe cleanly before the clock-rate lookup. As a consequence,
no ACPI GENI I²C device can probe in qcom-next at all.

### 2. Patch 0001 was dead code in qcom-next and the wrong fix for v7.0

The old `0001-i2c-qcom-geni-reject-missing-se-clock.patch` rejected the
error pointer in the I²C driver:

- **In qcom-next:** it could never run, because the OPP call fails first.
- **In v7.0:** it would turn the fault into a probe failure for every ACPI
  GENI I²C device, including `QCOM0220` and `QCOM0411`.

It is replaced by `0001-soc-qcom-geni-se-acpi-missing-se-clock.patch`. The
new patch stores `NULL` for an absent ACPI clock, which the clock API treats
as a no-op, and skips the OPP clock name. `clk_get_rate(NULL)` returns 0, so
the I²C driver falls back to its 19.2 MHz table, which matches the rate in
HP's `PEP0.BSRC`. DT behaviour is unchanged. The patched objects
cross-compile with Qualcomm's config, and the whole 0001–0005 series applies
in order.

### 3. `clk_ignore_unused pd_ignore_unused` did not affect the ACPI captures

Several documents said the register snapshots "do not establish normal-boot
clock or power persistence" because those kernel arguments were present.
The September 25 capture's `platform-devices.txt` shows no clock controller,
RPMh, interconnect, or power-domain driver bound in the ACPI boot. The only
bound platform drivers were:

- `acpi-thermal`, `acpi-tad`, `acpi-fan`, `acpi-button`
- `xhci-hcd`
- `arm-smmu`, `arm-smmu-v3`
- `simple-framebuffer`, `serial8250`, `kgdboc`

Both arguments act only on clocks and power domains that a Linux provider
has registered, so they were no-ops there. Firmware clock and power state
therefore persists after `ExitBootServices` regardless of those arguments.
It is still true that nothing on Linux actively manages the state: runtime
power transitions and suspend remain unvalidated.

### 4. The DMA and wrapper hazards were overstated

> **Correction after the first live run:** this section missed one wrapper
> use. The inline `geni_se_get_tx_fifo_depth()` reads the QUP version
> through `se->wrapper`, and the test module oopsed there. See
> `docs/acpi-input-results-2026-09-26.md`.

Without a GENI wrapper, `geni_se_{tx,rx}_dma_prep()` returns `-EINVAL`, and
the v7.0 and qcom-next I²C transfer paths already fall back to FIFO for that
message. `geni_load_se_firmware()` does need the wrapper, but it runs only
when the engine reports an invalid protocol. The HP I2C1 and I2C5 engines
report protocol 3 (I²C). The test driver still forces FIFO mode and refuses
to probe unless firmware left an I²C FIFO engine with its serial clock
enabled.

### 5. `CLKD` semantics are determined, not unknown

The timing snapshot matches the whole 400 kHz row
`(0, 0x4B00, 400, 2, 24, 5, 12)`:

- `GENI_SER_M_CLK_CFG = 0x21`: divider 2 with the serial-clock enable bit.
- `SE_I2C_SCL_COUNTERS = 0x00503018`: high 5, low 12, cycle 24.
- `SE_GENI_CLK_SEL = 0`.

So each row is `(reserved, source kHz, bus kHz, divider, t_cycle, t_high,
t_low)`. A driver that programs the `CLKD` row for the ACPI children's 400 kHz
`ConnectionSpeed` writes back exactly the values firmware already set.

## Tooling bugs fixed

| File | Bug | Fix |
|---|---|---|
| 27 tracked text files | CRLF in the working tree despite `.editorconfig` LF; the `.manifest`, `.patch`, `.cfg`, `.c`, and `Makefile` types had no `.gitattributes` rule | Converted to LF; `* text=auto eol=lf` plus explicit rules |
| `generate-day0-candidates.py` | Duplicate hardware IDs from several INFs silently kept only the last `inf_source` (57 IDs); output was CRLF on Windows Python; only ran from the repository root | Merges all sources; writes LF; resolves paths from the script location |
| `check-build-host.sh` | GCC readiness ignored the native `gcc` needed for Kbuild host tools (`HOSTCC`, including `scripts/dtc`) | Checks `gcc` as part of the GCC path |
| `fetch-upstream-series.sh` | `curl -sL` treated HTTP error pages as a successful download | `curl -fsSL` |

Validation: the PowerShell static suite passed; `test-analyze-acpi-pdc.py`
(6 tests) and `test-promote-hp-analysis.py` (3 tests) passed; every
`scripts/linux/*.sh` passed `bash -n`; and the PDC analyzer still maps ACPI
pins 704 → GPIO 67 and 896 → GPIO 3 from the private DSDT.

## Checked and found sound

- The PDC translation analyzer and RFC patch 0003 match OpenBSD `qcgpio.c`
  on the real DSDT. The only differences are for duplicate `_CRS` IRQs that
  also appear in CIPR, which this firmware does not have: the four `_CRS`
  IRQ 240 slots have no CIPR entry.
- Patch 0004 (runtime-PM balance on `set_rate()` failure) is correct against
  qcom-next.
- The Windows Day-0 capture and helpers passed review. The only remaining
  weakness is `analyze-day0-capture.py`'s substring hardware-ID matching,
  which is left in place because it only reports candidates.
