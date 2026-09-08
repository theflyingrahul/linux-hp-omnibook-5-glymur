# Build Environment

Research / Build Snapshot: 2026-09-08 12:51 UTC

## Host Information
- **OS:** Fedora Linux 44 (Workstation Edition)
- **Kernel:** Linux 7.1.13-200.fc44.x86_64 #1 SMP PREEMPT_DYNAMIC
- **Architecture:** x86_64

## Build Strategy

Due to the absence of `aarch64-linux-gnu-gcc`, `clang`, and `dtc` on the host system, compiling DTBs or the Kernel Image is currently **BLOCKED — toolchain unavailable**. 

## Fedora 44 Toolchain Packages

The exact package names required for Fedora 44 have been verified via `dnf repoquery`.

### Minimal GCC ARM64 Cross-Build Toolchain
This profile contains the minimum packages required to cross-compile the ARM64 kernel (`Image`) and Device Trees (`.dtb`) using GCC.

```bash
sudo dnf install gcc-aarch64-linux-gnu dtc flex bison bc openssl-devel elfutils-libelf-devel ncurses-devel pkgconf-pkg-config zlib-ng-compat-devel dwarves
```

*Package explanations:*
- `gcc-aarch64-linux-gnu`: The GNU GCC cross-compiler for ARM64 (`aarch64-linux-gnu-gcc`).
- `dtc`: Device Tree Compiler.
- `flex` / `bison`: Required for compiling Kconfig and various kernel parsers.
- `bc`: Required for kernel math operations.
- `openssl-devel`: Required for kernel certificate and module signing.
- `elfutils-libelf-devel`: Required by `objtool` for ELF manipulation.
- `ncurses-devel`: Required for `make menuconfig`.
- `pkgconf-pkg-config`: Provides `pkg-config` for dependency resolution.
- `zlib-ng-compat-devel`: Modern Fedora zlib headers for kernel tools.
- `dwarves`: Provides `pahole` for BTF generation.

### Full GCC + LLVM Development Toolchain
This profile adds LLVM/Clang support, kernel patch utilities (`b4`), and script analysis tools (`ShellCheck`).

```bash
sudo dnf install gcc-aarch64-linux-gnu dtc flex bison bc openssl-devel elfutils-libelf-devel ncurses-devel pkgconf-pkg-config zlib-ng-compat-devel dwarves clang lld llvm b4 ShellCheck
```

*Package explanations:*
- `clang` / `lld` / `llvm`: Provides LLVM cross-build capability (`make LLVM=1`).
- `b4`: Kernel patch series retrieval and management tool.
- `ShellCheck`: Static analysis tool for the repository's bash scripts.

## Mainline Kernel Source Baseline

- **Upstream Remote:** `https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git`
- **Current HEAD SHA:** `28924df2a08f440c73991b83028032c901de2ae4`
- **Commit Date:** Mon Sep 7 10:26:56 2026 -0700
- **Git Describe:** `v7.3-rc2-6-g28924df2a`

## Target Config Strategy

**Why we are not creating an OmniBook 5 config yet**
The target machine has not arrived, and a board-specific DTS does not yet exist. Current config work is only for generic Glymur/reference validation. Target config requirements will be derived after Day-0 evidence collection and first target DTS construction. No `omnibook5_defconfig` or similar target config will be created in this phase.
