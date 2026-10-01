# Contributing

Thanks for helping. This project brings up Linux on the HP OmniBook 5
16-bf1xxx (Snapdragon X2 Elite X2E-84-100, the "Mahua" die). Where things
stand is in [`docs/status.md`](docs/status.md); the newest results are at
the top of the [README](README.md).

Questions, test reports and ideas go in GitHub issues; changes go in pull
requests.

## What helps most

**If you have this laptop (or another 16-bf1xxx):**
- Boot results: which kernel, which boot entry, what works and what does
  not, with the logs (see [Reporting a result](#reporting-a-result)).
- Differences from this unit: other SKUs (X2 Plus, other RAM sizes,
  panels), other BIOS versions.

**If you have another Snapdragon X2 laptop:**
- ACPI and Windows driver comparisons. Many HP and Qualcomm firmware
  patterns are shared, and seeing them on a second machine tells us what is
  board-specific.

**If you know the kernel, Qualcomm platforms or the Linux graphics/audio
stack**, these are open:
- **Audio**: SoundWire and LPASS (the codecs are SDCA, `MAN_0217`/
  `PART_0110` in HP's tables). Nothing is wired yet.
- **NPU**: the CDSP boots with HP's signed firmware, but nothing above it
  (FastRPC, userspace) has been tried.
- **Full- and low-speed USB-C devices** (mice, receivers): they fail with
  `error -71` on every port; high speed and SuperSpeed work. The SMB2370
  eUSB2 repeaters identify but do not fix it
  ([`docs/usb-dwc3-crash-2026-09-30.md`](docs/usb-dwc3-crash-2026-09-30.md)).
- **EC hotkeys**: the EC's event line fires, but F9/F11 produce no key
  events yet ([`docs/ec-2026-09-30.md`](docs/ec-2026-09-30.md)).
- **Power rails for mainline**: the device tree declares no RPMh regulators
  yet. Each rail has to be mapped from HP's PEP votes before the device
  tree can go upstream.
- **Suspend, the TPM, the RTC, external displays.**

## Safety rules for testing on the laptop

These protect the machine and the Windows install on it. Changes that break
them will not be merged.

- Never flash firmware, change BIOS settings, or clear or disable the TPM.
- Never write to the Windows partitions (EFI, the BitLocker C: drive,
  Recovery). Linux lives on its own partition and boots from a USB stick's
  GRUB; the internal EFI partition is not touched.
- Never boot a device tree written for another machine (a reference board
  or another laptop), a Qualcomm reference image, or a driver patch that
  only adds an ID match. They can drive pins and power rails this board
  wires differently.
- Keep your BitLocker recovery key somewhere off the laptop before you
  start.
- Keep a known-good boot entry (the previous kernel, the minimal device
  tree, ACPI) for every test.

## Keeping private data out

Logs and firmware dumps can identify you or your machine. Before you attach
or commit anything:

- **Never share the `MSDM` ACPI table** (`msdm.dat`): it holds the Windows
  product key. `acpidump` writes it along with the others; the DSDT and
  SSDTs are what we need.
- Remove serial numbers (the laptop's, the SSD's, USB devices'), Wi-Fi and
  Bluetooth MAC addresses, UUIDs and the machine's hostname or user name.
  Replace them with a marker such as `[REDACTED-SERIAL]`.
- No photos of the bottom label or the BIOS screens with serials visible.

## Reporting a result

Open an issue with:

- the model and product number (for example `16-bf1107nr`, `D3ZN3UA`), the
  CPU, and the BIOS version;
- the kernel (`uname -r`) and the boot entry or device tree you used;
- what you tested and what happened;
- the relevant logs:
    - `journalctl -k -b` for kernel problems;
    - on the SSD install, the boot report in `/var/log/glymur/` and the
      output of the matching check script in `scripts/linux/glymur-ssd/`
      (`check-usb.sh`, `check-ec.sh`, `check-mesa.sh`).

Say what you saw, not only what you think it means: "the panel stayed dark
after GRUB" is more useful than "the display driver is broken".

## Changing the repository

- **Evidence first.** Every hardware value (a pin, an address, a rail, a
  timing) must come from this machine: HP's ACPI tables, HP's Windows
  drivers, or a measurement. Name the source in the commit message or the
  docs. A value you cannot source stays unknown; do not copy it from a
  reference board.
- **Device tree rules.** No RPMh regulators until the rail is evidenced
  from HP's PEP votes. After any change, the GPIO allow-list check must
  pass:

      python3 scripts/linux/check-dt-gpio-allowlist.py <dtb>

- **Findings** go in a new dated file, `docs/<topic>-YYYY-MM-DD.md`; do not
  rewrite older reports. Update `docs/status.md` when a subsystem's state
  changes.
- **Style** follows `.editorconfig`: UTF-8, LF line endings, four spaces in
  Markdown, shell, Python and PowerShell, tabs in `.dts`/`.dtsi`. Keep code
  comments short; explanations go in the READMEs and `docs/`.
- **Commit subjects** are scoped, imperative and lowercase, as in the
  history: `docs: ...`, `dts: ...`, `tools: ...`, `build: ...`. Keep
  commits focused.
- **Checks** before a pull request, from the repository root:

      bash -n scripts/linux/*.sh
      python3 scripts/linux/test-analyze-acpi-pdc.py
      python3 scripts/linux/test-promote-hp-analysis.py
      git diff --check

  For kernel or device tree changes, also say which kernel you built and
  what you booted.
- **Pull requests** explain the evidence and what changes for the laptop,
  list the checks you ran and their results, and call out anything
  generated, proprietary or sensitive.

## Kernel patches and upstream

Kernel patches live in `patches/kernel/` (see
[`patches/README.md`](patches/README.md)) and are applied on top of
Qualcomm's qcom-next by `scripts/linux/prepare-qcom-next-glymur.sh`.
Generic fixes are sent to the Linux kernel mailing lists by email, following
the kernel's `Documentation/process/submitting-patches.rst`, not through
this repository. A patch sent upstream needs a working user on mainline
itself, not only on this project's bring-up patches.

Patches meant for upstream need a `Signed-off-by:` line (the Developer
Certificate of Origin). Do not add firmware files from anywhere but HP's
published driver pack for this laptop.

## AI tools

This project uses an AI coding assistant, and contributions made with one
are welcome. Say so in your pull request. You are responsible for what you
submit: understand it, and only report hardware results you have run
yourself.

## License

Contributions are licensed as described in [`LICENSE`](LICENSE): BSD-3-Clause
for device trees, GPL-2.0-only for code, CC-BY-4.0 for documentation, and
the upstream project's license for patches.
