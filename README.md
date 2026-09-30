# Linux on HP OmniBook 5 Glymur

This repository tracks native Linux bring-up for the HP OmniBook 5 16-bf1xxx family using Qualcomm Snapdragon X2 / Glymur.

The working project target is:

    HP OmniBook 5 NGAI 16-bf1107nr
    D3ZN3UA
    Snapdragon X2 Elite X2E-84-100
    32 GB RAM
    16-inch OLED touchscreen

The live WMI capture reports the 16-bf1xxx family; the BIOS Main page additionally shows product number `D3ZN3UA#ABA`, confirming the documented D3ZN3UA target family.
16-bf1xxx is the HP hardware family covered by the service documentation.

The board device tree is `dts/qcom/mahua-hp-omnibook-5-bf1xxx.dts`. The SoC is
the Mahua die, described by Qualcomm's `mahua.dtsi`, which builds on
`glymur.dtsi`.

## Project Philosophy

- Evidence-first bring-up
- No foreign DTB will be booted on the target
- Other Glymur device trees may be studied as references only
- Machine-specific properties must be derived from the target machine or applicable documentation
- Unknown values must remain unknown rather than being guessed

Current phase: comparing Qualcomm's Snapdragon X2 kernel and Debian image recipes with this HP's ACPI evidence. Qualcomm validates its preview on reference hardware, not this laptop. Two Ubuntu ARM64 ACPI captures confirm CPU, PCIe, NVMe, xHCI, camera, and installer storage, while I²C/input remain unavailable. The pinned Qualcomm kernel and CRD DTB compile in WSL but have not been booted on this machine. Fedora ARM64 remains the intended installed OS. See `docs/qualcomm-preview-review-2026-09-25.md` and `docs/qualcomm-acpi-gap-2026-09-25.md`.

## CURRENT GATE

**2026-09-30 (three results in from kernel `-6`: charging fixed, USB-C data
works on one port, GPU corruption isolated to GMEM tiling):**

- **Charging: fixed.** `charging-watch.sh`, ~5.5 minutes of plug/unplug on
  both ports, logged zero "undefined port" lines (every prior run had one,
  then total silence). Every plug/unplug now tracks correctly in sysfs and
  the firmware's own polled status, battery `Charging`/`Discharging`
  transitions included. See `docs/usb-c-ports-2026-09-29.md`.
- **USB-C data: one port confirmed, one unsettled.** Connector 1 (away
  from the hinge) works as host: `partner=yes`, PD, and a real USB 2.0 hub
  + mass-storage device enumerated and read at 480 Mb/s. Connector 0
  (hinge side) shows a partner but churned through a failed host-mode
  enumeration (`error -71` ×3) before settling as `device` — needs a
  retest with a known-good USB-C drive to isolate. See
  `docs/usb-c-ports-2026-09-29.md`.
- **GPU corruption: isolated to `sysmem` (GMEM tiling).**
  `gpu-corruption-test.sh`'s first run: only the two cases including
  `FD_MESA_DEBUG=sysmem` were clean; linear scanout, `noubwc` and `nolrz`
  alone all stayed corrupted. Points specifically at Mesa's 3-slice
  GMEM/bin-layout tiling, not UBWC compression or LRZ. Workaround:
  `sudo mesa-glymur-run --system off`, or force `FD_MESA_DEBUG=sysmem`.
  Worth reporting upstream. See `docs/gpu-corruption-2026-09-30.md`.

**2026-09-30 (GNOME on the GPU, but corrupted):**

- **What happened.** With `-6` and Mesa `26.2.3-2` system-wide, GNOME
  composites on the Adreno X2-85 (About: "Adreno X2-85"). The screen shows
  noise bands and block-shaped garbage.
- **What isn't the cause.** The kernel's UBWC, GMEM and slice setup match
  Qualcomm's own KGSL driver, and the display was clean with software
  rendering.
- **Suspect.** Mesa's barely tested 3-slice gen8 path.
- **Next.** On a text console (Ctrl+Alt+F3), run `sudo apt install
  kmscube` and then `bash "/media/$USER/UBUNTU 26_0/glymur-tools/kernels/gpu-corruption-test.sh"`.
  It runs a GPU cube with compression, LRZ and GMEM tiling switched off
  one at a time, asks whether each looked clean, and logs the kernel's
  GPU messages.
