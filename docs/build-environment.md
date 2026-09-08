# Build Environment

Research / Build Snapshot: 2026-09-08 13:30 UTC

## Host Information
- **OS:** Fedora Linux 44 (Workstation Edition)
- **Kernel:** Linux 7.1.13-200.fc44.x86_64 #1 SMP PREEMPT_DYNAMIC
- **Architecture:** x86_64

## Build Strategy

Host currently provides the necessary dependencies. The environment is now capable of compiling the reference builds.

## Toolchain Capabilities

- **GCC ARM64:** READY
- **LLVM ARM64:** READY
- **DT compilation:** READY
- **Kernel Image build:** READY

## Fedora 44 Toolchain Packages

Host currently provides the following packages for the full GCC + LLVM development toolchain:

```text
gcc-aarch64-linux-gnu dtc flex bison bc openssl-devel elfutils-libelf-devel ncurses-devel pkgconf-pkg-config zlib-ng-compat-devel dwarves clang lld llvm b4 ShellCheck
```

## Mainline Kernel Source Baseline

- **Upstream Remote:** `https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git`
- **Current HEAD SHA:** `28924df2a08f440c73991b83028032c901de2ae4`
- **Commit Date:** Mon Sep 7 10:26:56 2026 -0700
- **Git Describe:** `v7.3-rc2-6-g28924df2a`

## Target Config Strategy

**Why we are not creating an OmniBook 5 config yet**
The target machine has not arrived, and a board-specific DTS does not yet exist. Current config work is only for generic Glymur/reference validation. Target config requirements will be derived after Day-0 evidence collection and first target DTS construction. No `omnibook5_defconfig` or similar target config will be created in this phase.

## Build parallelism and memory limits

- simultaneous full GCC and LLVM ARM64 Image builds exhausted available memory;
- the machine/container restarted;
- sequential builds with reduced parallelism completed successfully;
- this was a host-resource issue, not a kernel build failure.
