# Qualcomm Kernel vs HP ACPI: Probe Gaps

The comparison uses Qualcomm `qcom-next` commit
`a47c4c5aa34b866136077d023d7c9e78d5a2225b` (7.3.0-rc2), image-recipe
commit `e2150b21fa303d5571d2fdb2a978ba5de7eb275b`, the HP DSDT in the
private `.work/acpi-analysis-20260914-combined/` directory, and the completed
September 25 Ubuntu ACPI capture. This is source analysis, not a successful
Qualcomm-kernel boot.

## I²C is not an ID-only change

Ubuntu loaded `i2c_qcom_geni`, but the HP's five `QCOM0F10` platform devices
had no bound driver and no I²C adapter appeared. Qualcomm's
`drivers/i2c/busses/i2c-qcom-geni.c` matches `QCOM0220` and `QCOM0411`, not
`QCOM0F10`. HP's `I2C5` and `I2C9` are top-level ACPI devices with MMIO/IRQ
resources and a vendor `CLKD` package; they have no apparent named `se` clock
property or GENI wrapper parent.

### Verified controller identity, unresolved operating state

The HP's static `_CRS` Memory32Fixed windows are each `0x4000` bytes.
Their first ExtendedIRQ values and addresses match the corresponding
Qualcomm `glymur.dtsi` I²C nodes exactly. ACPI names are not DT bus numbers:

| HP ACPI device | ACPI MMIO | ACPI GSI | Qualcomm DT node / interrupt |
|---|---:|---:|---|
| `I2C1` (`QUP_0_SE_0`) | `0x00B80000` | 4188 | `i2c0`, GIC ESPI 92 |
| `I2C5` (`QUP_0_SE_4`) | `0x00B90000` | 4192 | `i2c4`, GIC ESPI 96 |
| `I2C6` (`QUP_0_SE_5`) | `0x00B94000` | 4193 | `i2c5`, GIC ESPI 97 |
| `I2C9` (`QUP_1_SE_0`) | `0x00A80000` | 385 | `i2c8`, GIC SPI 353 |
| `IC10` (`QUP_1_SE_1`) | `0x00A84000` | 386 | `i2c9`, GIC SPI 354 |

All five declare `_DEP` on `PEP0`; `IC10` additionally depends on
`QGP1` (a separate `QCOM0F88` ACPI device). Their `CLKD` packages have
the same three nonzero seven-integer records:
`(0, 0x4B00, 100, 7, 26, 10, 11)`,
`(0, 0x4B00, 400, 2, 24, 5, 12)`, and
`(0, 0x4B00, 1000, 1, 18, 3, 9)`, followed by a zero record.
Those are raw firmware values, **not a validated Linux clock or timing
binding**. The `_CRS` provides MMIO and IRQ only, not a clock resource;
Qualcomm's `gcc-glymur.c` clock provider has a DT match but no ACPI match.
The identity match therefore does not establish whether firmware left the
SE clock, I²C protocol firmware, or power domain active under Linux.

The private HP DSDT also contains `PEP0.BSMD`, which returns a `BSRC`
package with one resource entry for each of the five I²C devices. Its
`DSTATE=0` entries list four wrapper clocks, the serial-engine clock with
value `0x0124F800` (19,200,000, plausibly Hz), bus arbitration resources,
and two TLMM pins.
The `DSTATE=3` entries list corresponding clock and pin changes. The
serial-engine clock names and pins are:

| ACPI device | `PEP0.BSRC` SE clock | TLMM pins |
|---|---|---|
| `I2C1` | `gcc_qupv3_wrap0_s0_clk` | 0, 1 |
| `I2C6` | `gcc_qupv3_wrap0_s5_clk` | 20, 21 |
| `I2C9` | `gcc_qupv3_wrap1_s0_clk` | 32, 33 |
| `IC10` | `gcc_qupv3_wrap1_s1_clk` | 36, 37 |
| `I2C5` | `gcc_qupv3_wrap0_s4_clk` | 16, 17 |

Those five clock names match clocks implemented in Qualcomm's
`gcc-glymur.c`; the pins match the corresponding `qup0_se*` and
`qup1_se*` functions in `pinctrl-glymur.c`. The `BSRC` records are Windows
PEP resource descriptions. Linux has no identified consumer for them.
They identify intended resources and a likely clock rate. They do not establish
whether those resources are enabled on an ACPI Linux boot or provide a
Linux clock binding. Do not execute `PEP0._DSM` or reproduce its power
transitions without a reviewed implementation.
The PEP clock value is consistent with `CLKD`'s `0x4B00` value if both
represent 19.2 MHz in different units. This does not identify the other
`CLKD` fields or prove the units of either table.

