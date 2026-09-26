# Upstream Status

Research snapshot: 2026-09-14

This is a historical source/build snapshot. Qualcomm announced a Snapdragon X2
early developer preview on 2026-09-23 using Debian 13 and a custom kernel on
reference hardware; see `docs/qualcomm-preview-review-2026-09-25.md` before
treating this mainline/reference matrix as current HP laptop support.
Mainline commit: 704340f1cd0dcef829eb62f5b48ae95a2ce17bdf
Mainline HEAD subject: merge of `x86_urgent_for_7.3-rc4`

## Current Mainline Baseline

The main Glymur SoC baseline and CRD support are present in Linus's tree at the validated HEAD. The generic PCIe3 and DisplayPort PHY series remain local prerequisites for reference-board work; they are not target-board evidence.

## Reference Series Status

| Series | Latest revision | Posted Date | Acceptance Status | Known Dependencies |
|---|---|---|---|---|
| HP EliteBook X G2q 14 AI | v5 | 2026-08-29 | **Local validation PASS** on the newest mainline base. | **Runtime:** Glymur DP PHY series. DTB builds without it; DisplayPort Alt Mode remains untested. |
| HP OmniBook Ultra 14-kg0xxx | v1 | 2026-08-30 | **Local validation PASS** on the newest mainline base after applying PCIe3 v10. | **Compile:** Glymur PCIe3 support is required because its NVMe path uses `pcie3b`.<br>**Runtime:** Glymur DP/QMP combo PHY work remains separate. |

*Note: Earlier dependencies for EliteBook such as Audio, GPU, and SoCCP have since merged into mainline and are no longer pending.*

## Generic Glymur Dependencies Still Pending

The following generic Glymur SoC features remain local prerequisites for the reference stack:
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
