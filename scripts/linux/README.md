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

## Boot kernel, Mesa and profiles

### `prepare-qcom-next-glymur.sh`

    prepare-qcom-next-glymur.sh <qcom-next-clone> <new-worktree> [repo-root]

Creates a qcom-next worktree at the pinned `BASE` and applies the layered
series in order:
1. `patches/kernel/upstream/qcom-next-acpi/`
2. `upstream/qcom-next/`
3. `glymur-bringup/`
4. `backports/` (one mainline fix touches a file the bring-up layer also
   changes)

See `patches/README.md`.

### `build-qcom-next-glymur.sh`

    GLYMUR_SUFFIX=-N build-qcom-next-glymur.sh <source> <out> [jobs]

Builds the boot kernel for the SSD root, from `~/glymur-build` in WSL or
natively on the SSD install.
- **No initramfs.** The only initrd is the early ACPI-table cpio, so NVMe,
  ext4 and the PCI/ACPI host path are built in, and so is everything between
  the kernel and the NVMe root on a device-tree boot:
    - clock, pin and interconnect controllers;
    - TCSR reference clocks;
    - the QMP PCIe PHY.
- **GPU clock controllers.** `gpucc-glymur` and `gxclkctl` are built in, so
  the GPU SMMU and GMU don't wait past the deferred-probe timeout.
- **Config.** Ubuntu's `config-7.0.0-30-generic`, then
  `arch/arm64/configs/qcom.config`, then the script's own `glymur.config`.
  The build refuses to continue if a required symbol didn't survive
  `olddefconfig`.
- **Release name.** `GLYMUR_SUFFIX` gives each build its own release
  (`7.3.0-rc2-glymur-N`), so installing it never replaces the running
  kernel's modules. An empty `LOCALVERSION` keeps the release exact.
- **Device trees.** The HP DTBs from `dts/qcom/` are compiled against the
  tree's `mahua.dtsi` and shipped in `stage/dtbs/qcom/`. Each one must pass
  `check-dt-gpio-allowlist.py`. Lab and test DTBs are built by
  `glymur-lab/`.

### `setup-native-kernel-build.sh`

    bash scripts/linux/setup-native-kernel-build.sh [src-root]

Prepares a kernel build on the laptop itself, with no Windows round trip. It
never runs sudo.
1. It checks the build prerequisites and prints the `apt` command for any
   that are missing.
2. It shallow-fetches qcom-next at `BASE` into `<src-root>/linux-qcom-next`
   (default `~/src`, about 250 MB).
3. It applies the series in `<src-root>/linux-qcom-next-glymur`.

Then build and install:

    GLYMUR_SUFFIX=-N bash scripts/linux/build-qcom-next-glymur.sh ~/src/linux-qcom-next-glymur ~/src/build-glymur "$(nproc)"
    sudo bash scripts/linux/glymur-ssd/install-kernel.sh ~/src/build-glymur

### `build-mesa-glymur.sh`

    scripts/linux/build-mesa-glymur.sh <work dir> [jobs]

Builds upstream Mesa for the Adreno X2-85 on Ubuntu 26.04 arm64. It includes
freedreno (OpenGL), turnip (Vulkan), softpipe and llvmpipe. Ubuntu's Mesa
26.0.8 has no entry for chip `0x44070031`; Mesa 26.2 does.
- **llvmpipe** links against Ubuntu's LLVM 21, so this Mesa can serve the
  whole system, including boots without the GPU.
- **No root and no `apt install`.** Dependencies are fetched with
  `apt-get download`, using a private copy of the package lists, and
  unpacked into a sysroot.
    - Absolute and dangling symlinks there are retargeted to the sysroot or
      the host.
    - Static archives are removed, so a missing shared library fails the
      build instead of silently linking statically.
- **LLVM.** The sysroot's `llvm-config` is used if apt unpacked one, the
  host's otherwise, and it must be LLVM 21.
- **Packaging.**
    - Only the runtime is packaged: headers, pkgconfig and meson's
      libarchive fallback are removed.
    - The only LLVM dependency must be `libLLVM.so.21.1`.
    - Output: `mesa-glymur-<version>-<rev>.tar.gz`, installed by
      `glymur-ssd/install-mesa.sh`.
    - Revisions: `-1` had freedreno, turnip and softpipe; `-2` adds llvmpipe.

### `fan-thermal-profile.sh`

    [POWER_SOURCE=battery|ac] fan-thermal-profile.sh [out-dir]

The twin of `scripts/windows/fan-thermal-profile.ps1`: the same phases (60 s
idle, 60 s with every CPU busy, 120 s recovery), a 5 s interval and the same
TSV columns, so the two runs compare row by row.
- It samples the `acpi_fan` RPM (read from the EC over IC10), every thermal
  zone, CPU use, cpufreq and the AC state.
- `acpitz` zones carry their ACPI path (`\_SB_.TZ31` is "EC thermistor 1"),
  which matches the Windows instance names.
- Pass `POWER_SOURCE` by hand, because Linux cannot see the AC state yet.

## Rules

- Build and analysis scripts do not install packages. The live collector may remount the installer media writable and writes logs there.
- No script uses `sudo`.
- All outputs (clones, logs, patches, `.config`, and compiled artifacts) are placed inside `.work/`.
- Target OmniBook 5 compilation is strictly isolated from this generic validation suite.