> **Correction (2026-09-26):** the paragraph below is true for Linux
> v7.0 / Ubuntu 7.0.0-30, not for this qcom-next tree. In qcom-next,
> `geni_se_resources_init()` calls `devm_pm_opp_set_clkname(dev, "se")`,
> which fails with `-ENOENT` first, so an ID-only match fails probe cleanly
> and no ACPI GENI device can probe at all. See
> `docs/repository-audit-2026-09-26.md`.

The probe obtains wrapper data from `dev->parent`. Its resource initializer
allows an ACPI device to proceed if `devm_clk_get(dev, "se")` fails, but the
I²C initializer then calls `clk_get_rate(se->clk)`. The common clock
implementation does not accept an error pointer. Thus simply adding the HP ID
could trigger an invalid clock access if ACPI supplies no `se` clock. Clock,
parent/wrapper, firmware, IRQ, and transfer paths require a deliberate ACPI
design and static validation before any hardware probe test.

The wrapper issue is independent of the clock. If the engine reports an
invalid protocol, `geni_i2c_init()` calls `geni_load_se_firmware()`, which
dereferences `se->wrapper->dev`; the HP I²C devices are top-level ACPI objects,
not children of the DT GENI wrapper driver. The firmware loader also writes
wrapper registers. GENI DMA preparation returns `-EINVAL` without a wrapper.
These paths need review before an HP ID can be safely matched, even if a
clock is supplied or a timing-table fallback is added.

The existing Linux transfer path can also select SE DMA for sufficiently
large messages; `geni_se_tx_dma_prep()` and its RX counterpart require
`se->wrapper`, which these top-level HP ACPI devices do not provide.
Any ACPI implementation must either supply a correct wrapper relationship
or use a verified FIFO-only path. A speculative `CLKD` parser or
`QCOM0F10` match is not a safe workaround.

