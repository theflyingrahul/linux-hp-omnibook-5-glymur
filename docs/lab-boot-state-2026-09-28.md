# Display-Lab Boot: What Works, and Why the Lab Cannot Start, September 28, 2026

Booted the USB entry "Ubuntu on SSD: display lab (device tree)" (kernel
`7.3.0-rc2-glymur-3`, `model = "HP OmniBook 5 Laptop 16-bf1xxx (display
lab)"`, boot ID `26d2e8f7`). This checks every subsystem on that device tree
before the lab runs. Private logs: `.work/lab-boot-2026-09-28/`.

## The lab cannot start from the USB

`docs/display-lab-2026-09-28.md` says to run
`sudo bash "/media/$USER/UBUNTU 26_0/glymur-tools/lab/start-lab.sh"` on this
boot. That cannot work: a device-tree boot enables no USB controller.
`lsusb` is empty, `/sys/bus/usb/devices` is empty, and all five `usb@` nodes
(`a000000` to `a800000`) and their PHYs are `status = "disabled"`, as the
09-28 review lists under "Known limits". GRUB reads the USB itself (it loads
the lab DTB from it), but once Linux runs, the drive does not exist. The USB
is the boot loader only. `lsblk` shows just the NVMe.

Fix (no reboot into Windows, one extra reboot in each direction):

1. Boot "Ubuntu on SSD: newest glymur kernel" (ACPI; the right USB-A port
   works there, and it runs the same `-3` kernel).
2. `bash scripts/linux/glymur-lab/stage-kit.sh` checks the kit's
   `SHA256SUMS` on the USB and copies it to `~/glymur-lab-kit`, then
   verifies the copy.
3. Boot the lab entry and run `sudo bash ~/glymur-lab-kit/start-lab.sh`.
   `start-lab.sh` never needed the USB path; it works from any directory.

`stage-kit.sh` is new, and `start-lab.sh` and the README gate now say this.
The ACPI boot in step 1 is also a chance to run anything else that needs USB.

## What works on the lab device tree (checked live)

- **CPUs** (12), **NVMe/root**, **keyboard, touchpad, touchscreen**
  (`hid-over-i2c`), **lid** (`gpio-keys`), **cpuidle** (`WFI`,
  `cpu-sleep-0`).
- **Wi-Fi**: associated to the 6 GHz network (freq 6135).
- **Bluetooth**: `hci0` up and running, QCC2072 over the GENI UART
  (`ttyHS1`), RX/TX counters increasing, on linux-firmware's pair. The RF
  calibration file `ornbcscal11.*` is still missing.
- **Battery and AC over PMIC GLink: working**, and new. `qcom-battmgr-bat`
  reports capacity 50 %, 11.4 V, 59.92 Wh full against 59.16 Wh design, 15
  cycles, 31 °C, discharging at about 11 W; `qcom-battmgr-ac` reports
  offline; UPower reads it (2.8 h to empty). The SoCCP is attached and the
  ADSP and CDSP run HP's signed images. `charge_now`/`charge_full` return "no
  data", so only energy units exist. This closes the "no battery" gap for
  DT boots, and Linux can now tell battery from AC for the fan/thermal
  profiler.
- **Two `ucsi-source-psy-pmic_glink.ucsi.0{1,2}` power supplies** register,
  so the UCSI channel to both USB-C port controllers is alive. The ports
  themselves are unusable without USB controllers and PHYs.
- **Thermal**: 70 DT-native zones.

## What does not work, and what changed since the last catalogue

- **Fan RPM and EC thermistors: absent on every DT boot. My earlier status
  table was wrong.** It listed "live fan RPM" for the minimal DT. The RPM
  came from `acpi_fan` in the ACPI boots. No DT node describes the EC
  (IC10), and there is no `hwmon` fan. The EC still runs the fan by itself.
  Corrected in `docs/status.md`.
- **CPU frequency scaling**: SCMI protocol v2.0 comes up on both instances
  (`Qualcomm:PDP0` and `Qualcomm:`), and `scmi_dev.1` to `.4` exist, but
  `scmi-cpufreq` is not bound (`CONFIG_ARM_SCMI_CPUFREQ=m`, not loaded), so
  there is no `cpufreq` sysfs. Possible one-liner: `sudo modprobe
  scmi-cpufreq` (the lab tries it, along with `qcom-cpucp-mbox`).
- **USB, audio, TPM, GPU, RTC (not checked), suspend**: as before.
- **Bluetooth firmware still uses the old names.**
  `/usr/lib/firmware/updates/qca/` holds `ornbtfw10.tlv` and `ornnv10.*`,
  the ROM-10 names the pulled commit says btqca never requests. The fixed
  `install-firmware.sh` has not been run here. The lab A/B-tests HP's pair.

## Kernel-log items on this boot

- `arm-smmu 3da0000.iommu` and `gxclkctl-kaanapali 3d64000` fail at probe
  with -110 (deferred-probe timeout). Both are GPU-side and wait on
  `CLK_GLYMUR_GPUCC`, which is not built; expected while the GPU is off.
- `psci: [Firmware Bug]: failed to set PC mode: -3` (platform-coordinated
  mode; the kernel falls back) and `qcomtee: Failed to get service! error:
  11` (the TEE service is not there): both new in the log, neither blocks
  anything seen so far.
- `qcom_q6v5_pas d00000.remoteproc: failed to get shutdown_state: -22`
  (SoCCP attach path; it attaches anyway).
- The `do_idle` WARN at `sched/idle.c:269` recurs (CPU 8 this time), so it
  is not a one-off on CPU 0.
- `arm-smmu-v3 15480000.iommu: msi_domain absent - falling back to wired
  irqs`. The earlier ACPI-boot IRQ trigger failures do not appear on DT.

## Corrections to my own earlier work

- The two-rail eDP regulator fix I committed in `d3d29b5` and the
  "root cause" wording around it were wrong; the pulled commit `1f18e2f`
  reverts it for good reasons (the firmware keeps those shared rails on,
  and the fix would have voted them off on every eDP shutdown). The
  dummy-regulator observation was real, but it was never shown to cause the
  training failure.
- "`install-firmware.sh` was never run" was wrong: the ADSP boots from a
  path only that script creates. I looked in `/lib/firmware/qca/` instead of
  `/lib/firmware/updates/qca/`.
- The fan claim above.