- **Clean desktop meanwhile.** `sudo mesa-glymur-run --system off`, then
  reboot. See `docs/gpu-corruption-2026-09-30.md`.

**2026-09-30 (kernel `-6`: the charging fix, USB-C ports and system-wide
Mesa, built; waiting for the USB stick to stage):**

- **Kernel `7.3.0-rc2-glymur-6`.** Same qcom-next base (re-fetched: the
  tip is still `e428097a36d`; mainline has nothing newer for these
  drivers). It adds one patch: `pmic_glink_altmode` now acknowledges port
  notifications for ports without a connector node. The missing
  acknowledgement is the likely cause of charging stopping after the
  first unplug (`docs/usb-c-ports-2026-09-29.md`).
- **Device tree ("GPU and USB-A test" entry, shipped in the `-6`
  package).** Both USB-C ports are described from HP's tables: connector
  0 (hinge side) → `usb_0`, connector 1 → `usb_1`, each with its eUSB2
  and QMP PHYs. The firmware's notifications are now carried out and
  acknowledged, and the USB-C ports can carry data.
- **Mesa `26.2.3-2`.** Adds llvmpipe on Ubuntu's LLVM 21.
  `install-from-usb.sh` turns on `mesa-glymur-run --system on`, a
  dynamic-linker switch that should bring gnome-shell onto the GPU.
  `check-mesa.sh` shows which libraries it actually loaded
  (`docs/mesa-x2-85-2026-09-29.md`).
- **Next:**
    1. Once `-6` and Mesa are staged, from "device tree (GPU and USB-A
       test)" (its USB-A port works) run `install-from-usb.sh`.
    2. Reboot into the same entry.
    3. Run `check-mesa.sh`, `check-usb.sh` (with USB-C and USB 2.0
       devices plugged in) and `charging-watch.sh`.

**2026-09-29 (charging lead: unacknowledged port notifications; fix
staged):**

- **Re-timed charging run.** Re-timed with kernel timestamps (the trace
  lines were read late), `charging-watch.sh`'s run shows the 41 W session
  ending at 22:14:55. In the same second the kernel logged
  `pmic_glink_altmode: notification on undefined port 1`. After that, the
  firmware's own connector status never showed a connection again on
  either port.
- **Why.** Our `pmic-glink` node has no connector nodes, and
  `pmic_glink_altmode` only sends the firmware `ALTMODE_PAN_ACK` for
  defined ports. No notification had ever been acknowledged.
- **Staged.** The "device tree (GPU and USB-A test)" DTB on the USB now
  declares two bare `usb-c-connector` nodes (DTB-only, `398b335e…`).
- **Next boot of that entry:** run `sudo bash ~/charging-watch.sh` and
  plug, unplug and replug on both ports. See
  `docs/usb-c-charging-2026-09-29.md`, last section.
- **eDP.** The one blank boot matches a known post-fix eDP link-training
  intermittency (Zenbook A16: `-110` in about 1 of 3 boots). It is
  probably not caused by USB-A (`docs/usb-a-bringup-2026-09-29.md`).

**2026-09-29 (charging: real sessions, unstable negotiation):**
`charging-watch.sh`'s first live run (kernel `-5`): the owner plugged in
about a minute before starting it, and by the time it started a real 41 W
PD session was already up on port1 — proof the port and negotiation can
work for real. After it dropped on its own about a minute later, ~5.5
minutes of plugging/unplugging both ports left sysfs *and* the
firmware's own directly-polled connector status both flat at disconnected
— but two genuine `ucsi_connector_change` hardware interrupts fired
anyway, one per port, each already collapsed back to `connected=0` by the
time it was read. Together with a stray +45.6 W heartbeat read right after
a disconnect, this points at unstable/collapsing negotiation rather than a
missing driver feature. See `docs/usb-c-charging-2026-09-29.md`.

**2026-09-29 (real GPU acceleration confirmed; GNOME's compositor still isn't
using it):** `check-mesa.sh` (Mesa 26.2.3, `/opt/mesa-glymur`) on the GPU
test DT: `mesa-glymur-run eglinfo -B -p gbm`/`-p surfaceless` and
`vulkaninfo` all report the real `Adreno (TM) X2-85` device (not a
fallback), `glmark2` scores 29, and devfreq genuinely ramps to 1.35 GHz
under load — this is real, working hardware rendering and compute, not
just a bound-but-idle GPU. Only GNOME's own compositor (`gnome-shell`)
still shows software rendering: the desktop-wide `environment.d` switch
hasn't taken effect for it across two attempts (once after a disruptive
`systemctl restart user@1000.service`, once after a clean full reboot with
the file genuinely present), even though `gnome-shell` runs as a proper
systemd user unit that should inherit it. Cause not yet found. See
`docs/mesa-x2-85-2026-09-29.md`.

