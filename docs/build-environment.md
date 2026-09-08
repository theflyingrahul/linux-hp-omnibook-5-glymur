# Build Environment

Research / Build Snapshot: 2026-09-08 12:51 UTC

## Host Information
- **OS:** Fedora Linux 44 (Workstation Edition)
- **Kernel:** Linux 7.1.13-200.fc44.x86_64 #1 SMP PREEMPT_DYNAMIC
- **Architecture:** x86_64

## Toolchain Inventory

| Tool | Found | Version | Required for | Notes |
|---|---|---|---|---|
| `git` | YES | 2.55.0 | REQUIRED | Source management and patch application |
| `make` | YES | 4.4.1 | REQUIRED | Kernel build system |
| `python3` | YES | 3.14.7 | OPTIONAL | Kernel scripts / helpers |
| `perl` | NO | | OPTIONAL | Some kernel build scripts |
| `bash` | YES | 5.3.9(1)-release | REQUIRED | Shell scripts |
| `clang` | NO | | OPTIONAL | LLVM build strategy |
| `ld.lld` | NO | | OPTIONAL | LLVM build strategy |
| `llvm` | NO | | OPTIONAL | LLVM build strategy |
| `gcc` | YES | 16.2.1 | REQUIRED | Host tool compilation |
| `aarch64-linux-gnu-gcc` | NO | | OPTIONAL | GCC cross-compile strategy |
| `dtc` | NO | | REQUIRED | Device Tree Compiler |
| `b4` | NO | | OPTIONAL | Patch series retrieval (fallback to curl/wget) |
| `flex` | YES | 2.6.4 | REQUIRED | Kconfig/kernel parsing |
| `bison` | YES | 3.8.2 | REQUIRED | Kconfig/kernel parsing |
| `bc` | YES | 1.08.2 | REQUIRED | Kernel math operations |
| `openssl` | YES | 3.5.8 | REQUIRED | Certificate/signing operations |
| `pahole` | YES | 1.30 | OPTIONAL | BTF generation |
| `pkg-config` | YES | 2.5.1 | REQUIRED | Dependency resolution |
| `libssl` | YES | | REQUIRED | |
| `libelf` | YES | | REQUIRED | |
| `ncurses` | YES | | OPTIONAL | menuconfig |

## Build Strategy

Due to the absence of `aarch64-linux-gnu-gcc`, `clang`, and `dtc` on the host system, compiling DTBs or the Kernel Image is currently **BLOCKED — toolchain unavailable**. Development scripts will be constructed but build commands will exit or bypass when run, rather than erroring destructively.

## Mainline Kernel Source Baseline

- **Upstream Remote:** `https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git`
- **Current HEAD SHA:** (To be recorded)
- **Commit Date:** (To be recorded)
- **Git Describe:** (To be recorded)

## Target Config Strategy

**Why we are not creating an OmniBook 5 config yet**
The target machine has not arrived, and a board-specific DTS does not yet exist. Current config work is only for generic Glymur/reference validation. Target config requirements will be derived after Day-0 evidence collection and first target DTS construction. No `omnibook5_defconfig` or similar target config will be created in this phase.
