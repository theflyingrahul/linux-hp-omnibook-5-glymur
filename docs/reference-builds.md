# Reference Build Reproducibility Record

Research snapshot: 2026-09-08 13:30 UTC

## Build History
- **Phase 2:** build blocked — toolchain absent
- **Phase 2.1:** patch retrieval/application repaired
- **Phase 2.2:** actual compilation result (recorded below)

## Build Validation Summary

| Board/stack | Patch application | GCC DTB | LLVM DTB | Runtime tested | Notes |
|---|---|---|---|---|---|
| Mainline Glymur CRD | PASS (N/A) | PASS | PASS | NOT TESTED | Generated DTBs byte-identical |
| EliteBook v5 without DP PHY | PASS | PASS | PASS | NOT TESTED | Confirms DP PHY is not a compile dependency |
| OmniBook Ultra v1 without PCIe3 | PASS | EXPECTED FAIL | NOT RUN | NOT TESTED | Fails exactly as predicted due to missing `pcie3b` label |
| OmniBook Ultra v1 + PCIe3 | PASS | PASS | PASS | NOT TESTED | Confirms PCIe3 compile dependency |
| OmniBook Ultra v1 + PCIe3 + DP PHY | PASS | PASS | NOT RUN | NOT TESTED | Confirms DP PHY is runtime-only |

## MAINLINE CRD
- **Source SHA:** `28924df2a08f440c73991b83028032c901de2ae4`
- **Config Basis:** `defconfig`
- **Config Adjustments:** Script verifies `CONFIG_QCOM_CPUCP_MBOX=y`, `CONFIG_INTERCONNECT_QCOM_GLYMUR=y`, `CONFIG_PINCTRL_GLYMUR=y` (Script predictably transitioned `CONFIG_QCOM_CPUCP_MBOX` from `m` to `y`)
- **LOCAL COMPILATION:** `PASS` (GCC and LLVM). DTB artifacts are byte-identical.
- **GCC IMAGE SHA256:** `0f182dfe9c09d2b22da87a6d64bd1211419e4411cb434e36e0681b32d3bbb686`
- **LLVM IMAGE SHA256:** `8782b359839012db545312d224d565939d3c8e91aab867fd9ceabf0b8471c6c3`
- **RUNTIME STATUS:** `NOT TESTED`

## ELITEBOOK X G2q v5
- **Source/Base SHA:** `28924df2a08f440c73991b83028032c901de2ae4`
- **SOURCE CLAIM:** Pending DP PHY v3 is a runtime-only dependency.
- **LOCAL PATCH APPLICATION:** `PASS`
- **LOCAL COMPILATION (Without DP PHY):** `PASS`. This locally reproduces the claim that the pending DP PHY series is not a compile-time dependency for the EliteBook DTB.
- **RUNTIME STATUS:** `NOT TESTED`

## OMNIBOOK ULTRA v1
- **Source/Base SHA:** `28924df2a08f440c73991b83028032c901de2ae4`
- **SOURCE CLAIM:** PCIe3 v10 is a compile-time dependency. DP PHY v3 is a runtime-only dependency.
- **LOCAL PATCH APPLICATION (Without PCIe3):** `PASS`
- **LOCAL COMPILATION (Without PCIe3):** `EXPECTED FAIL` (`Error: ...:601.1-11 Label or path pcie3_phy not found`)
- **LOCAL PATCH APPLICATION (With PCIe3):** `PASS`
- **LOCAL COMPILATION (With PCIe3):** `PASS`. Locally reproduces that PCIe3 v10 is a compile-time dependency of the OmniBook Ultra v1 reference DTS on this baseline.
- **LOCAL PATCH APPLICATION (With PCIe3 + DP PHY):** `PASS` (Requires 3-way merge on baseline)
- **LOCAL COMPILATION (With PCIe3 + DP PHY):** `PASS`
- **RUNTIME STATUS:** `NOT TESTED`