**2026-09-29 (USB-A works; eDP is boot-to-boot flaky on that DT):** the
"device tree (GPU and USB-A test)" entry was booted twice back-to-back,
same DTB and kernel. First boot: everything worked together for the first
time — `usb_2`'s M31 eUSB2 and QMP combo PHYs both bind, and the boot
stick itself enumerates through the internal controller at 5000 Mb/s,
*and* the eDP panel was connected/enabled at 1920x1200 on the same boot.
Second boot, two minutes later: blank screen. Keyboard and the rest of the
system were alive (gdm/gnome-shell started normally, GPU bound) — this was
`msm_dp_ctrl_link_train_1_2` timing out (`ret=-110`) partway through
training, a different failure than the pre-backport `phy poweron failed`
bug, not a hang. Same DTB succeeding once and failing the next boot rules
out a deterministic DT regression; it looks like more of the same
boot-to-boot power/reference-clock marginality already seen in USB-C
charging. Next: reboot "GPU test" (no USB-A) a few times back-to-back to
see if eDP is equally flaky there, to tell a shared-reference-clock
interaction from a general one. See `docs/usb-a-bringup-2026-09-29.md`.

**2026-09-29 (hardware rendering and a USB-A test staged; charging re-read):**

- **Hardware rendering.** "Software Rendering" is a Mesa version gap:
  Ubuntu 26.04's Mesa 26.0.8 has no X2-85 entry, and Mesa **26.2**
  (`0xffff44070031`, both freedreno GL and turnip Vulkan) has one. Mesa
  26.2.3 is built as a normal user, hash-checked against its release notes,
  and staged on the USB. It installs under `/opt/mesa-glymur` beside
  Ubuntu's Mesa: per program with `mesa-glymur-run`, and for the whole
  desktop only after `mesa-glymur-run --desktop on`. See
  `docs/mesa-x2-85-2026-09-29.md`.
- **cpufreq at boot.** A boot service loads `scmi-cpufreq` only on device
  trees that carry the SCMI polling fix.
- **Charging.** The `-4` session's own capture shows the battery
  **charging at 40 W** over PD. Charging on the DT boot is intermittent,
  not absent, and `qcom-battmgr-ac`/`-usb` `ONLINE` do not track the
  charger. `charging-watch.sh` records the firmware's connector status and
  the UCSI tracepoints live. See `docs/usb-c-charging-2026-09-29.md`.

- **USB-A on device-tree boots (staged, untested).** A new entry, "device
  tree (GPU and USB-A test)", is the GPU test DT plus the right-hand USB-A
  port (`usb_2` in host mode and its two PHYs). HP's DSDT and PEP evidence
  map the port onto them. It needs no new kernel. If it works, installs
  from the stick no longer need an ACPI reboot. See
  `docs/usb-a-bringup-2026-09-29.md`.

Next:

1. Boot "device tree (GPU and USB-A test)".
2. If the stick shows up, run
   `sudo bash "/media/$USER/UBUNTU 26_0/glymur-tools/kernels/check-usb.sh"`,
   then `bash ".../install-from-usb.sh"` from the same directory. If it
   doesn't, run the installer from "ACPI, newest glymur kernel" instead.
3. Reboot into the same entry and run `bash ~/check-mesa.sh` on the
   desktop.
4. Run `sudo bash ~/charging-watch.sh`, then plug, unplug and replug,
   typing a note at each step.

**2026-09-29 (GPU and CPU frequency scaling both work, on the GPU test
DT):** booted kernel `7.3.0-rc2-glymur-5`'s "device tree (GPU test)" entry.
The Adreno X2-85 binds, loads GMU firmware (v5.2.38), needs no zap shader
(as on upstream Glymur boards), and `devfreq` actively scales it
310 MHz-1.35 GHz, with the display still live on the same boot. `modprobe
scmi-cpufreq` — which hung the laptop hard in lab run 1 — now falls back to
polling (the upstream SCMI completion-IRQ fix) and gives real frequency
policies up to 4.03 GHz. GL/Vulkan still show "Software Rendering": the
installed Mesa (`26.0.8`) has no hardware-table entry for this chip ID yet
— a userspace/Mesa version gap, not a kernel or DT problem. See
`docs/gpu-bringup-run1-2026-09-29.md`. Neither GPU nor cpufreq is carried
by the full/minimal DTs yet.

