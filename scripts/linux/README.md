# Linux Build Scripts

This directory contains shell scripts for validating the build environment, retrieving reference patches, and reproducibly building reference device trees (DTBs) out-of-tree.

## Scripts Overview

- `check-build-host.sh`: Performs a non-destructive inventory of the host system. Verifies the presence of required compilers (`gcc`, `clang`, `aarch64-linux-gnu-gcc`), `dtc`, and kernel build dependencies. Supports `--dt-only` and `--kernel` target validation.
- `configure-glymur-build.sh`: Wraps the kernel config step. Starting from an ARM64 `defconfig`, it ensures essential Glymur generic symbols (`CONFIG_QCOM_CPUCP_MBOX`, `CONFIG_INTERCONNECT_QCOM_GLYMUR`, `CONFIG_PINCTRL_GLYMUR`) are validated or applied.
- `fetch-upstream-series.sh`: Retrieves the raw reference patch series from upstream ML archives (e.g. `lkml.iu.edu`) and safely stores them in `.work/patches`.
- `build-mainline.sh`: Executes an out-of-tree build of the mainline `glymur-crd.dtb` (and optionally the kernel `Image`), tracking exact provenance and configuration.
- `build-qcom-next.sh`: Compiles Qualcomm's pinned integration kernel with its `prune.config`, `qcom.config`, and published Debian image-recipe fragments. Pass `--source`, `--recipes`, and `--out` for WSL checkouts; default parallelism is two jobs. Its CRD DTB is for build validation only, never an HP boot artifact.
- `build-reference-dtbs.sh`: Executes out-of-tree builds for the EliteBook X G2q and OmniBook Ultra reference DTBs using the dedicated `.work/` branch worktrees.
- `analyze-day0-capture.py`: Validates a Day-0 hardware capture directory by verifying SHA-256 hashes from `SHA256SUMS.tsv`, cross-referencing PnP device IDs and firmware filenames against known candidates, and generating `analysis/day0-summary.md` and `analysis/dts-evidence-gate.md`.
- `analyze-acpi-pdc.py`: Reads a private iasl-disassembled DSDT and derives `GIO0` PDC pseudo-pin mappings from `_CRS` and `CIPR` without changing firmware. Run `python3 scripts/linux/test-analyze-acpi-pdc.py` for synthetic parser tests.
- `analyze-hp-packages.sh`: Inventories `.inf` files within an extracted HP SoftPaq directory using `parse-windows-inf.py`, then searches for subsystem-relevant string tokens (e.g., `glymur`, `C7700`, `ADSP`). Writes results to `.work/hp-software/manifests/<pkg_id>-analysis.txt`.
- `build-day0-kit.py`: Assembles a self-contained Day-0 capture kit ZIP containing the Windows capture scripts, candidates JSON, a README, and a `MANIFEST.tsv` with SHA-256 hashes. Output is placed in `.work/releases/`.
- `fetch-hp-packages.sh`: Downloads HP SoftPaq packages listed in `reference/hp-software/d3zn3ua-packages.tsv`. Supports `--list`, `--download <softpaq>`, and `--download-all`. Validates SHA-256 hashes when available and detects HTML error pages.
- `generate-day0-candidates.py`: Reads `reference/hp-software/hardware-id-candidates.tsv` and `firmware-candidates.tsv`, then generates `scripts/windows/day0-candidates.json` for use by the Windows Day-0 capture script.
- `import-hp-package.sh`: Imports a locally obtained HP SoftPaq file into `.work/hp-software/`, extracts it using `7z`, `cabextract`, `bsdtar`, or `unzip`, generates a manifest JSON, and hands off to `analyze-hp-packages.sh` for INF analysis.
- `parse-windows-inf.py`: Parses a single Windows `.inf` driver file (UTF-16 or UTF-8) and extracts provider, class, GUID, driver version, hardware IDs, service names, and firmware file references.
- `promote-hp-analysis.py`: Reviews new INF-derived hardware and firmware candidates without writing by default. Run with `--apply` only after checking the dry-run counts; it preserves existing canonical TSV rows. `test-promote-hp-analysis.py` verifies dry-run, merge, and idempotence on temporary data.
- `verify-day0-kit.py`: Verifies a built Day-0 kit directory by checking `MANIFEST.tsv` hashes and ensuring no forbidden file extensions (`.exe`, `.sys`, `.dll`, `.mbn`, `.elf`, `.bin`, `.dtb`, `.dts`, `.dtsi`) are present.
- `glymur-live-collector.sh`: Runs on a Linux live boot and writes diagnostic evidence to the installer FAT32 partition when writable. Version 2 completed the September 25 capture; later driver-link reporting changes are syntax-tested but not target-tested.
- `glymur-system-inventory.sh`: Default-off RAM-live collector for whole-system GPU, Wi-Fi, Bluetooth, audio, power, USB-C, and service evidence. It verifies the installer's serial, saves checkpoints, then makes one exact-ID, hash-verified QCC2072 firmware retry in RAM; it writes no internal disk. See `docs/system-inventory-live-test.md`.
- `qcom0f10-inspect/`: Out-of-tree, opt-in AArch64 module for read-only inspection of this HP's keyboard and touchpad I²C controller registers under the captured Ubuntu live kernel. It registers no I²C adapter; see `docs/qcom0f10-inspection.md`.
- `glymur-qcom0f10-inspect.sh`: Focused live USB collector that checks the module hash and kernel version, syncs a marker, loads the inspection module, and saves kernel logs. It is not part of the normal live boot.
- `qcom0f10-snapshot/`: Separate default-off, read-only GENI timing/status module for the same two controllers. It does not register an I²C adapter; its September 25 live test completed.
- `glymur-qcom0f10-snapshot.sh`: Follow-up collector that pins the Ubuntu kernel and module hash before a read-only snapshot. It is staged only in a separate optional GRUB entry; the normal Ubuntu boot remains unchanged.

- `ath12k-board-add.py`: appends one named board-data ELF to a copy of an ath12k `board-2.bin`, refusing duplicates and checking the round trip. Its output holds Windows-derived data and stays in `.work/`.
- `glymur-acpi-input/`: keyboard/touchpad bring-up kit for the stock Ubuntu `7.0.0-30-generic` live kernel. It contains:
    - `glymur_acpi_gpio.c`: a default-off ACPI TLMM GPIO/IRQ driver with PDC pin translation and a pin allow-list.
    - `derive-geni-i2c.py`: derives an ACPI-only GENI I²C driver from the v7.0 `i2c-qcom-geni.c`, SHA-256 checked. The delta is in `glymur_geni_i2c-vs-v7.0.diff`.
    - `build.sh`: builds both modules against the headers.
    - `make-kit.sh`: pins the module hashes into `glymur-acpi-input-test.sh`, the staged collector.
    - `glymur-input-counter.py`: records event-type counts only.

    - `glymur-live-desktop-setup.sh` with `desktop-grub-entry.cfg`: an interactive live desktop that loads the same modules and Wi-Fi, masks suspend, and starts GNOME.

    See `docs/acpi-input-test-2026-09-26.md` and `docs/acpi-input-results-run2-2026-09-26.md`.

## Rules

- Build and analysis scripts do not install packages. The live collector may remount the installer media writable and writes logs there.
- No script uses `sudo`.
- All outputs (clones, logs, patches, `.config`, and compiled artifacts) are placed inside `.work/`.
- Target OmniBook 5 compilation is strictly isolated from this generic validation suite.
