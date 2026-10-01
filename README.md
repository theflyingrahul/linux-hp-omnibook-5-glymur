# Linux on the HP OmniBook 5 16 (Snapdragon X2 Elite)

Native Linux bring-up for the HP OmniBook 5 16-bf1xxx, a laptop with
Qualcomm's Snapdragon X2 Elite. HP does not support Linux on it; this
project builds that support from the laptop's own firmware tables and
Windows drivers, with a device tree written for this board.

| | |
|---|---|
| Laptop | HP OmniBook 5 16-bf1107nr (product `D3ZN3UA`), the 16-bf1xxx family |
| SoC | Snapdragon X2 Elite X2E-84-100, the "Mahua" die (`mahua.dtsi`, which builds on `glymur.dtsi`) |
| Memory, display | 32 GB, 16-inch OLED touchscreen |
| Kernel | Qualcomm's [qcom-next](https://github.com/qualcomm-linux/kernel) plus [`patches/kernel/`](patches/README.md) |
| Device tree | [`dts/qcom/mahua-hp-omnibook-5-bf1xxx.dts`](dts/qcom/mahua-hp-omnibook-5-bf1xxx.dts) |
| Distribution | Ubuntu 26.04 today; Fedora ARM64 is the intended installed OS |

> **Experimental.** This has run on one laptop. Following it means
> repartitioning the internal SSD and running a self-built kernel. Read the
> disclaimer in [`docs/booting.md`](docs/booting.md) first.

## Status

Working: the internal display with GPU acceleration (Adreno X2-85, Mesa
main), keyboard, touchpad, lid, Wi-Fi, Bluetooth, battery and USB-C
charging, USB-A, USB-C at high speed and SuperSpeed, CPU frequency scaling,
thermal sensors, and the embedded controller (fan, temperatures, mute LEDs).

Not yet: audio, the NPU, suspend, full- and low-speed USB-C devices (mice,
receivers), the embedded controller's hotkeys, external displays, the TPM.

Per-subsystem detail: [`docs/status.md`](docs/status.md). Newest results:
[`docs/progress-log.md`](docs/progress-log.md).

## Booting it

[`docs/booting.md`](docs/booting.md) explains how the laptop boots Linux
(GRUB on a USB stick, the kernel and root filesystem on an SSD partition,
Windows left untouched) and the steps to set it up, after the disclaimer.

## How the work is done

- **Evidence first.** Every board value (pins, addresses, power rails,
  timings) comes from this laptop: HP's ACPI tables, HP's Windows drivers,
  or a measurement. Unknown values stay unknown rather than guessed
  ([`docs/evidence-policy.md`](docs/evidence-policy.md)).
- **No foreign device trees.** Reference boards and other laptops are read
  for comparison only; their device trees are never booted on this laptop.
- **Upstream first.** Qualcomm's published kernel work is reused, fixes by
  others are carried only until qcom-next has them, and generic fixes go to
  the kernel mailing lists.
- **Safe for Windows.** Nothing writes the Windows partitions, the EFI
  partition or the firmware.

This project uses an AI coding assistant for analysis, scripts, patches and
notes. Every hardware result here comes from real boots on the laptop, and
the owner reviews and signs off on anything sent upstream.

## Repository layout

| Path | Contents |
|---|---|
| [`dts/`](dts/README.md) | the board device tree: daily, test and minimal variants |
| [`patches/`](patches/README.md) | kernel patches, layered by who benefits, and their status |
| [`scripts/linux/`](scripts/linux/README.md) | kernel and Mesa builds, installers, check scripts, analysis tools |
| [`scripts/windows/`](scripts/windows/README.md) | read-only evidence capture on Windows |
| [`boards/hp-omnibook-5-16-bf1xxx/`](boards/hp-omnibook-5-16-bf1xxx/README.md) | board command line and HP's firmware files |
| [`docs/`](docs/) | status, boot guide, and dated findings |
| `captures/` | sanitized logs from the laptop that the findings cite |
| [`reference/`](reference/README.md) | HP package metadata and upstream references |

## Contributing

Test reports, logs and kernel work are welcome. Read
[`CONTRIBUTING.md`](CONTRIBUTING.md) first: it has the safety rules for
testing on the laptop and what to keep out of logs.

## License

Device trees are BSD-3-Clause, code is GPL-2.0-only, documentation is
CC-BY-4.0, and patches follow their upstream project. HP's firmware files
are not covered. See [`LICENSE`](LICENSE).
