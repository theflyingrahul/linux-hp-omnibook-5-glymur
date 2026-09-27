The HP OmniBook 5 16-bf1xxx device tree is in `qcom/`:

- `mahua-hp-omnibook-5-bf1xxx.dtsi`: the shared board description;
- `mahua-hp-omnibook-5-bf1xxx-minimal.dts`: storage, input, lid, Wi-Fi and
  Bluetooth on the firmware framebuffer, as a fallback;
- `mahua-hp-omnibook-5-bf1xxx.dts`: adds the eDP OLED, ADSP/CDSP and PMIC
  GLink (battery, AC) through the SoCCP.

The SoC is Mahua (HP's DSDT `SDFE` 0xA8), described by Qualcomm's
`mahua.dtsi`, which itself builds on `glymur.dtsi`.

It must not be created by copying another machine's DTS wholesale. Every
board value comes from this laptop's ACPI tables, PEP power tables, HP
driver pack or Windows device tree. The evidence is in
`docs/device-tree-evidence-2026-09-27.md`, corrected by
`docs/device-tree-review-2026-09-28.md`.

`scripts/linux/build-qcom-next-glymur.sh` compiles these files against the
kernel tree it builds, checks each DTB with
`scripts/linux/check-dt-gpio-allowlist.py`, and ships the DTBs with the
kernel. `scripts/linux/glymur-ssd/install-kernel.sh` installs them under
`/boot/dtbs/<release>/`, where the USB's device-tree GRUB entries find them.
