# Project Status

## Current state (2026-09-27)

These run under the stock Ubuntu 7.0 live kernel with the out-of-tree ACPI
modules (`scripts/linux/glymur-acpi-input/`):

- ACPI boot without a DTB, with 12 CPUs, NVMe, the right USB-A port and the
  UVC camera;
- keyboard, touchpad and touchscreen;
- Wi-Fi scanning with HP board data;
- the EC bus over GPI DMA, which brings EC thermal zones, fan RPM and lid
  events;
- per-core CPU idle with the BIOS-gated `_OSC` override.

The same logic is now confirmed on the qcom-next boot kernel
(`7.3.0-rc2-glymur`), first booted from the Ubuntu root on SSD partition 5:
input, the EC bus/thermal/fan, and CPU idle all carry over, and Wi-Fi now
fully associates (not just scans).

Still missing, mostly on the device-tree/remoteproc path:

- battery, AC and the RTC (PMIC GLink on the ADSP);
- USB-C;
- the native GPU;
- audio (SoundWire behind LPASS);
- Bluetooth (a GENI UART, the same ACPI pattern as I²C; see the Windows
  evidence review);
- CPU frequency scaling (no `_CPC`) and cluster idle;
- suspend and the TPM.

**Device tree (2026-09-28):** the owner chose the DT route. A review before
the first boot corrected the SoC to Mahua (DSDT `SDFE` 0xA8). It also
disabled the GPU, which msm would have bound into the display device,
`uart21` and, in the minimal DT, `dispcc`. PERST#/WAKE# are confirmed from
HP's DSDT. Kernel `7.3.0-rc2-glymur-3` carries the corrected DTBs; the `-2`
DTBs must not be booted. See `docs/device-tree-review-2026-09-28.md`.

**First DT boots (2026-09-28):** the minimal DT is now the working
baseline — CPUs, NVMe, native DT input (keyboard/touchpad/touchscreen),
thermal, cpuidle, and Wi-Fi all carry over from the ACPI results, on the
firmware framebuffer. The full DT reached userspace cleanly (SoCCP, ADSP
and CDSP all attached with HP's signed firmware) but the eDP panel stayed
dark; the review's GPU-component fix held (that predicted failure mode
did not recur). The panel fails eDP clock recovery. The two-rail
regulator fix proposed that day is reverted: the firmware keeps those
shared rails on (the minimal DT's framebuffer and the Wi-Fi PHY run on
them), and the fix would have voted them off on every eDP shutdown. The
cause is open. A display lab is staged on the USB: one boot that captures
the firmware's working eDP registers and tries ten variants at runtime
(Windows' five display rails, SSC, swing tables, the firmware's TX values,
lanes, rate, lane map). A DT boot still has no USB, GPU or audio. See
`docs/device-tree-first-boot-2026-09-28.md` and
`docs/display-lab-2026-09-28.md`.

