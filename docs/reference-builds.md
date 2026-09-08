# Reference Build Reproducibility Record

Research snapshot: 2026-09-08 12:51 UTC

## MAINLINE CRD
- **Source SHA:** `28924df2a08f440c73991b83028032c901de2ae4`
- **Config Basis:** `defconfig`
- **Config Adjustments:** Script verifies `CONFIG_QCOM_CPUCP_MBOX=y`, `CONFIG_INTERCONNECT_QCOM_GLYMUR=y`, `CONFIG_PINCTRL_GLYMUR=y`
- **Make Command:** `make -C .work/linux-mainline O=../build/mainline ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- qcom/glymur-crd.dtb`
- **Result:** `BLOCKED` (Toolchain unavailable)

## ELITEBOOK X G2q v5
- **Source/Base SHA:** `28924df2a08f440c73991b83028032c901de2ae4`
- **Retrieval:** `PASS` (lore.kernel.org raw mbox endpoint)
- **Patch Application:** `PASS`
  - **Commit:** `4a0e27597` dt-bindings: arm: qcom: Add HP EliteBook X G2q 14 AI
  - **Commit:** `4182a093f` arm64: dts: qcom: Add HP EliteBook X G2q 14 AI
  - **Commit:** `0045f63b5` firmware: qcom: scm: Allow QSEECOM on HP EliteBook X G2q 14 AI
- **Compilation:** `BLOCKED` (Toolchain unavailable)
- **DP PHY Runtime Support:** `NOT RUN` (Runtime-only dependency; compilation untested due to blocked compiler)

*Note: Phase 2 previously resulted in retrieval blocked by bot protection yielding rendered HTML, which prevented patch application. Phase 2.1 successfully fetched raw mbox data and applied it.*

## OMNIBOOK ULTRA v1
- **Source/Base SHA:** `28924df2a08f440c73991b83028032c901de2ae4`
- **Retrieval:** `PASS` (lore.kernel.org raw mbox endpoint)
- **Patch Application Without PCIe3:** `PASS` (Commit: `6641dfc35`)
- **Compilation Without PCIe3:** `EXPECTED FROM SOURCE DEPENDENCY` (Would fail to compile due to missing `pcie3b` label; actual build blocked by toolchain absence)
- **Patch Application With PCIe3 (v10):** `PASS`
  - **Base:** `28924df2a08f440c73991b83028032c901de2ae4`
  - **PCIe3 Commits Applied:** `0bd6f1986`, `0c9c05a18`, `d547325f5`, `82a3bd7b0`
  - **OmniBook Commits Applied:** `3fcb88131`, `e53878b8f`, `79002eb42`
- **Compilation With PCIe3:** `BLOCKED` (Toolchain unavailable)
- **DP PHY Runtime Support:** `NOT RUN` (Runtime-only dependency)

*Note: As with EliteBook, Phase 2.1 successfully bypassed HTML bot protection to retrieve and validate raw patches using lore's `.mbox.gz` endpoints.*
