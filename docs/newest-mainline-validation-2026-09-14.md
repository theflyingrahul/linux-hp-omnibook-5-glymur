# Newest Mainline Validation

Validation date: 2026-09-14

## Source and host

- Linux source: `https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git`
- Validated mainline HEAD: `704340f1cd0dcef829eb62f5b48ae95a2ce17bdf`
- Build host: Ubuntu 26.04.1 LTS in WSL2, aarch64
- Intended target OS: Fedora Workstation for ARM64/aarch64
- Build outputs: `/home/login/glymur-build/.work/` in the WSL filesystem

## Results

The host prerequisite check passed. The generic Glymur CRD DTB built with both GCC and LLVM. The HP EliteBook X G2q v5 reference DTB also built with both toolchains.

The HP OmniBook Ultra reference initially failed exactly as expected because its DTS references `pcie3_phy`. After applying the PCIe3 v10 prerequisite series, its DTB built with both GCC and LLVM. The DP PHY series is a separate runtime dependency and is not needed to compile these DTBs.

The GCC ARM64 `Image` build for the unmodified mainline CRD baseline passed with `--jobs 2`. Its SHA-256 is `0e13b99aae1e71b0e778b34bbdff24ecfea63a39d2945b8565adf5be49f6fe0e`. No target-board image has been built.

Commands used:

```bash
./scripts/linux/check-build-host.sh --dt-only
./scripts/linux/build-mainline.sh --gcc --dtb-only --jobs 2
./scripts/linux/build-mainline.sh --llvm --dtb-only --jobs 2
./scripts/linux/build-reference-dtbs.sh --gcc --jobs 2
./scripts/linux/build-reference-dtbs.sh --llvm --jobs 2
```

## Target gate

No target DTS has been created. Captured ACPI identifies the WLAN on Windows PCI segment 4 and the NVMe device on segment 5. Mainline `pcie4` and `pcie5` declare matching Linux PCI domains 4 and 5, while `pcie3b` declares domain 7; this narrows the WLAN/NVMe host candidates without proving board reset, wake, PHY, regulator, or lane wiring. ACPI `_STR` values and resource bases confirm `I2C5` → mainline `i2c4` (`QUP_0_SE_4`, `0xB90000`) and `I2C9` → mainline `i2c8` (`QUP_1_SE_0`, `0xA80000`). ACPI child addresses are `0x15` and `0x10`; their Linux operation remains unresolved.

The external-port/chassis and BIOS/UEFI photographs are now reviewed and preserved privately. An Ubuntu 26.04.1 ARM64 ACPI live boot completed an automated capture without a supplied target DTB: PCI4/WLAN, PCI5/NVMe, xHCI, camera, and installer storage enumerated, while no I²C adapters or keyboard/touchpad input registered. The next target-specific gate is to capture the running kernel's I²C configuration and ACPI/platform enumeration, then evaluate both the ACPI driver path and an evidence-backed board DT route. This is a historical September 14 build result; Qualcomm's September 23 preview is reviewed in `docs/qualcomm-preview-review-2026-09-25.md`.
