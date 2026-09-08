# Reference Build Reproducibility Record

Research snapshot: 2026-09-08 12:51 UTC

## MAINLINE CRD
- **Source SHA:** `28924df2a08f440c73991b83028032c901de2ae4`
- **Config Basis:** `defconfig`
- **Config Adjustments:** Script verifies `CONFIG_QCOM_CPUCP_MBOX=y`, `CONFIG_INTERCONNECT_QCOM_GLYMUR=y`, `CONFIG_PINCTRL_GLYMUR=y`
- **Compiler:** `gcc` / `aarch64-linux-gnu-gcc`
- **dtc:** (Unavailable on host)
- **Make Command:** `make -C .work/linux-mainline O=../build/mainline ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- qcom/glymur-crd.dtb`
- **Result:** `BLOCKED` (Toolchain unavailable)
- **Warnings:** None (Build not run)
- **Output Artifact:** None
- **Artifact SHA256:** N/A

## ELITEBOOK X G2q v5
- **Source/Base SHA:** `28924df2a08f440c73991b83028032c901de2ae4`
- **Patch Message-IDs:** `20260829-glymur-send-v5-0-a11bdf6a4b66`
- **Dependency Series:** None required for compile
- **Generated Commit SHAs:** N/A (Patch application failed)
- **Compiler:** `gcc` / `aarch64-linux-gnu-gcc`
- **Config:** `defconfig` + generic Glymur symbols
- **Result:** `BLOCKED` (Patch application failed due to mangled HTML archive retrieval; Toolchain unavailable)
- **Warnings:** `patch fragment without header`
- **Artifact SHA256:** N/A
- **DP PHY Present:** No (Runtime dependency only, not required for compilation)

## OMNIBOOK ULTRA v1
- **Source/Base SHA:** `28924df2a08f440c73991b83028032c901de2ae4`
- **Patch Message-IDs:** `12244.html` (LKML)
- **PCIe3 Dependency:** `20260825-glymur_linkmode_0826-v10-0-56ab597d77e4`
- **DP PHY Dependency Present:** No (Runtime dependency only, not required for compilation)
- **Result Before PCIe3 Dependency:** `BLOCKED` (Would fail to compile due to missing `pcie3b` label, and Toolchain is unavailable)
- **Result After PCIe3 Dependency:** `BLOCKED` (Patch application failed due to mangled HTML archive retrieval; Toolchain unavailable)
- **Compiler:** `gcc` / `aarch64-linux-gnu-gcc`
- **Config:** `defconfig` + generic Glymur symbols
- **Warnings:** None (Build not run)
- **Artifact SHA256:** N/A
