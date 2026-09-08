# Linux Build Scripts

This directory contains shell scripts for validating the build environment, retrieving reference patches, and reproducibly building reference device trees (DTBs) out-of-tree.

## Scripts Overview

- `check-build-host.sh`: Performs a non-destructive inventory of the host system. Verifies the presence of required compilers (`gcc`, `clang`, `aarch64-linux-gnu-gcc`), `dtc`, and kernel build dependencies. Supports `--dt-only` and `--kernel` target validation.
- `configure-glymur-build.sh`: Wraps the kernel config step. Starting from an ARM64 `defconfig`, it ensures essential Glymur generic symbols (`CONFIG_QCOM_CPUCP_MBOX`, `CONFIG_INTERCONNECT_QCOM_GLYMUR`, `CONFIG_PINCTRL_GLYMUR`) are validated or applied.
- `fetch-upstream-series.sh`: Retrieves the raw reference patch series from upstream ML archives (e.g. `lkml.iu.edu`) and safely stores them in `.work/patches`.
- `build-mainline.sh`: Executes an out-of-tree build of the mainline `glymur-crd.dtb` (and optionally the kernel `Image`), tracking exact provenance and configuration.
- `build-reference-dtbs.sh`: Executes out-of-tree builds for the EliteBook X G2q and OmniBook Ultra reference DTBs using the dedicated `.work/` branch worktrees.

## Rules

- No script modifies the host system or installs packages.
- No script uses `sudo`.
- All outputs (clones, logs, patches, `.config`, and compiled artifacts) are placed inside `.work/`.
- Target OmniBook 5 compilation is strictly isolated from this generic validation suite.
