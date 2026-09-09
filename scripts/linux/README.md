# Linux Build Scripts

This directory contains shell scripts for validating the build environment, retrieving reference patches, and reproducibly building reference device trees (DTBs) out-of-tree.

## Scripts Overview

- `check-build-host.sh`: Performs a non-destructive inventory of the host system. Verifies the presence of required compilers (`gcc`, `clang`, `aarch64-linux-gnu-gcc`), `dtc`, and kernel build dependencies. Supports `--dt-only` and `--kernel` target validation.
- `configure-glymur-build.sh`: Wraps the kernel config step. Starting from an ARM64 `defconfig`, it ensures essential Glymur generic symbols (`CONFIG_QCOM_CPUCP_MBOX`, `CONFIG_INTERCONNECT_QCOM_GLYMUR`, `CONFIG_PINCTRL_GLYMUR`) are validated or applied.
- `fetch-upstream-series.sh`: Retrieves the raw reference patch series from upstream ML archives (e.g. `lkml.iu.edu`) and safely stores them in `.work/patches`.
- `build-mainline.sh`: Executes an out-of-tree build of the mainline `glymur-crd.dtb` (and optionally the kernel `Image`), tracking exact provenance and configuration.
- `build-reference-dtbs.sh`: Executes out-of-tree builds for the EliteBook X G2q and OmniBook Ultra reference DTBs using the dedicated `.work/` branch worktrees.
- `analyze-day0-capture.py`: Validates a Day-0 hardware capture directory by verifying SHA-256 hashes from `SHA256SUMS.tsv`, cross-referencing PnP device IDs and firmware filenames against known candidates, and generating `analysis/day0-summary.md` and `analysis/dts-evidence-gate.md`.
- `analyze-hp-packages.sh`: Inventories `.inf` files within an extracted HP SoftPaq directory using `parse-windows-inf.py`, then searches for subsystem-relevant string tokens (e.g., `glymur`, `C7700`, `ADSP`). Writes results to `.work/hp-software/manifests/<pkg_id>-analysis.txt`.
- `build-day0-kit.py`: Assembles a self-contained Day-0 capture kit ZIP containing the Windows capture scripts, candidates JSON, a README, and a `MANIFEST.tsv` with SHA-256 hashes. Output is placed in `.work/releases/`.
- `fetch-hp-packages.sh`: Downloads HP SoftPaq packages listed in `reference/hp-software/d3zn3ua-packages.tsv`. Supports `--list`, `--download <softpaq>`, and `--download-all`. Validates SHA-256 hashes when available and detects HTML error pages.
- `generate-day0-candidates.py`: Reads `reference/hp-software/hardware-id-candidates.tsv` and `firmware-candidates.tsv`, then generates `scripts/windows/day0-candidates.json` for use by the Windows Day-0 capture script.
- `import-hp-package.sh`: Imports a locally obtained HP SoftPaq file into `.work/hp-software/`, extracts it using `7z`, `cabextract`, `bsdtar`, or `unzip`, generates a manifest JSON, and hands off to `analyze-hp-packages.sh` for INF analysis.
- `parse-windows-inf.py`: Parses a single Windows `.inf` driver file (UTF-16 or UTF-8) and extracts provider, class, GUID, driver version, hardware IDs, service names, and firmware file references.
- `promote-hp-analysis.py`: Reads a cleaned HP package analysis manifest and promotes extracted hardware IDs and firmware references into the canonical `reference/hp-software/hardware-id-candidates.tsv` and `firmware-candidates.tsv` files.
- `verify-day0-kit.py`: Verifies a built Day-0 kit directory by checking `MANIFEST.tsv` hashes and ensuring no forbidden file extensions (`.exe`, `.sys`, `.dll`, `.mbn`, `.elf`, `.bin`, `.dtb`, `.dts`, `.dtsi`) are present.

## Rules

- No script modifies the host system or installs packages.
- No script uses `sudo`.
- All outputs (clones, logs, patches, `.config`, and compiled artifacts) are placed inside `.work/`.
- Target OmniBook 5 compilation is strictly isolated from this generic validation suite.
