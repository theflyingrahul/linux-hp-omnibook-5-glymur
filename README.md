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

**2026-09-28 (first DT boots):** the minimal DT is the new working
baseline — CPUs, NVMe, native DT input, thermal, cpuidle and Wi-Fi, on the
firmware framebuffer. The full DT reaches userspace cleanly, with HP's
signed ADSP/CDSP firmware attached over the SoCCP, but the eDP panel stays
dark: an eDP link-training failure at the DP PHY (`ret=-11`, "max v_level
reached"), not the GPU-component issue the prior review already guarded
against. A DT boot still has no USB, GPU or audio. Next: root-cause the
link-training failure (check `vdda-phy`/`vdda-pll` supplies and the
panel's link rate/lane count against the Glymur/Mahua CRD reference), and
keep booting the minimal DT meanwhile. See
`docs/device-tree-first-boot-2026-09-28.md` and
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
