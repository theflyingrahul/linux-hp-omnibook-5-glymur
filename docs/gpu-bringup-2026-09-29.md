# GPU Bring-Up and Kernel -5, September 29, 2026

With the eDP panel working on kernel `-4`, this stages the Adreno GPU, the
CPU frequency (SCMI) fix, and the fixes Qualcomm and mainline have landed
since our base, as kernel `7.3.0-rc2-glymur-5` with a separate "GPU test"
device tree. The full and minimal device trees keep the GPU off, so the
proven display boot stays the fallback.

## Evidence for the GPU configuration

- **The chip.** Windows binds `ACPI\VEN_QCOM&DEV_0FF5&SUBSYS_8F47103C&REV_0049`
  as "Qualcomm(R) Adreno(TM) X2-85 GPU" (driver 32.0.146.0). `glymur.dtsi`
  describes exactly that part: `qcom,adreno-44070001`, GMU
  `qcom,adreno-gmu-x285.1`. `mahua.dtsi` does not override it.
- **Windows treats both dies' GPUs alike.** HP's `qcdx8480.inf` installs
  both `DEV_0F36` and our `DEV_0FF5` through the same `..._ma_185` section,
  and our `REV_0049` falls through to the generic `DEV_0FF5` match. The
  `ma_<n>` variants differ only in a per-SKU `AcpiBaseFile`. "ma" is not
  "Mahua".
- **No zap shader.** The upstream Glymur laptops (ASUS Zenbook A16, HP
  EliteBook X G2q, HP OmniBook Ultra 14) only set `&gpu` and `&gmu` to
  `okay`, with no `zap-shader` node. msm then logs "Zap shader not enabled -
  using SECVID_TRUST_CNTL instead", and the Zenbook reports a working GPU.
  No HP-signed firmware is needed.
- **Firmware.** The msm catalog entry for `0x44070001` requests
  `qcom/gen80100_sqe.fw` and `qcom/gen80100_gmu.bin`. linux-firmware ships
  both (GMU v5.02.26, SQE v1.00; WHENCE "adreno - Qualcomm Adreno GPU
  firmware", redistributable). The files fetched from gitlab.com and
  git.kernel.org are identical:
    - SQE `bfcc5193…b258`
    - GMU `dae72587…4d20`
- **Clocks.** The driver reads the chip's speed-bin fuse
  (`ADRENO_QUIRK_SOFTFUSE`). The X2-85 bins are fuse 388, 357 and 284,
  apparently 1.85, 1.70 and 1.35 GHz; an unknown fuse falls back to bin 0.
  For this first bring-up the test DT also deletes the three OPPs above
  1.35 GHz, which every bin supports.
- **Upstream validation.** Qualcomm's `mahua-crd.dts` is still a stub (it
  only touches `&tcsr`), so GPU-on-Mahua has no upstream validation. This
  is the first test.

## What kernel -5 changes

- **New base:** qcom-next `e428097a36d`, the tip on 2026-09-28, replacing
  `a47c4c5aa`. Its 6 new commits are Shikra board DTs and one audio fix
  (the audioreach channel-map revert). `qcom-next-staging` is plain 7.3-rc4
  and adds nothing Qualcomm-specific for us.
- **Backports `0003`–`0012`** (`patches/README.md`):
    - the PUSH_IDLE reset fix, ported to qcom-next's MST code;
    - seven mainline drm/msm fixes from 7.3-rc3..rc5, four of them for the
      Adreno GPU: GMU firmware init timeout, PAS check only with a zap
      shader, autosuspend teardown, RCU-freed ring/VM;
    - hci_qca and GENI I²C DMA fixes.

  The GENI I²C clock-index fix is deliberately not taken.
- **Config:** `CONFIG_CLK_GLYMUR_GPUCC=y`, which builds gpucc-glymur and
  gxclkctl in, so the GPU SMMU and GMU are not left waiting on a module.
- **Device trees:**
    - the shared dtsi now also disables `gpucc`, `gxclkctl` and
      `adreno_smmu` (before `-5` they had no driver and failed to probe);
    - `mahua-hp-omnibook-5-bf1xxx-gpu.dts` turns the whole GPU block on,
      caps the GPU at 1.35 GHz, and adds `arm,no-completion-irq` to
      `/firmware/scmi`: the upstream SCMI polling fix, which leaves
      `scmi-cpufreq` still unloaded until asked.
- **Reproducibility:** a fresh `prepare-qcom-next-glymur.sh` worktree
  equals the `-5` build tree's source (regular files; symlinks unchanged).

## Why qcom-next plus backports, not a newer mainline kernel

Mainline 7.3-rc5 (2026-09-27) already has the Glymur/Mahua basics this
laptop uses: `glymur.dtsi`/`mahua.dtsi`, battery over PMIC GLink, SoCCP,
the eDP PHY, dispcc/gpucc, the X2-85 catalog entry and the UCSI quirk. It
lacks only DP MST. qcom-next is still a superset in the files that matter,
counting lines present in one tree but not the other:

| File | Only in qcom-next | Only in mainline |
|---|---|---|
| `glymur.dtsi` | 1007 (camera, PCIe3, SD, video, CPUCP mailbox, power limits…) | 10 |
| `mahua.dtsi` | 89 | 0 |
| `qcom_battmgr.c` | 471 | 12 |
| `qcom_q6v5_pas.c` | 134 | 8 |
| `a6xx_catalog.c` | 369 | 33 |

A mainline base would mean forward-porting Qualcomm's pending work. The
backports are only the mainline fixes qcom-next has not absorbed yet, and
they drop out when Qualcomm rebases qcom-next. Refresh the pin whenever
qcom-next moves.

## Staged (USB `glymur-tools/kernels/`)

- `glymur-kernel-7.3.0-rc2-glymur-5.tar.gz` (SHA-256 `afaefcfa…77e6`), with
  the full, minimal and GPU test DTBs;
- `gpu-fw/qcom/gen80100_{sqe.fw,gmu.bin}` and `install-gpu-firmware.sh`,
  which checks the hashes above;
- `check-gpu-test.sh`, `install-kernel.sh` and `SHA256SUMS`;
- the GRUB entry "Ubuntu on SSD: device tree (GPU test)". The `grub.cfg`
  backup is `.work/grub-before-kernel5-20260929.cfg`.

## Test plan (one boot after install)

1. From "Ubuntu on SSD: ACPI, newest glymur kernel", run
   `bash "/media/$USER/UBUNTU 26_0/glymur-tools/kernels/install-from-usb.sh"`
   as your normal user. It checks `SHA256SUMS`, installs the `-5` kernel
   and the GPU firmware, and copies `check-gpu-test.sh` to `~`.
2. Boot "Ubuntu on SSD: device tree (GPU test)".
3. At the desktop, run `sudo bash check-gpu-test.sh --charging`, and then,
   with nothing unsaved, `--cpufreq`. Results go to
   `/var/log/glymur/gpu-test-*.txt`.

If the panel stays dark, the GPU failed to bind and took the display with
it (msm binds them together). Wait three minutes, power off, boot "device
tree (full)", and read `journalctl -k -b -1`.
