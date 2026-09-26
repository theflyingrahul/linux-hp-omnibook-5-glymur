# Build Environment

Build validation snapshot: 2026-09-14

## Host and Target

- **Runtime target:** Fedora Workstation for ARM64/aarch64.
- **Build host:** Ubuntu 26.04.1 LTS in WSL2, aarch64 (`6.18.33.2-microsoft-standard-WSL2`).
- **Source location:** use a Linux-native checkout; the Windows checkout is subject to Git CRLF conversion.

Fedora is the intended installed OS. The WSL distribution is only a reproducible build host and does not determine the target DTS.

## Build Strategy

The WSL host provides the necessary dependencies and is capable of compiling the reference builds.

## Toolchain Capabilities

- **GCC ARM64:** READY
- **LLVM ARM64:** READY
- **DT compilation:** READY
- **Kernel Image build:** READY

## Toolchain Packages

The WSL host has GCC AArch64, Clang/LLVM, `dtc`, `flex`, `bison`, `bc`, `pkg-config`, `b4`, and the required kernel build utilities. Fedora equivalents include:

```text
gcc-aarch64-linux-gnu dtc flex bison bc pkgconf-pkg-config openssl-devel elfutils-libelf-devel ncurses-devel dwarves clang lld llvm b4
```

## Mainline Kernel Source Baseline

- **Upstream Remote:** `https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git`
- **Validated HEAD:** `704340f1cd0dcef829eb62f5b48ae95a2ce17bdf`
- **HEAD subject:** merge of `x86_urgent_for_7.3-rc4`
- **Validation:** generic Glymur CRD DTB passed with GCC and LLVM; the GCC ARM64 `Image` also passed with `--jobs 2`.

## Target Config Strategy

The Ubuntu ACPI boot shows that a target-specific DTB is not a prerequisite for reaching userspace. An ACPI-focused kernel configuration can be evaluated independently of a board DTS. Before building one, capture the running Ubuntu kernel's `CONFIG_I2C_QCOM_GENI` setting and ACPI/platform device enumeration. The pinned mainline checkout remains a historical build baseline, not evidence that it matches Qualcomm's September 2026 custom-kernel preview. Fedora ARM64 remains the intended runtime target.

## Build parallelism and memory limits

- Use sequential builds and `--jobs 2` on this WSL host. Do not run GCC and LLVM Image builds simultaneously.
