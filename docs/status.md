# Project Status

**2026-09-26, second input-test run: keyboard, touchpad, and touchscreen
work under Linux.** This is the stock Ubuntu `7.0.0-30-generic` live kernel
with no DTB, plus two out-of-tree ACPI modules. Wi-Fi scanning also works.
The EC bus (IC10) is in GPI DMA mode and was refused safely. See
`docs/acpi-input-results-run2-2026-09-26.md`.

**2026-09-26, first input-test run:**

- Wi-Fi scanned successfully with the HP board data.
- The ACPI GPIO module loaded.
- The I²C module oopsed on a NULL GENI wrapper, since fixed and restaged.

See `docs/acpi-input-results-2026-09-26.md`.

**Earlier 2026-09-26 update:** a repository audit
(`docs/repository-audit-2026-09-26.md`) corrected the I²C clock analysis
and replaced RFC patch 0001. A keyboard/touchpad test kit is now staged on
the installer USB as an optional GRUB entry, "Glymur ACPI keyboard/touchpad
test (RAM live)"; it has not yet been run. It loads two out-of-tree modules
into the stock Ubuntu kernel:

- an ACPI TLMM GPIO driver with PDC pin translation;
- an ACPI GENI I²C driver derived from v7.0 that uses the firmware's `CLKD`
  timing.

Ubuntu's `i2c_hid_acpi` should then bind the keyboard and touchpad. The same
boot also probes the touchscreen and EC buses. See
`docs/acpi-input-test-2026-09-26.md`.

Battery and AC AML read PMIC-GLink fields through the ABD GenericSerialBus
region (`QCOM1045`), gated by the same `PMGK.LKUP` flag as USB-C. They do not
use the EC's I²C bus.

Ubuntu 26.04.1 ARM64 booted through UEFI/ACPI on 2026-09-15 and 2026-09-25 without a supplied target DTB. The second automated capture confirmed `CONFIG_I2C_QCOM_GENI=m` and a loaded module, but five `QCOM0F10` controllers remained unbound; no I²C adapters or keyboard/touchpad input appeared. Linux started 12 CPUs and enumerated PCI4/WLAN, PCI5/NVMe, two xHCI controllers, the camera, and the right USB-A installer. See `docs/ubuntu-live-boot-results-2026-09-25.md`. An elevated Windows Day-0 metadata capture and ACPICA table capture were completed earlier. Qualcomm's preview validates a separate reference platform; see `docs/qualcomm-preview-review-2026-09-25.md` before applying its boot instructions here.

A September 26 RAM-live whole-system inventory completed all checkpoints and
powered off without keyboard input. It confirmed the desktop used `simpledrm`
without a GPU render node; a verified QCC2072 firmware retry reached firmware
startup but failed to find HP board data, leaving no Wi-Fi interface. The
private capture stays on the installer USB. Its live clock still reports July
27, so its directory timestamp is not the physical collection date.
See `docs/system-inventory-results-2026-09-26.md` for the sanitized findings.

Read-only checks on the same laptop's live Windows installation verified the
driver-to-ACPI-ID mapping for I²C, PMIC GLink, USB-C, and UCSI. Qualcomm's
Glymur GLink/UCSI implementation is currently matched through device tree,
whereas this HP boots through ACPI. The specific probe and firmware-state
gaps are recorded in `docs/qualcomm-acpi-gap-2026-09-25.md`; the reference
kernel and CRD DTB are not ready to boot on this HP.
An RFC guard for one missing-clock probe failure has passed an isolated
cross-compile, but it does not bind the HP I²C devices or enable input.
An independent RFC also balances runtime PM if I²C bus-rate setup fails;
it is likewise offline-only and adds no HP device ID. The HP's ACPI
clock, GENI wrapper, and `PEP0` power-state model remain unresolved.
The HP's `PEP0.BSRC` resource table identifies all five I²C engine clocks
with a numeric value of 19,200,000 and their TLMM pin pairs. Linux has no
validated ACPI path to apply those resource settings.
The live boot also waited for `dev-tpm0.device` and `dev-tpmrm0.device` after
reporting no TPM chip. Its TPM2 ACPI table uses vendor-reserved start method
9, and the captured ACPI namespace has no `MSFT0101` device for Linux's
standard CRB driver. These are two waits for one absent TPM, not evidence of
two independent service failures or an I²C regression. TPM support requires
separate investigation; do not clear or disable the Windows TPM to hide the
wait.
A separate inspection module now cross-builds against the captured Ubuntu
`7.0.0-30-generic` headers. It is default-off, registers no I²C adapter,
and was loaded in a separate live USB test on September 25. Both inspected
ACPI controllers (`I2C1` and `I2C5`) reported I²C protocol, enabled FIFO,
and a set master SE clock-enable bit. The collector completed; no adapter
or bus transfer was attempted. Clock/power transitions and interrupts remain
unproven. A separate read-only timing/status snapshot is built and staged as
an optional live USB boot entry and has now completed. Both devices had the
HP `CLKD` 400-kHz divider/SCL counter tuple `(2, 5, 12, 24)` at probe time,
with no active command and DMA disabled. This is not a measured bus rate or
successful transfer. That boot used `clk_ignore_unused pd_ignore_unused`; in ACPI mode no Linux clock or
power-domain provider binds, so those arguments were no-ops (see
`docs/repository-audit-2026-09-26.md`). See
`docs/qcom0f10-inspection.md`.
The first active FIFO transaction has an offline design in
`docs/i2c-fifo-probe-design.md`; no transfer-capable module or new boot entry
has been built or staged.
A separate draft ACPI GPIO match also cross-compiled; it remains unbooted.
Keyboard, touchpad, and touchscreen need both their I²C bus and `GIO0`
interrupt provider. Keyboard and touchpad additionally use PDC-encoded ACPI
GPIO numbers that the draft does not translate, so these patches do not
restore input even when considered together. The static ACPI mapping resolves
the keyboard's pin 704 to GPIO 67 and the touchpad's pin 896 to GPIO 3;
Linux still needs a correct runtime translation path. The read-only
`scripts/linux/analyze-acpi-pdc.py` checker reproduces those mappings from
the private DSDT and passes synthetic tests. An unbooted PDC-translation
RFC now cross-compiles after the GPIO match draft, but interrupt delivery
and I²C remain unvalidated; no new boot artifact was made.

