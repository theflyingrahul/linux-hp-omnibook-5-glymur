# A Daily Device Tree and a Shorter Boot Menu: September 30, 2026

Until kernel `-10`, each new capability got its own device tree layered on
the last: full, then GPU test, then "GPU and USB-A test", which was what
the owner actually booted every day. The USB menu had grown to ten entries.
From kernel `-11`, what is proven goes into one daily device tree, and what
is being tested goes into one test device tree on top of it.

## The device trees (kernel `-11`)

| DTB | Contents | Status |
|---|---|---|
| `mahua-hp-omnibook-5-bf1xxx` (daily) | eDP panel (`-4`), GPU and SCMI polling fix for CPU frequency scaling (`-5`, `-7`), ADSP/CDSP and PMIC GLink: battery, AC, USB-C charging (`-6`), USB-A, both USB-C ports at high speed and SuperSpeed (`-6`), the camera's `usb_hs` (`-8`), the EC: fan, thermistors, mute LEDs, backlight timeout and level (`-9`, `-10`) | proven, except as noted below |
| `-test` | the daily tree plus the SMB2370 eUSB2 repeaters on SID 9/10 (full and low speed on USB-C, `docs/eusb2-repeater-2026-09-30.md`) and the EC event line with HP's pull-up (`docs/ec-2026-09-30.md`) | in test |
| `-minimal` | the daily tree without the native display and the GPU: the firmware framebuffer, with USB and the EC still on | fallback |

Removed: `-gpu.dts` and `-usb.dts`, now the daily tree. The display-lab
and eDP 2-lane trees stay for `scripts/linux/glymur-lab/`, and the lab tree
turns the GPU off again, as it had it.

Changes against `-10`'s "GPU and USB-A test" tree, all checked in the
compiled DTBs:
- the USB-C repeaters moved to the test tree: USB-C high speed and
  SuperSpeed were proven on `-6`/`-7` without them, and with them no USB-C
  device has been plugged in yet;
- the third SMB2370 (SID 11) is not declared: on `-10` it failed its probe
  with an SPMI transaction error and a kernel warning, so no PMIC is there;
- the EC event line moved to the test tree;
- the GPU is now described as Mahua's Adreno X2-85 (`mahua.dtsi`, from
  `backports/0014`), in every tree (`docs/mahua-gpu-2026-09-30.md`). This
  one is not yet proven on this laptop: it is Qualcomm's reviewed
  description of this chip, and `-10` stays bootable as the previous
  kernel;
- GPIO allow-lists: the daily tree uses 26 pins, the test tree 27 (adds
  GPIO 66), the minimal tree 23 (eDP pins 18, 70, 119 reserved). All three
  pass `check-dt-gpio-allowlist.py`.

## The boot menu (USB `boot/grub/grub.cfg`)

| Entry | Kernel, device tree |
|---|---|
| Try or Install Ubuntu, Boot from next volume, UEFI Firmware Settings | stock, unchanged, first |
| **Ubuntu on SSD** | newest kernel, daily device tree |
| Ubuntu on SSD: test device tree | newest kernel, test device tree |
| Ubuntu on SSD: previous kernel | `vmlinuz-glymur.old` with its own daily device tree (`glymur-dtb.old`) |
| Ubuntu on SSD: fallback, firmware display (minimal device tree) | newest kernel, minimal device tree |
| Ubuntu on SSD: ACPI (no device tree) | newest kernel, board command line, DSDT `_OSC` override |
| Glymur workstation | the live USB with persistence |

Removed: device tree (minimal), (full), (full, DRM debug), (GPU test),
(GPU and USB-A test), and ACPI previous kernel. For DRM debugging, edit an
entry at the menu (`e`) and add `drm.debug=0x102`.

Kernels before `-11` ship no daily DTB with USB; their "GPU and USB test"
DTB is the same configuration, so the daily and previous-kernel entries
use `…-usb.dtb` when the kernel's DTB directory has one. That keeps `-10`
bootable with its proven tree, both before `-11` is installed and as the
previous kernel afterwards. The test entry needs `-11`.

The template is `scripts/linux/glymur-ssd/grub-entry.cfg`.
