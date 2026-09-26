# First Active I²C Probe: Design Gate

This is an **offline design**, not a boot instruction or proof of hardware
safety. The September 25 read-only captures show that the HP's `I2C5`
(`QCOM0F10:01`, MMIO `0x00b90000`) runs I²C firmware with FIFO enabled,
clock config `0x21`, SCL counters `0x00503018`, GENI status 0, and DMA mode 0.
Those counters match the HP ACPI `CLKD` 400-kHz row. They do not prove the
touchpad is powered or that Linux can recover a failed command. The snapshot
boot used `clk_ignore_unused pd_ignore_unused`, so it is not evidence that
an ordinary boot keeps these resources enabled.
*(Correction 2026-09-26: no Linux clock, RPMh, or power-domain provider binds
in this ACPI boot, so those arguments were no-ops and firmware clock state
persists regardless. See `docs/repository-audit-2026-09-26.md`.)*

## One target, one operation

The private DSDT describes `TCPD` (ELAN touchpad) on `I2C5` at 7-bit address
`0x15`; its HID-I²C `_DSM` returns descriptor register `0x0001`. The first
useful test would write the little-endian register offset `{0x01, 0x00}`
without STOP, then read exactly 30 descriptor bytes from `0x15` with STOP.
The Linux HID-I²C core uses this two-message pattern and checks for length
30 and HID version `0x0100`. Do not probe any other address, invoke
`i2cdetect`, register an I²C adapter, or allow ACPI clients to auto-probe.
The unused `I2C_ADDR_ONLY` opcode is not a validated substitute for this
transaction.

## Required fail-closed behavior

An opt-in test module must restrict the ACPI ID and MMIO window exactly, and
refuse to run if protocol, FIFO, clock enable, clock selector, SCL counters,
DMA mode, or idle GENI status differ from the captured state. It must preserve
the HP timing: Qualcomm's generic 400-kHz counters differ. The observed
pre-existing master IRQ status `0x80` must be accounted for; clearing it is a
hardware write and needs an explicit, reviewed sequence. Use polling, not an
unvalidated ACPI interrupt route, and cap every FIFO, completion, cancel, and
abort wait. Qualcomm's normal cancel/abort path waits for IRQ-driven
completions; that cannot be copied until this HP's IRQ route is validated.
Never reset the controller, issue a bus-clear command, load GENI
firmware, or alter `PEP0` resources as an automatic recovery step. Log state
before and after each command; on an unrecoverable timeout, stop all further
transactions and power off the live system.

## No-go items before hardware use

Review the polled FIFO command/error/STOP sequence and cancel/abort behavior
against the pinned Qualcomm driver and OpenBSD's ACPI implementation. The
Qualcomm driver uses `STOP_STRETCH` on the first of two messages but does not
cancel on address NACK; its cancel/abort path waits for IRQ completions.
OpenBSD polls for command-done but does not check error bits or recover an
early failure in this path. Neither implementation establishes a safe polled
recovery sequence for this HP. The upstream GENI UART driver demonstrates
polling the generic cancel/abort completion bits, but UART does not establish
what I²C does with a held bus after `STOP_STRETCH`. Verify that a failed or
NACKed first message cannot leave a repeated START pending before any active
test.
The private DSDT's `PEP0.BSRC` requests the I2C5 wrapper clocks, a 19.2-MHz
`gcc_qupv3_wrap0_s4_clk`, and TLMM pins 16/17 for D0; its touchpad entry
lists D0/D3 states without a separate power action. There is no validated
Linux consumer of those requests. Resolve how the controller and pins stay
in their required state throughout the operation; the read-only snapshots
establish only an instant in time. Build and statically test the exact module
against the live Ubuntu kernel, then verify its hash and the USB filesystem.
Until these gates pass, do not stage a transfer-capable module or test kernel.

Source review: [pinned Qualcomm GENI I²C driver](https://github.com/qualcomm-linux/kernel/blob/a47c4c5aa34b866136077d023d7c9e78d5a2225b/drivers/i2c/busses/i2c-qcom-geni.c),
[Linux HID-I²C core](https://github.com/torvalds/linux/blob/master/drivers/hid/i2c-hid/i2c-hid-core.c),
[GENI UART polled cancel path](https://github.com/torvalds/linux/blob/master/drivers/tty/serial/qcom_geni_serial.c),
and [OpenBSD ACPI GENI I²C driver](https://github.com/openbsd/src/blob/master/sys/dev/acpi/qciic.c).
