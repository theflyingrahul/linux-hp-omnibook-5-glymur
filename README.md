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

**2026-09-29 (eDP PHY fix staged as kernel `-4`, untested):** the eDP
PHY's `-110` matches a Glymur v8 bug that Qualcomm describes. Their posted
fix (Bjorn Andersson, "phy: qcom: edp: Update v8 programming sequence",
June 2026) says the PLL does not lock at 1.62 or 2.7 Gb/s without it, and
this panel tops out at 2.7 Gb/s. On an ASUS Zenbook A16 the same series
cleared the same `-110`, and that panel then trained at 5.4 Gb/s. Training
at 2-lane 2.7 Gb/s with it has not been reported. It is backported in
`patches/kernel/backports/` and built into `7.3.0-rc2-glymur-4`, now on the
USB. The minimal DT is now the lab configuration: full DT minus the native
display, which adds battery and AC over PMIC GLink. The ADSP/CDSP boot, but
there is still no audio, USB, GPU or TPM. Next: from
"Ubuntu on SSD: ACPI, newest glymur kernel", install `-4` from the USB,
then boot "device tree (full, DRM debug)". See
`docs/edp-phy-backport-2026-09-29.md`.

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