**2026-09-29: the lane/rate mismatch theory is ruled out.** A boot-time DTB
limits the full DT's eDP link to exactly the panel's own DPCD maximum (2
lanes, 2.7 Gb/s — read fresh on this boot, matching the firmware's link).
It still goes dark, with the identical `phy poweron failed --> -110` the
display lab found inside the PHY driver's power-on sequence, before link
training even starts. Two independent code paths (the stock driver here,
the instrumented lab driver in lab run 3) now show the same failure, so the
cause is inside `phy_qcom_edp_phy_power_on_v8()`/PLL configuration in
`drivers/phy/qualcomm/phy-qcom-edp.c`, not anything the device tree
controls. See `docs/edp-2lane-test-run1-2026-09-29.md` and
`docs/display-lab-run3-2026-09-28.md`.

The table below is per subsystem. "Lab DT" is the display-lab device tree
(the full DT with the display disabled at boot, plus ADSP, CDSP and PMIC
GLink), verified live on 2026-09-28 on kernel `7.3.0-rc2-glymur-3`
(`docs/lab-boot-state-2026-09-28.md`). "Minimal DT" and "Full DT" are from
the first DT boots (`docs/device-tree-first-boot-2026-09-28.md`), where
"same" means the logs showed the same result. The dated entries after this
section are history, newest first. A later entry supersedes an earlier one.

**2026-09-29:** from kernel `-4`, the minimal DT is the lab configuration
(the full DT minus the native display), so the "Lab DT" column below
describes it. The "Minimal DT" column is the old minimal
(`docs/edp-phy-backport-2026-09-29.md`).

**2026-09-29: the eDP panel works.** Kernel `7.3.0-rc2-glymur-4` backports
Qualcomm's posted v8 eDP PHY programming-sequence fix
(`docs/edp-phy-backport-2026-09-29.md`). Booted on the **unmodified full
DTS** (still declaring 4 lanes up to 8.1 Gb/s as the ceiling): no `phy
poweron failed` anywhere in the log, link training succeeds on the first
attempt at 2 lanes/2.7 Gb/s (msm negotiates down to the panel's real DPCD
limit), the eDP-1 connector shows `status=connected enabled=enabled` at
1920x1200, and `/sys/class/backlight/dp_aux_backlight` gives live DP-AUX
backlight control. Same boot: battery/AC/USB-C power supplies, Bluetooth,
Wi-Fi, ADSP/CDSP all working; GPU still safely disabled (`no GPU device was
found`, `arm-smmu`/`gxclkctl` still `-110` as designed); no ALSA soundcard
yet. This is the first full-DT boot with native graphics. See
`docs/edp-display-working-2026-09-29.md`.

| Subsystem | Minimal DT | Full DT | Lab DT (verified live) | Notes |
|---|---|---|---|---|
| CPUs (12) | Working | Working | Working | |
| NVMe / root storage | Working | Working | Working | |
| Keyboard | Working | Working | Working | native DT `geni_i2c`/`hid-over-i2c`, no out-of-tree modules |
| Touchpad | Working | Working | Working | |
| Touchscreen | Enumerates | Enumerates | Enumerates | not interactively retested; one boot-time IRQ-without-data warning |
| Lid switch | Working | Working | Working | `gpio-keys` |
| Wi-Fi | Working | Working | Working (6 GHz, HE) | still on generic `ath12k` board data (`board_id 0xff`) |
| Bluetooth | Working | Working | Working (`hci0`, QCC2072) | runs on linux-firmware's ROM-1.1 pair; RF calibration file `ornbcscal11.*` missing. The corrected `install-firmware.sh` has not been run on this SSD: `/usr/lib/firmware/updates/qca/` still holds the old ROM-10 names |
| **Battery / AC (PMIC GLink)** | No (no `pmic-glink` node) | Node declared, no data seen in logs | **Working, but has hung at least once.** `qcom-battmgr-bat` reads capacity, voltage, power, energy (59.9 Wh full, 59.2 Wh design), 15 cycles, temperature; `qcom-battmgr-ac` reads online state; UPower sees it. **2026-09-30 (kernel `-7`):** every `qcom-battmgr-*` property failed with `-110` (timeout) continuously for 14+ minutes mid-session, with GNOME showing a false "0%" (a `NaN`-fallback display, not a real reading — every property failed identically and instantly, which a real depleting battery wouldn't do). ADSP/CDSP stayed `running`; UCSI, a different client on the same PMIC GLink transport, kept responding throughout. No PDR/servreg state-change was ever logged for the hung service. Looks like a firmware-side battery-manager service hang, not a Linux driver bug — no DT/kernel fix implicated. See `docs/battmgr-hang-2026-09-30.md` | newly confirmed. The SoCCP, ADSP and CDSP are up. `charge_now`/`charge_full` return no data (energy units only) |
| USB-C port controllers (UCSI) | No | Not seen | Two `ucsi-source-psy` power supplies register | the ports are not usable for data: no USB controller or PHY is enabled |
| **USB-C charging** | Not seen | **Fixed on kernel `-6`.** The unacknowledged-notification root cause (`pmic_glink_altmode` never sending `ALTMODE_PAN_ACK` for a port with no connector node) is patched (`upstream/qcom-next/0001`) and the DT now describes both connectors. Confirmed live: a ~5.5-minute `charging-watch.sh` run with repeated plug/unplug on both ports logged **zero** "undefined port" lines, and every plug/unplug now shows up immediately in sysfs and the firmware's own polled status, with the battery correctly tracking `Charging`/`Discharging`/`Not charging` through several cycles. `qcom-battmgr-ac`/`-usb` `ONLINE` still do not track the charger; use the battery and UCSI supplies. See `docs/usb-c-ports-2026-09-29.md`, `docs/usb-c-charging-2026-09-29.md` | Not checked | See `docs/usb-c-ports-2026-09-29.md` |
| RTC | Not working | Not seen | Not checked | |
| Thermal zones | Working (69) | Working | Working (70) | DT-native TSENS zones (per-core, GPU, NSP, camera, DDR, AOSS) |
| **Fan RPM / EC** | **Absent** | **Absent** | **Absent** | correction: an earlier version of this table listed live fan RPM under DT. That was wrong. The fan RPM and EC thermistors (`acpi_fan`, `acpitz`) came from the ACPI boot only; no DT node describes the EC (IC10), so there is no fan telemetry. The EC still runs the fan itself. **Kernel `-9`, first live test (2026-09-30):** `hp-omnibook-5-ec` binds cleanly on `i2c9`/`9-0076`. **Fan and thermistors: working** — `fan1 0 rpm` (idle) and four thermistor readings (35/36/36/31 °C), stable across 5 samples. **Keyboard backlight: write doesn't take** — all three levels set, backlight stayed visibly off every time (owner-confirmed); likely missing the same "take OS control" flag the mute-LED commands send first. **Mute LEDs: real but not 1:1** — `platform::micmute` (LED 9) correctly lights only F9; `platform::mute` (LED 8) lights *both* F6 and F9 together, so the driver's own F6-only labeling for LED 8 is wrong as written. Nothing here is a hardware-safety concern. See `docs/ec-2026-09-30.md` |
| CPU idle | Working (`WFI`, `cpu-sleep-0`) | Working | Working | no cluster idle yet |
| CPU frequency scaling | No | No | No | **Working on the GPU test DT (kernel `-5`)**: `arm,no-completion-irq` on `/firmware/scmi` (upstream SCMI polling fix) turns the old hard hang into a fallback-to-polling warning; `modprobe scmi-cpufreq` then gives two real policies, `policy0` (cpus 0-5) up to 3.42 GHz and `policy6` (cpus 6-11) up to 4.03 GHz, `driver=scmi`. Not yet carried by the full/minimal DTs. See `docs/gpu-bringup-run1-2026-09-29.md`. Still true elsewhere: **do not `modprobe scmi-cpufreq` without this fix** — it hangs the laptop hard (display-lab run 1, `docs/display-lab-run1-2026-09-28.md`) |
| USB-A / USB-C / UVC camera | No | No | No | All five `usb@` nodes and their PHYs are disabled in the full and minimal DTs: a regression against the ACPI boot. **Working on the "GPU and USB test" DT (kernel `-5`/`-6`)**: `usb_2` (host, USB-A), its M31 eUSB2 PHY and QMP combo PHY all bind, and the boot USB stick itself enumerates through the new internal controller at 5000 Mb/s (`lsusb -t`: `Driver=usb-storage, 5000M`) — no supplies, repeater or HP's `PHYC` tuning declared. First working USB on any DT boot. See `docs/usb-a-bringup-2026-09-29.md`. **USB-C, first live test (kernel `-6`):** connector 1 (`usb_1`, away from the hinge) works — `partner=yes`, `opmode=usb_power_delivery`, `data_role=host`, and a real USB 2.0 hub + mass-storage device enumerated and read data at 480 Mb/s (no repeater declared, as predicted). Connector 0 (`usb_0`, hinge side) shows `partner=yes`/PD but is unsettled: it came up in host mode, failed to enumerate a device three times (`error -71`), then the role switch settled on `device` — not yet retested with a known-good USB-C drive to isolate cause. See `docs/usb-c-ports-2026-09-29.md`. **Log review (2026-09-30, later):** port0 ending as `device` was the charger plugged into it (correct); the failing port0 device was low-speed and the working port1 device high-speed, so speed (eUSB2 repeater) is as likely as the port: swap-test pending. Each host-to-device role switch logs a kernel WARN (`kernfs: can not remove 'usb5'`, Type-C partner links). Charging through a hub left the laptop as USB device (no DR_Swap). USB-C SuperSpeed untested. **Swap test result (2026-09-30, kernel `-7`): a full/low-speed problem on all three host ports, not a port problem.** The same mouse failed identically on `usb_0`, `usb_1` and **USB-A** (`error -71`, escalating to `WARN: invalid context state for evaluate context command`) — including on USB-A, which has cleanly enumerated a SuperSpeed stick on every boot, and on `usb_1`, which enumerated that same stick on its SuperSpeed side *in the same boot*. High-speed (480 Mb/s) and SuperSpeed both work everywhere tried; full-speed and low-speed fail everywhere tried. Matches the predicted, deliberately-undeclared eUSB2 repeater gap (all three controllers share the `qcom-m31eusb2-phy` design; native eUSB2 without a repeater is typically HS-only). See `docs/usb-c-ports-2026-09-29.md`. **The UVC camera (2026-09-30): identified, not yet staged.** A real USB2 peripheral (`USB\VID_30C9&PID_00D9`, works on ACPI boot), on its own controller `usb_hs` (ACPI `QCOM0FEF`), fully described in HP's DSDT: memory range, 4 interrupts, one direct GPIO (pin 9), and a PEP D0 rail-vote table (S7F 1.2V, L15B 1.8V, LDO8_B 3.072V, L4H 1.2V, L2H 0.88V, L1F 0.904V) matching the same rail families already used for the working ports. Its PHY is the same `qcom,glymur-m31-eusb2-phy` family as `usb_0`/`usb_1`/`usb_2`, but it's the only one of the four with an extra GPIO in its ACPI resources — worth checking whether that's a repeater line the others lack, given today's full/low-speed finding. No DT change staged yet. See `docs/camera-usb-controller-2026-09-30.md`. **Kernel `-8` (staged, not booted):** SMB2370 eUSB2 repeaters (SPMI bus 2, SID 9 → `usb_0`, SID 10 → `usb_1`, as on Qualcomm's CRD; HP votes their L15B/L7B rails) with a driver check that the PMIC is an SMB2370 before any write (`upstream/qcom-next/0003`), and `usb_hs` enabled for the camera. USB-A unchanged. See `docs/eusb2-repeater-2026-09-30.md`. |
| Native display | Firmware framebuffer | **Working on kernel `-4`/`-5`, but boot-to-boot flaky on the GPU/USB-A test DTs**: unmodified full DTS link trains at 2 lanes/2.7 Gb/s on the first attempt, `eDP-1 connected/enabled`, 1920x1200, DP-AUX backlight control live. Fixed by Qualcomm's posted v8 PHY programming-sequence backport (`docs/edp-phy-backport-2026-09-29.md`, confirmed `docs/edp-display-working-2026-09-29.md`). On kernel `-3`, DPU and DP bound but the panel stayed dark on `phy poweron failed --> -110`. **New (2026-09-29, GPU-and-USB-A test DT):** the identical DTB and kernel link-trained cleanly on one boot, then failed two reboots later with a *different* signature — `link training #2 ... failed. ret=-110` inside `msm_dp_ctrl_link_train_1_2` (PHY power-on succeeded; training itself timed out) — with the rest of the session (GPU, gdm, gnome-shell, keyboard) fully alive, just no connector to show it on. Not yet isolated whether this is specific to the USB-A addition or a general reboot-to-reboot marginal eDP behavior. See `docs/usb-a-bringup-2026-09-29.md` | Firmware framebuffer (display disabled on purpose) | The pre-backport root cause was inside `phy_qcom_edp_phy_power_on_v8()`/PLL configuration in `phy-qcom-edp.c`, not the DT: a boot-time test limited to the panel's own advertised maximum (2 lanes, 2.7 Gb/s) still failed identically. See `docs/display-lab-run3-2026-09-28.md`, `docs/edp-2lane-test-run1-2026-09-29.md` |
| GPU | Disabled | Disabled | Disabled | **Kernel-side working on the GPU test DT (kernel `-5`)**: Adreno X2-85 binds, GMU firmware loads (v5.2.38), no zap shader needed (`SECVID_TRUST_CNTL` instead, as on upstream Glymur boards), `devfreq` actively scales 310 MHz-1.35 GHz. Display stayed live on the same boot. **Userspace: real hardware acceleration confirmed with Mesa 26.2.3** (`/opt/mesa-glymur`, opt-in beside Ubuntu's 26.0.8, `docs/mesa-x2-85-2026-09-29.md`) — `mesa-glymur-run eglinfo -B -p gbm`/`-p surfaceless` and `vulkaninfo` all report the real `Adreno (TM) X2-85` device, `glmark2` scores 29, and devfreq genuinely ramps to 1.35 GHz under load. **GNOME's own compositor (gnome-shell) still shows "Software Rendering"**: the desktop-wide switch (`environment.d`) hasn't reached it in two attempts, for reasons not yet understood — a desktop-integration gap now, not a Mesa-support or kernel gap. The full and minimal DTs still keep the GPU block (GPU, GMU, gpucc, gxclkctl, SMMU) off by design **Desktop fix staged:** Mesa `26.2.3-2` (adds llvmpipe on LLVM 21) and `sudo mesa-glymur-run --system on`, which makes the dynamic linker prefer it for every process, gnome-shell included (`docs/mesa-x2-85-2026-09-29.md`). **2026-09-30, `-6` + Mesa `26.2.3-2` system-wide:** GNOME composites on the GPU (About: "Adreno X2-85"), but the screen is **corrupted** (noise bands, block garbage). The kernel's UBWC table, GMEM and slice handling match Qualcomm's KGSL; the 3-slice gen8 path in Mesa is the prime suspect. **`gpu-corruption-test.sh`'s first run isolates it to `sysmem` (GMEM tiling):** of `default`/`linear scanout`/`noubwc`/`nolrz`/`sysmem`/`noubwc+nolrz+sysmem`, only the two cases with `sysmem` were clean — linear scanout, `noubwc` and `nolrz` alone all stayed corrupted. Points specifically at Mesa's 3-slice GMEM/bin-layout tiling, not UBWC or LRZ. Workaround: `sudo mesa-glymur-run --system off`, or force `FD_MESA_DEBUG=sysmem`. See `docs/gpu-corruption-2026-09-30.md` **Root cause (2026-09-30, later):** msm reports 21 MB of GMEM (all 4 slices) but the part runs 3; KGSL reports 15.75 MB. Mesa placed tiles and CCU caches past real GMEM. Fixed in kernel `-7` (`upstream/qcom-next/0002`). **Confirmed exactly as predicted (2026-09-30, second `gpu-corruption-test.sh` run, still on `-6`):** `sysmem` and `FD_MESA_GMEM` set to the correct 15.75 MB (or less) both render clean; the kernel's own (wrong) 21 MB default is the only corrupted case. An over-estimate of GMEM causes the corruption; an under-estimate is safe. **Fixed and confirmed on kernel `-7` (2026-09-30, booted):** zero corruption, and the first boot in this whole investigation with zero `fd_pipe_new2`/`unsupported GPU id`/`VK_ERROR_INCOMPATIBLE_DRIVER`/software-fallback lines anywhere in the log. `gnome-shell`'s own process has the real Mesa mapped in (not just test programs via `mesa-glymur-run`). `glmark2` (GPU default, no overrides) scores **11570**, versus 29 on `-6`'s uncorrupted-looking-but-actually-corrupted default — a ~400× jump, since the low score was the GPU stumbling over out-of-range GMEM accesses on nearly every frame, not just visual noise. No GPU faults or hangs. **GPU bring-up on this laptop is done**: bound, firmware loaded, cpufreq scaling, real accelerated rendering, GNOME's own compositor using it, no corruption. See `docs/gpu-corruption-2026-09-30.md`. Still true: the full and minimal DTs keep the GPU block off by design; this is all on the GPU test DT only. |
| Audio | No | No | No | SoundWire/LPASS not wired yet |
| TPM | No | No | No | |
| Suspend | Untested (masked) | Untested (masked) | Untested (masked) | |

## History

**2026-09-28: first device-tree boots.** The minimal DT (firmware
framebuffer, no GPU/audio/USB) is the new working baseline, matching the
ACPI results with native DT drivers throughout. The full DT (adds the
eDP panel, SoCCP-attached ADSP/CDSP with HP's signed firmware) reached
userspace but the panel stayed dark on an eDP link-training failure at
the DP PHY — a different failure than the GPU-component issue the
09-28 review had already guarded against. See
`docs/device-tree-first-boot-2026-09-28.md`.

**2026-09-27: first boot of the qcom-next kernel on the SSD install.**
Input, the EC bus/thermal zones/fan, and CPU idle all work as they did
under stock Ubuntu, entirely from in-kernel drivers driven by the board
command line (no out-of-tree modules). Wi-Fi now fully associates (6 GHz,
HE, 160 MHz), beyond the previous scanning-only result. Still absent:
USB-C, native GPU, Bluetooth, audio, battery/AC/RTC, TPM, CPU frequency
scaling, suspend (untested). New issue found: `chrony`'s RTC poll against
`acpi-tad` retries without backoff, flooding the journal with ACPI
`GenericSerialBus`-handler errors (hundreds/sec) until PMIC GLink lands;
not yet fixed. The fan/thermal profile closely tracks the stock-Ubuntu
run. See `docs/qcom-next-first-boot-2026-09-27.md` and
`docs/fan-thermal-windows-2026-09-27.md`.

**2026-09-27: qcom-next boot kernel built; Ubuntu root on SSD partition 5 staged.**
`7.3.0-rc2-glymur` (layered series, board values on the command line) is built
and staged with an SSD installer and USB GRUB entries; not yet booted. A log
review added `systemd.tpm2_wait=0` (90 s TPM wait per boot) and found the RTC
behind PMIC GLink. See `docs/qcom-next-ssd-install-2026-09-27.md`.

**2026-09-26, late: lid events work** through a GpioInt-capable GED driver
(now `patches/kernel/upstream/qcom-next-acpi/0001`); the port to the qcom-next kernel is in progress. See
`docs/qcom-next-port-and-lid-2026-09-26.md`.

**2026-09-26, reboot with the `_OSC` override: CPU core idle and the EC
bus work.** `acpi_idle` uses per-core C1/C4; cluster states stay gated behind
`PEPI`. IC10 transfers over GPI DMA, and the ACPI thermal zones now read real
temperatures. See `docs/cpuidle-and-ec-bus-results-2026-09-26.md`.

**2026-09-26, live workstation: EC bus (IC10) GPI DMA test** (superseded:
IC10 bound after the next reboot, see the entry above). An ACPI GPI
DMA module bound `QGP1`, and its allocate commands completed through the
GPII interrupt. IC10 did not bind: the live image's `async_tx` claimed every
channel first, because the driver did not set `DMA_PRIVATE`. That is now
fixed; a retry needs a clean boot. See `docs/ec-gsi-live-test-2026-09-26.md`.

**2026-09-26, second input-test run: keyboard, touchpad, and touchscreen
work under Linux.** This is the stock Ubuntu `7.0.0-30-generic` live kernel
with no DTB, plus two out-of-tree ACPI modules. Wi-Fi scanning also works.
The EC bus (IC10) is in GPI DMA mode and was refused safely. See
`docs/acpi-input-results-run2-2026-09-26.md`.

**2026-09-26, first input-test run:**

- Wi-Fi scanned successfully with the HP board data.
- The ACPI GPIO module loaded.
- The I²C module oopsed on a NULL GENI wrapper, since fixed and restaged.

See `docs/acpi-input-results-2026-09-26.md`.

**Earlier 2026-09-26 update:** a repository audit
(`docs/repository-audit-2026-09-26.md`) corrected the I²C clock analysis
and replaced RFC patch 0001. A keyboard/touchpad test kit is now staged on
the installer USB as an optional GRUB entry, "Glymur ACPI keyboard/touchpad
test (RAM live)"; it was run twice later that day (see the input-test
entries above). It loads two out-of-tree modules
into the stock Ubuntu kernel:

- an ACPI TLMM GPIO driver with PDC pin translation;
- an ACPI GENI I²C driver derived from v7.0 that uses the firmware's `CLKD`
  timing.

Ubuntu's `i2c_hid_acpi` should then bind the keyboard and touchpad. The same
boot also probes the touchscreen and EC buses. See
`docs/acpi-input-test-2026-09-26.md`.

Battery and AC AML read PMIC-GLink fields through the ABD GenericSerialBus
region (`QCOM1045`), gated by the same `PMGK.LKUP` flag as USB-C. They do not
use the EC's I²C bus.

### Before the input work (superseded by the entries above)

Ubuntu 26.04.1 ARM64 booted through UEFI/ACPI on 2026-09-15 and 2026-09-25 without a supplied target DTB. The second automated capture confirmed `CONFIG_I2C_QCOM_GENI=m` and a loaded module, but five `QCOM0F10` controllers remained unbound; no I²C adapters or keyboard/touchpad input appeared. Linux started 12 CPUs and enumerated PCI4/WLAN, PCI5/NVMe, two xHCI controllers, the camera, and the right USB-A installer. See `docs/ubuntu-live-boot-results-2026-09-25.md`. An elevated Windows Day-0 metadata capture and ACPICA table capture were completed earlier. Qualcomm's preview validates a separate reference platform; see `docs/qualcomm-preview-review-2026-09-25.md` before applying its boot instructions here.

A September 26 RAM-live whole-system inventory completed all checkpoints and
powered off without keyboard input. It confirmed the desktop used `simpledrm`
without a GPU render node; a verified QCC2072 firmware retry reached firmware
startup but failed to find HP board data, leaving no Wi-Fi interface
(fixed the same day with the HP `board-2.bin`). The
private capture stays on the installer USB. Its live clock still reports July
27, so its directory timestamp is not the physical collection date.
See `docs/system-inventory-results-2026-09-26.md` for the sanitized findings.

Read-only checks on the same laptop's live Windows installation verified the
driver-to-ACPI-ID mapping for I²C, PMIC GLink, USB-C, and UCSI. Qualcomm's
Glymur GLink/UCSI implementation is currently matched through device tree,
whereas this HP boots through ACPI. The specific probe and firmware-state
gaps are recorded in `docs/qualcomm-acpi-gap-2026-09-25.md`; the reference
kernel and CRD DTB are not ready to boot on this HP.
An RFC guard for one missing-clock probe failure has passed an isolated
cross-compile, but it does not bind the HP I²C devices or enable input.
An independent RFC also balances runtime PM if I²C bus-rate setup fails;
it is likewise offline-only and adds no HP device ID. The HP's ACPI
clock, GENI wrapper, and `PEP0` power-state model remain unresolved.
The HP's `PEP0.BSRC` resource table identifies all five I²C engine clocks
with a numeric value of 19,200,000 and their TLMM pin pairs. Linux has no
validated ACPI path to apply those resource settings.
The live boot also waited for `dev-tpm0.device` and `dev-tpmrm0.device` after
reporting no TPM chip. Its TPM2 ACPI table uses vendor-reserved start method
9, and the captured ACPI namespace has no `MSFT0101` device for Linux's
standard CRB driver. These are two waits for one absent TPM, not evidence of
two independent service failures or an I²C regression. TPM support requires
separate investigation; do not clear or disable the Windows TPM to hide the
wait.
A separate inspection module now cross-builds against the captured Ubuntu
`7.0.0-30-generic` headers. It is default-off, registers no I²C adapter,
and was loaded in a separate live USB test on September 25. Both inspected
ACPI controllers (`I2C1` and `I2C5`) reported I²C protocol, enabled FIFO,
and a set master SE clock-enable bit. The collector completed; no adapter
or bus transfer was attempted. Clock/power transitions and interrupts remain
unproven. A separate read-only timing/status snapshot is built and staged as
an optional live USB boot entry and has now completed. Both devices had the
HP `CLKD` 400-kHz divider/SCL counter tuple `(2, 5, 12, 24)` at probe time,
with no active command and DMA disabled. This is not a measured bus rate or
successful transfer. That boot used `clk_ignore_unused pd_ignore_unused`; in ACPI mode no Linux clock or
power-domain provider binds, so those arguments were no-ops (see
`docs/repository-audit-2026-09-26.md`). See
`docs/qcom0f10-inspection.md`.
The first active FIFO transaction has an offline design in
`docs/i2c-fifo-probe-design.md`; no transfer-capable module or new boot entry
has been built or staged.
A separate draft ACPI GPIO match also cross-compiled; it remains unbooted.
Keyboard, touchpad, and touchscreen need both their I²C bus and `GIO0`
interrupt provider. Keyboard and touchpad additionally use PDC-encoded ACPI
GPIO numbers that the draft does not translate, so these patches do not
restore input even when considered together. The static ACPI mapping resolves
the keyboard's pin 704 to GPIO 67 and the touchpad's pin 896 to GPIO 3;
Linux still needs a correct runtime translation path. The read-only
`scripts/linux/analyze-acpi-pdc.py` checker reproduces those mappings from
the private DSDT and passes synthetic tests. An unbooted PDC-translation
RFC now cross-compiles after the GPIO match draft, but interrupt delivery
and I²C remain unvalidated; no new boot artifact was made.

| Subsystem | Status | Notes |
|---|---|---|
| boot | ACPI live boot confirmed | Ubuntu ARM64 reached userspace without a target DTB; collector completed |
| CPU | Linux observed | Snapdragon X2 Elite X2E84100; Ubuntu kernel initialized ACPI/PSCI |
| SMP | Linux booted 12 CPUs | Kernel log reports 12 processors activated; hotplug and long-run stability untested |
| timers | Linux clocksource active | ARM architected timer at 19.2 MHz and `arch_sys_counter` selected; accuracy and suspend behavior untested |
| NVMe | Linux enumerated | Samsung endpoint at PCI domain 5 (`0005:01:00.0`); namespace and partitions visible |
| internal display interface | Unknown | The live capture did not establish eDP versus another transport |
| OLED brightness | Unknown | |
| GPU | Native acceleration absent in tested boot | GNOME used `simpledrm` on `simple-framebuffer.0`; no `/dev/dri/renderD*` appeared. ACPI `QCOM0FF5` was unbound, although `msm` was loaded. Xwayland reported software fallback. |
| touchscreen | **Linux working (test modules)** | `ELAN2513` 0x10 on I2C9, GPIO 51; `hid-multitouch`; see `docs/acpi-input-results-run2-2026-09-26.md` |
| touchpad | **Linux working (test modules)** | `ELAN0189` 0x15 on I2C5, PDC pin 896 → GPIO 3; `hid-multitouch` |
| keyboard | **Linux working (test modules)** | `QTEC0001` 0x3A on I2C1, PDC pin 704 → GPIO 67; `i2c_hid_acpi` |
| keyboard backlight | **Works, but entirely outside Linux's view**: on/off and its auto-off timeout both function, but no `/sys/class/backlight` device, HP platform driver, or any control/status path exists for it. Confirms the EC/`HWMI` theory: it runs autonomously in firmware. See `docs/keyboard-hotkeys-2026-09-29.md` | Not a config change: `ACPI_WMI` is x86-only in qcom-next and `HP_WMI` needs an ACPI EC. The control path (EC or `HWMI`) is still open. See `docs/windows-evidence-plan-review-2026-09-27.md` |
| F6/F9 mute/mic-mute keys and their LEDs | Keycode raw-captured live: **F6 and F9 send the identical HID usage (Consumer/Mute, 0xC00E2), not distinct keys** — Linux cannot tell them apart. Neither LED is on the keyboard's own LED bitmap (only the 5 standard lock LEDs) | Likely EC- or codec-driven, neither present in any DT yet. See `docs/keyboard-hotkeys-2026-09-29.md` |
| Copilot key / other special Fn keys | Keycode raw-captured live: **arrive correctly** (e.g. Copilot = `Meta+Shift+F23`, a known OEM pattern for keys with no native Windows driver) | Nothing is bound to them in GNOME yet — a desktop-config gap, not a kernel/DT problem. See `docs/keyboard-hotkeys-2026-09-29.md` |
| Power key LED | Lights correctly (autonomous) | Suspend "breathing" behavior not tested — suspend is masked |
| function keys | Unknown | |
| lid switch | **Linux working (test modules)** | GED `LIGE` on GPIO 92 plus the EC bus; logind sees open/close. See `docs/qcom-next-port-and-lid-2026-09-26.md` |
| battery | Not exposed in tested Linux boot | Windows exposes charge and discharge data, but Linux had no `/sys/class/power_supply` device; UPower displayed no battery. |
| charging | Windows observed; Linux unknown | The charger powers and charges the laptop in Windows; Linux ACPI adapter `_PSR` previously failed because a GenericSerialBus handler was missing. |
| thermal sensors | **Linux working (test modules)** | Four `acpitz` zones read real temperatures once IC10 (EC) is on GPI DMA; see `docs/cpuidle-and-ec-bus-results-2026-09-26.md` |
| fan | **EC-controlled; responds under Linux** | `acpi_fan` `_FST` reads RPM over the EC bus: 2482 -> 4028 -> 2776 RPM in a load test (`docs/boot-log-battery-fan-review-2026-09-26.md`). Windows exposes no fan RPM; on the same EC thermistors (TZ31-34) Linux idles 3-8 °C warmer (no DVFS or cluster idle) and peaks similarly under load. See `docs/fan-thermal-windows-2026-09-27.md` |
| Right USB-A | USB 3 storage and USB 2 HID enumeration work | The installer used bus 3 at 5 Gbit/s; a Dell receiver bound to `usbhid` on bus 2 at 12 Mb/s. Mouse motion events remain unproven. See `docs/usb-input-isolation-test.md`. |
| USB-C port 1 | Timed storage hotplug not detected | Owner connected USB-C storage in the hinge-side port; no USB event or topology change appeared. Earlier installer boot from USB-C also failed. |
| USB-C port 2 | Timed storage hotplug not detected | Owner repeated the test in the other left port with the same result. Connector routing and cause remain unknown. |
| USB-C Power Delivery | No Linux Type-C device observed | ACPI `USBC000` reported `status=0`; `/sys/class/typec` and `/sys/class/usb_role` were empty. Negotiation was not tested. |
| USB-C DisplayPort Alt Mode | Unknown | No Type-C class device appeared; DisplayPort routing was not tested |
| Wi-Fi | **Working on the qcom-next SSD install** | Associates and passes traffic: 6 GHz, HE, 160 MHz (2026-09-27). Uses upstream `firmware-2.bin` plus the private HP `board-2.bin` entry for subsystem `103c:8ef3`, board 255, from `/lib/firmware/updates/`. See `docs/qcom-next-first-boot-2026-09-27.md` and the correction in `docs/windows-evidence-plan-review-2026-09-27.md`. Without that entry, no interface comes up (2026-09-26). |
| Bluetooth | No controller yet; path identified | `QCOM0F6B` (`BTH0`) is QCC2072 Bluetooth over a GENI UART: `UR15` (`QCOM0F16`, QUP_1_SE_6) with BT_EN on GPIO 116. `hci_qca` supports QCC2072. Missing: ACPI support in `qcom_geni_serial`, the 3 Mbaud clock question, and a BT_EN output. A read-only snapshot module is staged. See `docs/windows-evidence-plan-review-2026-09-27.md` |
| speakers | No ALSA soundcard in tested boot | Windows: SoundWire SDCA peripheral `MAN_0217`/`PART_0110` behind LPASS (ACX). LPASS/ADSP path. |
| headphone jack | Physical jack observed | Linux audio behavior untested |
| microphones | Not in Linux | Windows: SDCA "Microphone Array" on the same SoundWire peripheral as the speakers. LPASS/ADSP path. |
| RGB camera | Linux USB/UVC enumerated | HP True Vision FHD camera present and bound to `uvcvideo` |
| IR camera | Windows observed | HP IR camera present |
| CPU idle | **Core states working (DSDT override)** | `acpi_idle` C1/C4 after the `_OSC` fix; cluster/system states gated by `PEPI` |
| suspend | Unknown | |
| resume | Unknown | |
| RTC | Not available under ACPI | No `rtc0`. `\_SB.PRTC` (`ACPI000E`) reads and sets time through `\_SB.PMGK` (PMIC GLink), the same missing path as the battery. See `docs/qcom-next-ssd-install-2026-09-27.md` |
| TPM | Not exposed to Linux | TPM2 table present, but no `/dev/tpm0` or `/dev/tpmrm0` in captured boot; vendor-reserved start method 9 needs investigation. systemd waited 90 s per boot for it; the board command line sets `systemd.tpm2_wait=0` |
| ADSP | Unknown | |
| CDSP | Unknown | |
| NPU | Unknown | |
| firmware loading | Partial | QCC2072 Wi-Fi firmware and HP board data load. ADSP, CDSP and GPU firmware need the device-tree/remoteproc path and are untested. |