| Subsystem | Status | Notes |
|---|---|---|
| boot | ACPI live boot confirmed | Ubuntu ARM64 reached userspace without a target DTB; collector completed |
| CPU | Linux observed | Snapdragon X2 Elite X2E84100; Ubuntu kernel initialized ACPI/PSCI |
| SMP | Linux booted 12 CPUs | Kernel log reports 12 processors activated; hotplug and long-run stability untested |
| timers | Linux clocksource active | ARM architected timer at 19.2 MHz and `arch_sys_counter` selected; accuracy and suspend behavior untested |
| NVMe | Linux enumerated | Samsung endpoint at PCI domain 5 (`0005:01:00.0`); namespace and partitions visible |
| internal display interface | Unknown | The live capture did not establish eDP versus another transport |
| OLED brightness | Unknown | |
| GPU | Native acceleration absent in tested boot | GNOME used `simpledrm` on `simple-framebuffer.0`; no `/dev/dri/renderD*` appeared. ACPI `QCOM0FF5` was unbound, although `msm` was loaded. Xwayland reported software fallback. |
| touchscreen | **Linux working (test modules)** | `ELAN2513` 0x10 on I2C9, GPIO 51; `hid-multitouch`; see `docs/acpi-input-results-run2-2026-09-26.md` |
| touchpad | **Linux working (test modules)** | `ELAN0189` 0x15 on I2C5, PDC pin 896 → GPIO 3; `hid-multitouch` |
| keyboard | **Linux working (test modules)** | `QTEC0001` 0x3A on I2C1, PDC pin 704 → GPIO 67; `i2c_hid_acpi` |
| keyboard backlight | Unknown | |
| function keys | Unknown | |
| lid switch | Linux input enumerated | ACPI `LID0` appeared as the sole input device in the live capture; lid events were not tested |
| battery | Not exposed in tested Linux boot | Windows exposes charge and discharge data, but Linux had no `/sys/class/power_supply` device; UPower displayed no battery. |
| charging | Windows observed; Linux unknown | The charger powers and charges the laptop in Windows; Linux ACPI adapter `_PSR` previously failed because a GenericSerialBus handler was missing. |
| thermal sensors | Unknown | |
| fan | Unknown | |
| Right USB-A | USB 3 storage and USB 2 HID enumeration work | The installer used bus 3 at 5 Gbit/s; a Dell receiver bound to `usbhid` on bus 2 at 12 Mb/s. Mouse motion events remain unproven. See `docs/usb-input-isolation-test.md`. |
| USB-C port 1 | Timed storage hotplug not detected | Owner connected USB-C storage in the hinge-side port; no USB event or topology change appeared. Earlier installer boot from USB-C also failed. |
| USB-C port 2 | Timed storage hotplug not detected | Owner repeated the test in the other left port with the same result. Connector routing and cause remain unknown. |
| USB-C Power Delivery | No Linux Type-C device observed | ACPI `USBC000` reported `status=0`; `/sys/class/typec` and `/sys/class/usb_role` were empty. Negotiation was not tested. |
| USB-C DisplayPort Alt Mode | Unknown | No Type-C class device appeared; DisplayPort routing was not tested |
| Wi-Fi | **Working in RAM-live test** (scan only) | Upstream `firmware-2.bin` plus a private HP `board-2.bin` brought up `wlo1`; a scan found 13 BSSs on 2.4, 5, and 6 GHz; no association was attempted. See `docs/acpi-input-results-2026-09-26.md`. Earlier notes: | Windows binds this device to `bdwlan_qcc2072_1p0_ncm820A.elf`; a private `board-2.bin` adds it under the HP name. See `docs/acpi-input-test-2026-09-26.md`. The live-only retry loaded verified upstream `firmware-2.bin` and identified the QCC2072 chip, then failed the `board-2.bin` lookup for PCI `17cb:1112`, HP subsystem `103c:8ef3`, QMI chip 33, board 255. No WLAN interface appeared; a successful bind command did not mean the radio was usable. |
| Bluetooth | No controller observed in tested boot | Qualcomm FastConnect C7700/NCM820A maps through ACPI `QCOM0F6B`/`QCOM0FEA`; `/sys/class/bluetooth` was empty. |
| speakers | No ALSA soundcard in tested boot | `aplay` and `/proc/asound/cards` found none. |
| headphone jack | Physical jack observed | Linux audio behavior untested |
| microphones | Unknown | |
| RGB camera | Linux USB/UVC enumerated | HP True Vision FHD camera present and bound to `uvcvideo` |
| IR camera | Windows observed | HP IR camera present |
| suspend | Unknown | |
| resume | Unknown | |
| RTC | Unknown | |
| TPM | Not exposed to Linux | TPM2 table present, but no `/dev/tpm0` or `/dev/tpmrm0` in captured boot; vendor-reserved start method 9 needs investigation |
| ADSP | Unknown | |
| CDSP | Unknown | |
| NPU | Unknown | |
| firmware loading | Partial | Verified upstream QCC2072 firmware started in RAM; the HP-specific board-data lookup failed. Other subsystem firmware paths remain untested. |