There is a useful independent precedent: [OpenBSD's `qciic.c`](https://github.com/openbsd/src/blob/master/sys/dev/acpi/qciic.c)
matches `QCOM0F10`, maps the ACPI MMIO resource, and uses polled FIFO
transfers without parsing `CLKD` or obtaining a driver-managed `se` clock.
The [September 2026 OpenBSD commit](https://github.com/openbsd/src/commit/489d85f3c2d48f169dfcc51e3a687764d11d476b)
reports keyboard and touchpad working in ACPI mode on a **different** HP
Glymur machine, the EliteBook X G2q. Its `I2C5` and `I2C9` controller
addresses match this OmniBook's ACPI resources. This suggests that firmware
may leave some engines configured, but it does not prove the OmniBook's
boot-time protocol, clock, or power state. Audit the HP's `PEP0` power
dependency before any MMIO diagnostic: all five I²C objects declare `_DEP`
on `PEP0` (`QCOM0F17`, compatible ID `PNP0D80`). Windows binds this node to
`qcpep_8480`; the Ubuntu capture has no platform driver for it. The pinned
Linux ACPI scanner's `acpi_ignore_dep_ids` includes `PNP0D80`, so this `_DEP`
does not hold back enumeration. That exception is not proof that Linux has
established equivalent power state. Even a register read can fail if the
device is not powered. A Linux ACPI path must not assume the DT GENI resource
sequence applies.

OpenBSD's attach path maps the ACPI MMIO window and registers an I²C bus;
its transfer path uses polled GENI FIFO registers and does not program a
clock, load SE firmware, use DMA, or require a GENI wrapper. That is a
candidate model for a Linux ACPI path, not evidence that the existing Linux
GENI driver can be reused unchanged. A Linux adapter can trigger immediate
child-device probe transfers, so a first HP experiment needs an explicit
failure path for an unpowered engine or unexpected protocol before adapter
registration. The controller's `PEP0` dependency and safe clock assumptions
remain open; the OpenBSD report is for a different machine.

An RFC patch in `patches/kernel/0001-i2c-qcom-geni-reject-missing-se-clock.patch`
rejected an error-valued SE clock before `clk_get_rate()`. It adds no HP ID.
*(Superseded on 2026-09-26 by
`0001-soc-qcom-geni-se-acpi-missing-se-clock.patch`: the old guard was
unreachable in qcom-next and would have failed every ACPI GENI device in
v7.0.)*
`git apply --check` passed against the pinned `qcom-next` commit, and the
patched `drivers/i2c/busses/i2c-qcom-geni.o` cross-compiled with the
published Qualcomm config in a separate WSL worktree/output directory. The
full patched kernel was not built or booted; this test does not validate
ACPI resources, transfers, or input devices.

The independent RFC
`patches/kernel/0004-i2c-qcom-geni-balance-pm-on-rate-error.patch` routes a
failed `set_rate()` through the transfer cleanup path, releasing the
runtime-PM reference acquired earlier in `geni_i2c_xfer()`. It applies to
the pinned tree, passed style checks, and its I²C object cross-compiled in
the isolated worktree. It neither matches `QCOM0F10` nor establishes the
HP's clock, wrapper, firmware, or power state.

The next RFC,
`patches/kernel/0005-i2c-qcom-geni-glymur-acpi-inspect-rfc.patch`, adds
`QCOM0F10` matching with a default-off `qcom0f10_inspect` parameter. With
that parameter unset, probe returns before MMIO access. When enabled, the
path accepts only the HP's `I2C1` (`0x00B80000`) and `I2C5`
(`0x00B90000`) windows of size `0x4000`, reads the GENI protocol, FIFO
disable bit, and SE clock-enable bit, then returns without binding an
adapter. It does not issue I²C transfers or program the controller.
The object cross-compiled and the patch passed static checks. A first
boot would establish only the observed register state. Even MMIO reads
can fault if firmware has not powered the engine; the PEP0 dependency
remains unresolved. No transfer path or boot test is claimed.

## Input also needs ACPI GPIO interrupts

The HP ACPI children `ECKB` (`QTEC0001`, keyboard on `I2C1`), `TCPD`
(`ELAN0189`, touchpad on `I2C5`), and `TSC1` (`ELAN2513`, touchscreen on
`I2C9`) each name `GIO0` in `_DEP` and have a GPIO interrupt resource in
`_CRS`. Thus an I²C adapter alone is unlikely to produce working input.
Ubuntu enumerated `GIO0` (`QCOM0F0C`) but its platform `uevent` had no
driver. Qualcomm's `pinctrl-glymur.c` has DT matches only.

The HP `GIO0` memory base (`0x0F100000`) and first parent IRQ (240, GIC
SPI 208) match `glymur.dtsi`'s TLMM node. `GIO0._DSM` returns `GPIC=0xFA`
(250 GPIO lines), whereas the Linux pinctrl data advertises 251 entries,
including pin 250 used for UFS reset. The separate RFC
`patches/kernel/0002-pinctrl-qcom-glymur-draft-acpi-match.patch` adds an ACPI
match with a 250-line GPIO view. It applies cleanly and its ARM64 object
cross-compiles with Qualcomm's config. **It has not been booted and is not
an input-enablement patch.** The keyboard and touchpad use PDC-encoded ACPI
GPIO specifiers above the physical GPIO count:

| ACPI child | Bus | ACPI `GpioInt` pin | PDC index / IRQ | Physical GPIO |
|---|---|---:|---:|---:|
| `ECKB` keyboard | `I2C1` | 704 (`0x2C0`) | 11 / 751 | 67 |
| `TCPD` touchpad | `I2C5` | 896 (`0x380`) | 14 / 658 | 3 |
| `TSC1` touchscreen | `I2C9` | 51 (`0x33`) | direct | 51 |

The mapping follows [OpenBSD's PDC translation](https://github.com/openbsd/src/blob/master/sys/dev/acpi/qcgpio.c)
and this HP's `GIO0._CRS` IRQ order plus `GIO0.CIPR` table. Linux
`gpiolib-acpi-core.c` currently passes the raw ACPI pin to
`gpio_device_get_desc()`, so a 250-line chip cannot resolve 704 or 896.
Reproduce the mapping without copying the private DSDT into the repository:

```bash
python3 scripts/linux/analyze-acpi-pdc.py .work/acpi-analysis-20260914-combined/dsdt.dsl --pin 704 --pin 896 --pin 51
python3 scripts/linux/test-analyze-acpi-pdc.py
```

The checker reads the `GIO0` resource and CIPR package, retains duplicate
IRQs in `_CRS` because their *positions* define PDC indices, and fails on
missing or ambiguous CIPR entries. It verifies static firmware data only;
it does not prove that Linux can route or service those interrupts.
The draft match alone may register direct GPIOs but cannot deliver keyboard
or touchpad interrupts. A bounded ACPI PDC-translation design is required.
ACPI `_AEI` events, interrupt routing, suspend/wake behavior, and the effect
of gpiochip registration on this HP also remain untested. Do not combine the
draft with an I²C ID patch and assume input is ready.

For a Linux implementation, translate the ACPI pin before descriptor lookup
and before requesting ACPI GPIO events and OpRegion descriptors, while
preserving the original pin number for AML event dispatch, wake-policy
lookups, and OpRegion connection identity. Derive the mapping from `GIO0._CRS` IRQ
order and the firmware's `GIO0._DSM` CIPR package, validate each physical
pin against the reported count, and reject malformed or missing entries.
The Linux GPIO descriptor path and the ACPI `_AEI`/OpRegion paths need the
same translation; changing only consumer lookup is incomplete. Review
`acpi_gpiochip_alloc_event()` and `acpi_gpiochip_free_interrupts()` too:
they lock and unlock GPIO offsets using the raw firmware pin. The HP's
current `GIO0._AEI` uses direct pin 126, but a general PDC-aware driver
must use the translated offset for those GPIO-core calls while retaining
the raw pin for `_EVT`. The HP `GIO0` OpRegion uses direct pin 92. Review
the TLMM summary IRQ and PDC wake route as well: Qualcomm's DT uses
`wakeup-parent = <&pdc>`, whereas the ACPI path has no equivalent DT
phandle. OpenBSD's ACPI driver handles its TLMM summary IRQ, but this
HP has not demonstrated working interrupts under Linux. Do not treat a
successful GPIO descriptor lookup as evidence of functional input.
OpenBSD's `qcgpio` registers the first ACPI IRQ as its TLMM summary IRQ
and programs GPIO interrupt target value 3. Qualcomm's Glymur pinctrl
data also uses target value 3, and `pinctrl-msm` uses the first platform
IRQ as its summary parent. This supports testing the summary route once
the controller path is ready; it does not establish the HP's PDC wake
route or prove an interrupt will reach Linux.
`msm_pinctrl_probe()` has an ACPI pin-range fallback, but that does not
translate these PDC specifiers. Hard-coding only pins 704 and 896 would miss
other firmware consumers and board variants. This design needs static tests
before any hardware experiment.

The offline RFC `patches/kernel/0003-gpio-acpi-glymur-pdc-translation-rfc.patch`
implements that bounded translation after `0002`. It validates the ACPI
GPIO count, requires one IRQ per `_CRS` ExtendedIRQ resource, rejects
malformed or duplicate CIPR IRQ entries, and leaves unmatched PDC indices
unusable. Consumer lookup and ACPI event/OpRegion descriptor requests use
translated offsets; AML event dispatch retains the raw pin. The three
affected ARM64 objects cross-compiled with Qualcomm's published config,
and the patch passed `git apply --reverse --check` against the isolated
worktree. The consumer lookup holds the GPIO device's SRCU read lock while
calling the controller translator, so removal cannot invalidate the chip
pointer during that call. This is **not a hardware validation**. GPIO
interrupt delivery,
I²C power/clock/firmware setup, input operation, and wake behavior remain
unproven; do not put this RFC or a derived Image on the live USB.

## USB-C has an ACPI state dependency

The HP DSDT's `USBC000` `_STA` returns zero when `\_SB.PMGK.LKUP` is zero.
`PMGK.LKUP` initializes to zero; `PMGK.LKST` can update it and notify UCSI.
The captured Linux boot reported `USBC000 status=0` and no Type-C class
device. `PMGK` is `QCOM0F8E`; it reported `status=11` but no bound driver in
its platform-device `uevent`. A whole-tree search found no `QCOM0F8E` or
`LKST` support in the reviewed Qualcomm kernel. This is a plausible software
gating path, not proof that it alone explains every USB-C failure. Do not
force ACPI methods or power states on the laptop as a diagnostic shortcut.

Qualcomm's published kernel fragments select `CONFIG_I2C_QCOM_GENI=y` but
leave `CONFIG_UCSI_ACPI` unset. The upstream UCSI ACPI driver matches
`PNP0CA0`, which the HP UCSI object declares as a compatible ID, but a
`status=0` ACPI device cannot be enabled just by selecting that module. The
reference configuration and CRD DTB are not an HP boot profile. Keep the
existing ACPI live media as a recovery path; do not deploy the CRD DTB or an
ID-only kernel patch.

## Target Windows cross-check (read-only, September 25)

Live PnP properties on this same laptop confirm that Windows binds
`qci2c_8480` to all five `QCOM0F10` controllers, `qcpmicglink_8480` to
`QCOM0F8E` (`PMGK`), `qcusbcucsi_8480` to `QCOM0F9D` (`UCS0`), and Microsoft's
`UcmUcsiAcpiClient` to `USBC000`. All report no PnP problem. These are
Windows-driver observations, not evidence that the corresponding Linux paths
are implemented.

The installed `qci2c8480.inf` matches `ACPI\QCOM0F10` but contains no bus
clock or timing parameters. Each HP I²C ACPI object provides a `CLKD`
package, whose interpretation still needs a documented Linux implementation;
do not assume the DT GENI timing table is interchangeable. The installed
`qcpmicglink8480.inf` matches `ACPI\QCOM0F8E`. The DSDT's `PMGK.LKST` method
sets `LKUP`, notifies UCSI, **and writes additional PMGK control fields** when
passed `1`; it is not a harmless visibility toggle. The caller and required
protocol sequence are not established by the INF or DSDT alone.

The installed `qcusbcucsi8480.inf` matches `ACPI\QCOM0F9D` and installs a
separate `UCS0.bin` resource. Do not import or redistribute this proprietary
Windows payload. Its presence is another reason not to treat `UCSI_ACPI=y`
as a complete USB-C solution.

All five I²C objects have the same four-entry `CLKD` package: three
seven-integer rows containing `0x4B00` and `0x64`/`0x190`/`0x3E8`, then a
zero row. The apparent 19.2 MHz and 100/400/1000 kHz values align with
common bus frequencies, but the remaining fields are not identified by the
INF. Qualcomm's GENI driver uses its own fixed timing map, whose row values
are not identical; preserve the HP table until its field semantics are clear.

Qualcomm's `pmic_glink.c` and `ucsi_glink.c` include
`qcom,glymur-pmic-glink` DT matches. Their platform path has no ACPI match for
the HP's `GLNK` (`QCOM0F84`), `PMGK` (`QCOM0F8E`), or `UCS0` (`QCOM0F9D`).
The live Linux platform `uevent`s do not report a driver for these IDs.
Reusing the DT path on this ACPI boot would require designed transport,
device enumeration, and firmware-state handling, not merely adding IDs.

## Next safe development gate

The September 25 read-only `QCOM0F10` module test reached both `I2C1` and
`I2C5`: each reported I²C protocol, FIFO available, and the master SE clock
enable bit set. See `docs/qcom0f10-inspection.md`. This confirms those three
register values at probe time; it does not validate an ACPI clock consumer,
`PEP0` power sequencing, IRQ delivery, or a transfer. The other three I²C
controllers were not inspected. A second default-off read-only snapshot module
has been built to capture SCL counters and GENI status on only those two
controllers. Its separate optional USB boot entry completed on September 25:
both had the HP `CLKD` 400-kHz timing tuple `(2, 5, 12, 24)`, GENI status 0,
and DMA disabled at probe time. The pinned Qualcomm driver uses
`(2, 5, 11, 22)` for its 19.2-MHz 400-kHz map; substituting that map would
change the firmware-observed timing. No transaction or power-state transition
has been tested.

Keep investigation offline until the ACPI GENI clock/resource model and the
PMIC-GLink/UCSI protocol are understood. A proposed patch must first show
that probe handles absent clocks and wrapper data without dereferencing
invalid pointers, and explain the `CLKD` timing mapping. For USB-C, establish
the GLink transport and the firmware-defined `LKST` call sequence before any
runtime method call. Only then build a bounded test kernel; preserve the
working ACPI USB-A recovery boot and avoid writes to internal storage.

## Reference build result

`scripts/linux/build-qcom-next.sh` merged Qualcomm's `prune.config`,
`qcom.config`, and all `qcom-deb-images/kernel-configs/*.config` fragments
out of tree and compiled with two cross-compiler jobs on 2026-09-25. The
unmodified `Image` (SHA-256
`994266a28deaa1dc7e2cf8e7ce58d06323e4b88cebe999ac89a7338220548295`)
and `glymur-crd.dtb` (SHA-256
`8487861ef706cea0ac048afbfbeff1855f008d1b3d2a1d6a99b74830d0f08ec5`)
are in `/home/login/glymur-build/.work/build/qcom-next/`. Both source
checkouts remained clean. This verifies the reference build, not HP boot or
peripheral functionality; neither artifact was copied to the installer USB.
