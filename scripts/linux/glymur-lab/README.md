# Display lab

A one-boot display lab on the SSD install (`docs/display-lab-2026-09-28.md`).
Its GRUB entry was taken off the USB menu on 2026-09-29, after its display
phase hung the laptop twice. To use it again, restore the entry from
`scripts/linux/glymur-ssd/grub-entry.cfg` at commit `7fc1d8e`. Display
changes are now tested at boot time with `build-test-dtb.sh`.

## `build-lab.sh`

    scripts/linux/glymur-lab/build-lab.sh [SRC] [OUT] [KIT]

Runs in WSL, from `~/glymur-build`, against the kernel build the SSD runs
(`7.3.0-rc2-glymur-3`). It builds and checks everything before anything
reaches the laptop:
- the display-lab DTB (with overlay symbols) and its two overlays. Each
  overlay is applied offline with `fdtoverlay`, and the merged tree must
  pass the GPIO allow-list check with the eDP pins in use;
- `glymur_lab.ko` and the instrumented `phy-qcom-edp-lab.ko`, whose vermagic
  must match the target release.

It then assembles the kit: the run scripts, HP's Bluetooth pair and
`SHA256SUMS`.

## `stage-kit.sh`, `start-lab.sh`

    bash scripts/linux/glymur-lab/stage-kit.sh [USB-KIT-DIR]
    sudo bash ~/glymur-lab-kit/start-lab.sh

A device-tree boot of the lab has no USB, so `stage-kit.sh` first copies the
kit to the SSD from an ACPI boot. `start-lab.sh` then:
- checks the kit, the running kernel and the device tree;
- copies the kit to `/run/glymur-lab`;
- starts `glymur-lab-run.sh` as the transient service `glymur-lab`, so it
  survives the desktop being stopped.

The output goes to `/var/log/glymur/lab-<time>/`.

## `glymur-lab-run.sh`

    glymur-lab-run.sh KIT_DIR OUT_DIR

Phases, all logged:
1. baseline: every subsystem as booted;
2. a read-only snapshot of the firmware's working eDP link;
3. Bluetooth: HP's Windows firmware pair against linux-firmware;
4. battery (PMIC GLink) and CPU frequency diagnostics. scmi-cpufreq only
   loads with `GLYMUR_LAB_CPUFREQ=1`, because it hung the laptop in run 1;
5. display: stop the desktop, enable the eDP path by overlay, and try
   variants until the panel trains.

How it runs:
- Every log line is flushed, so after a hard hang the last line on disk
  names the step that did it.
- Run 3 found the real failure: `phy poweron failed --> -110`, with ten PLL
  registers differing from the firmware's
  (`docs/display-lab-run3-2026-09-28.md`).
- So the variants only change the lab PHY driver's module parameters, and
  re-run link training on the bound msm. Unbinding `msm-mdss` hung the
  laptop in run 2, so it is done only with `GLYMUR_LAB_REBIND=1`.

## `build-test-dtb.sh`

    [GLYMUR_KREL=7.3.0-rc2-glymur-N] scripts/linux/glymur-lab/build-test-dtb.sh NAME [SRC] [OUT] [DEST]

Builds `dts/qcom/NAME.dts` against the kernel build the SSD runs.
`GLYMUR_KREL` must be the release `OUT` was built as. The DTB must pass the
GPIO allow-list check. Its model is printed for review; diff the decompiled
DTB against its parent. It is copied to `DEST` (default `.work/test-dtbs`)
with a `SHA256SUMS` line.
