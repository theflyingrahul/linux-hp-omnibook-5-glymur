# Upstream Status

Research snapshot: 2026-09-08 11:34 UTC
Mainline commit: 28924df2a08f440c73991b83028032c901de2ae4
Mainline commit date: 2026-09-08

## Current Mainline Baseline

The main Glymur SoC baseline and CRD support are present in Linus's tree as of the research snapshot. Additional generic support required for some OEM-board functionality remains pending.

## Reference Series Status

| Series | Latest revision | Posted Date | Acceptance Status | Known Dependencies |
|---|---|---|---|---|
| HP EliteBook X G2q 14 AI | v5 | 2026-08-29 | **Partially Applied**. Patches 1/3 (bindings) and 2/3 (DTS) applied to maintainer tree by Bjorn Andersson. Patch 3/3 applied to QSEECOM allowlist (`665d237915193b06d3026da367040e4a4f3356ba`). | **Runtime:** Glymur DP PHY series. DTB builds without it. DisplayPort Alt Mode does not work without it. |
| HP OmniBook Ultra 14-kg0xxx | v1 | 2026-08-30 | **Under review**. Received substantive review comments from Abel Vesa and Konrad Dybcio; no application to a maintainer tree located as of the research snapshot. | **Compile:** Glymur PCIe3 support (required because its NVMe path uses `pcie3b`).<br>**Runtime:** Glymur DP/QMP combo PHY work. DTB can build/boot without it, but DisplayPort output requires it. |

*Note: Earlier dependencies for EliteBook such as Audio, GPU, and SoCCP have since merged into mainline and are no longer pending.*

## Generic Glymur Dependencies Still Pending

Based on the reference patch cover letters, the following generic Glymur SoC features remain out of tree:
1. **PCIe3 PHY / PCIe3a controllers:** Pending (Needed by OmniBook Ultra 14-kg0xxx v1 for NVMe root disk; compile-time dependency).
2. **QMP-combo DisplayPort PHY table updates:** Pending (Needed for Type-C DP Alt Mode; runtime dependency).

## Kernel Config Requirements

Based on the cover letters and mainline configurations:
- `CONFIG_QCOM_CPUCP_MBOX=y` (Built-in required: explicitly required for SCMI on Glymur).
- `CONFIG_INTERCONNECT_QCOM_GLYMUR=y` (Required: SoC interconnect driver).
- `CONFIG_PINCTRL_GLYMUR=y` (Required: Pinctrl).

## Build Dependency Matrix

- **IN MAINLINE:** Base `glymur.dtsi`, SCMI, SoCCP, Audio (LPASS), GPU/GMU.
- **MAINTAINER TREE:** HP EliteBook X G2q v5 board support.
- **PENDING (COMPILE):** Glymur PCIe3 PHY and controller support.
- **PENDING (RUNTIME):** Glymur DisplayPort/QMP combo PHY updates.
