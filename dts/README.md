The HP OmniBook 5 16-bf1xxx device tree is in `qcom/`:

- `glymur-hp-omnibook-5-bf1xxx.dtsi`: the shared board description;
- `glymur-hp-omnibook-5-bf1xxx-minimal.dts`: storage, input, lid, Wi-Fi and
  Bluetooth on the firmware framebuffer, as a fallback;
- `glymur-hp-omnibook-5-bf1xxx.dts`: adds the eDP OLED, GPU, ADSP/CDSP and
  PMIC GLink.

It must not be created by copying another machine's DTS wholesale. Every
board value comes from this laptop's ACPI tables, PEP power tables, HP
driver pack or Windows device tree; the evidence for each one is in
`docs/device-tree-evidence-2026-09-27.md`. Qualcomm's `glymur.dtsi`
(qcom-next) describes the SoC.

`scripts/linux/build-qcom-next-glymur.sh` compiles these files against the
kernel tree it builds and ships the DTBs with the kernel;
`scripts/linux/glymur-ssd/install-kernel.sh` installs them under
`/boot/dtbs/<release>/`, where the USB's device-tree GRUB entries find them.