USB-C charging: five unplug/replug attempts on `-5` showed nothing in
sysfs or the kernel log, although the owner saw the charging LED light
once. The later entry above re-reads this with the `-4` capture.

**2026-09-29 (the eDP panel works):** kernel `7.3.0-rc2-glymur-4`
backports Qualcomm's posted v8 eDP PHY programming-sequence fix (Bjorn
Andersson, "phy: qcom: edp: Update v8 programming sequence", June 2026;
`patches/kernel/backports/`, `docs/edp-phy-backport-2026-09-29.md`) and it
works: booted on the **unmodified full DTS**, no `phy poweron failed`
anywhere in the log, link training succeeds on the first attempt at 2
lanes/2.7 Gb/s (the panel's own limit), `eDP-1` shows
`connected`/`enabled` at 1920x1200, and DP-AUX backlight control is live.
This is the first confirmed 2-lane 2.7 Gb/s training report for this
series (the only other public report, an ASUS Zenbook A16, trained at
5.4 Gb/s). Same boot: battery/AC/USB-C power supplies, Bluetooth, Wi-Fi,
and ADSP/CDSP all work; GPU stays safely disabled as designed; there is
still no audio, USB or TPM. See `docs/edp-display-working-2026-09-29.md`
and `docs/edp-phy-backport-2026-09-29.md`. The plain
"device tree (full)" entry (no `drm.debug`) also brings the display up.
USB-C charging does not work yet (cause open,
`docs/usb-c-charging-2026-09-29.md`). Next: audio (SoundWire/LPASS; the
ADSP is already up). Other upstream patches
worth taking next (PUSH_IDLE reset fix, SCMI polling for cpufreq, USB
votes) are in `docs/upstream-patch-survey-2026-09-29.md`.

**2026-09-29 (lane/rate mismatch ruled out; the fault is in the PHY
driver):** the boot-time eDP 2-lane test (below) came back dark. Its
journal shows the panel's own DPCD ceiling is exactly 2 lanes at 2.7 Gb/s —
the same limit the test DTB declares — so msm was never being held back by
the device tree. The failure is `phy phy-faac00.phy.2: phy poweron failed
--> -110`, thrown by the PHY driver itself before link training starts,
identical to the failure the display lab found independently
(`docs/display-lab-run3-2026-09-28.md`) in its own instrumented copy of the
driver. Two different code paths now show the same fault, so it is inside
`phy_qcom_edp_phy_power_on_v8()`/PLL configuration in
`drivers/phy/qualcomm/phy-qcom-edp.c`, not fixable from the DTS. Leading
hypothesis: a 10-register PLL coefficient mismatch between the driver's
hardcoded 2.7 Gb/s table and the firmware's live PLL values. The lab
already has (uncommitted, unbuilt) instrumentation — `lab_fw_pll` — that
substitutes the firmware's PLL values at power-on and four variants (W1-W4)
to test it; that needs a WSL rebuild and a fourth lab run. See
`docs/edp-2lane-test-run1-2026-09-29.md`.

**2026-09-29 (eDP 2-lane test staged):** the lab's display phase hung the
laptop twice, so the firmware's link configuration is now tested at boot
time with the stock drivers. The USB entry "Ubuntu on SSD: eDP test, 2
lanes (device tree)" boots the `-3` kernel with the full DT limited to 2
lanes at up to 2.7 Gb/s, the configuration the firmware runs. msm's retries
never reach it from the full DT's 4 lanes at up to 8.1 Gb/s. It adds DRM
DP debug logging. If the panel lights, the two endpoint properties go into
the full DTS. If it stays dark, wait three minutes before powering off, and
read `journalctl -k -b -1` from the next boot. The GRUB menu was also
cleaned up to 9 entries. See `docs/edp-2lane-test-2026-09-29.md`.

**2026-09-28 (first DT boots):** the minimal DT is the new working
baseline — CPUs, NVMe, native DT input, thermal, cpuidle and Wi-Fi, on the
firmware framebuffer. The full DT reaches userspace cleanly, with HP's
signed ADSP/CDSP firmware attached over the SoCCP, but the eDP panel stays
dark: an eDP link-training failure at the DP PHY (`ret=-11`, "max v_level
reached"), not the GPU-component issue the prior review already guarded
against. The two-rail regulator fix drafted that day is reverted (see
`docs/display-lab-2026-09-28.md`). The first lab run (kit staged from the USB, run on the lab boot) captured
the firmware's link and finished the Bluetooth test, but the laptop hung in
phase 4 when the lab loaded `scmi-cpufreq`, so no display variant ran. The
firmware drives the panel on **2 lanes at 2.7 Gb/s; our DT declares 4 lanes**
(`docs/display-lab-run1-2026-09-28.md`). The fixed kit is at
`~/glymur-lab-kit`. Next: on a display-lab boot, `sudo bash
~/glymur-lab-kit/start-lab.sh` again (phase 5 runs the DPCD dump and ten
variants), and try `data-lanes = <0 1>` in the full DT regardless. A DT boot still has no USB, GPU or audio. Keep booting the minimal DT
otherwise.
See `docs/device-tree-first-boot-2026-09-28.md` and
`docs/device-tree-review-2026-09-28.md`.

**2026-09-27 (first boot):** the qcom-next boot kernel (`7.3.0-rc2-glymur`)
is installed and booted on SSD partition 5, from the USB's GRUB (the SSD's
EFI partition stays untouched). Input, the EC bus/thermal/fan, and CPU idle
carry over from the stock-Ubuntu results, and Wi-Fi now fully associates.
USB-C, the native GPU, Bluetooth, audio, battery/AC/RTC, TPM, and CPU
frequency scaling remain gated behind the device-tree path. Next: fix or
work around the chrony/RTC ACPI-error journal flood, then continue the
device-tree work for the remaining subsystems. See
`docs/qcom-next-first-boot-2026-09-27.md` and
`docs/fan-thermal-windows-2026-09-27.md`.

**2026-09-26 (after reboot):** CPU core idle works with a BIOS-gated DSDT
`_OSC` fix, and the EC bus works over GPI DMA (thermal zones now read).
The remaining power gaps are CPU frequency scaling (no `_CPC`), cluster
idle, battery (PMIC GLink) and the GPU; these point to the device-tree
path. See `docs/cpuidle-and-ec-bus-results-2026-09-26.md`.

**2026-09-26 (live workstation):** the EC bus needs the QUP1 GPI DMA
engine. A derived ACPI GPI driver binds it and its command path works, but
the first live test lost the channels to `async_tx`. Retry after a reboot;
see `docs/ec-gsi-live-test-2026-09-26.md`.

**2026-09-26 (run 2):** the keyboard, touchpad, and touchscreen work under
the stock Ubuntu live kernel with two out-of-tree ACPI modules, and Wi-Fi
scans with HP board data. See `docs/acpi-input-results-run2-2026-09-26.md`.
Remaining gaps:

- the EC bus, which needs GPI DMA;
- battery and AC, and USB-C, via ADSP/PMIC GLink;
- GPU, audio, Bluetooth, suspend.


**2026-09-26:** a staged live-USB test loads two out-of-tree ACPI modules,
for GPIO/PDC interrupts and GENI I²C, into the stock Ubuntu kernel to bring
up the keyboard and touchpad. See `docs/acpi-input-test-2026-09-26.md` and
the audit in `docs/repository-audit-2026-09-26.md`, which supersedes the
clock-hazard reasoning in the next paragraph for qcom-next. Battery, AC, and
USB-C share one missing path: ADSP, then PMIC GLink, then the ABD
GenericSerialBus region.

Previous gate:

The HP UEFI/ACPI path reaches Linux userspace, but Ubuntu registered no I²C adapter. The `i2c_qcom_geni` module loaded without binding any of the five HP `QCOM0F10` controllers; Qualcomm's reviewed `qcom-next` driver also lacks that ACPI ID. Its clock and wrapper assumptions make an ID-only patch unsafe. The HP UCSI ACPI object reported `status=0`, with no USB-C class device. Trace and validate both resource paths before another target boot. Do not flash Qualcomm reference images or load another board's DTB.
