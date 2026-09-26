# Reference Build Reproducibility Record

Validation snapshot: 2026-09-14

## Build History
- **Phase 2:** build blocked — toolchain absent
- **Phase 2.1:** patch retrieval/application repaired
- **Phase 2.2:** actual compilation result (recorded below)

## Build Validation Summary

| Board/stack | Patch application | GCC DTB | LLVM DTB | Runtime tested | Notes |
|---|---|---|---|---|---|
| Mainline Glymur CRD | PASS (N/A) | PASS | PASS | NOT TESTED | Validated at `704340f1cd0d…` |
| EliteBook v5 without DP PHY | PASS | PASS | PASS | NOT TESTED | Confirms DP PHY is not a compile dependency |
| OmniBook Ultra v1 without PCIe3 | PASS | EXPECTED FAIL | NOT RUN | NOT TESTED | Fails on missing `pcie3_phy` label |
| OmniBook Ultra v1 + PCIe3 | PASS | PASS | PASS | NOT TESTED | Confirms PCIe3 compile dependency |
| OmniBook Ultra v1 + PCIe3 + DP PHY | PASS (historical) | PASS (historical) | NOT RUN | NOT TESTED | Retained from the earlier validation snapshot |

## MAINLINE CRD
- **Source SHA:** `704340f1cd0dcef829eb62f5b48ae95a2ce17bdf`
- **Config Basis:** `defconfig`
- **Config Adjustments:** Script verifies `CONFIG_QCOM_CPUCP_MBOX=y`, `CONFIG_INTERCONNECT_QCOM_GLYMUR=y`, `CONFIG_PINCTRL_GLYMUR=y` (Script predictably transitioned `CONFIG_QCOM_CPUCP_MBOX` from `m` to `y`)
- **LOCAL DTB COMPILATION:** `PASS` with GCC and LLVM.
- **LOCAL GCC IMAGE COMPILATION:** `PASS` with `--jobs 2`.
- **GCC IMAGE SHA256:** `0e13b99aae1e71b0e778b34bbdff24ecfea63a39d2945b8565adf5be49f6fe0e`
- **RUNTIME STATUS:** `NOT TESTED`

## ELITEBOOK X G2q v5
- **Source/Base SHA:** `704340f1cd0dcef829eb62f5b48ae95a2ce17bdf`
- **SOURCE CLAIM:** Pending DP PHY v3 is a runtime-only dependency.
- **LOCAL PATCH APPLICATION:** `PASS`
- **LOCAL COMPILATION (Without DP PHY):** `PASS`. This locally reproduces the claim that the pending DP PHY series is not a compile-time dependency for the EliteBook DTB.
- **RUNTIME STATUS:** `NOT TESTED`

## OMNIBOOK ULTRA v1
- **Source/Base SHA:** `704340f1cd0dcef829eb62f5b48ae95a2ce17bdf`
- **SOURCE CLAIM:** PCIe3 v10 is a compile-time dependency. DP PHY v3 is a runtime-only dependency.
- **LOCAL PATCH APPLICATION (Without PCIe3):** `PASS`
- **LOCAL COMPILATION (Without PCIe3):** `EXPECTED FAIL` (`Error: ...:601.1-11 Label or path pcie3_phy not found`)
- **LOCAL PATCH APPLICATION (With PCIe3):** `PASS`
- **LOCAL COMPILATION (With PCIe3):** `PASS`. Locally reproduces that PCIe3 v10 is a compile-time dependency of the OmniBook Ultra v1 reference DTS on this baseline.
- **LOCAL PATCH APPLICATION (With PCIe3, 3-way):** `PASS` on newest mainline
- **LOCAL DTB COMPILATION (With PCIe3):** `PASS` with GCC and LLVM
- **RUNTIME STATUS:** `NOT TESTED`
