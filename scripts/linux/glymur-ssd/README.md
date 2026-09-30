# SSD install and test scripts

Scripts for the Ubuntu 26.04 root on the internal SSD's Linux partition
(`glymur-root`), booted from the installer USB's GRUB. Most are staged on the
USB under `glymur-tools/kernels/` and run on the laptop.

## Installing

### `install-ssd-root.sh`

Installs Ubuntu 26.04 onto the empty SSD partition, run as root from the RAM
live desktop:

    sudo bash /cdrom/glymur-tools/ssd/install-ssd-root.sh <partition-guid>

Safety:
- It touches only the partition with the given GPT GUID, and only if all of
  these hold:
    - its type is Linux filesystem, it is 150-300 GB and it is on the
      internal NVMe;
    - it is not mounted and has no filesystem (or it is our own
      `glymur-root`, with `--reuse`);
    - the operator types `INSTALL`.
- It never mounts or writes the SSD's EFI partition and never installs a
  boot loader. It diverts `grub-install` in the target, so package upgrades
  cannot touch the EFI partition either.
- Windows (BitLocker C:) and Recovery are untouched.

How it builds the target:
- Like Ubuntu's installer (curtin) for the full "Ubuntu Desktop" source, it
  stacks the `minimal`, `minimal.standard` and `minimal.standard.<lang>`
  layers with overlayfs and copies them. Language layers are deltas that
  delete the other languages, and the live layer is excluded.
- Kernel modules are unpacked on the target filesystem, because they don't
  fit the live session's `/run` tmpfs. They go into `usr/lib`, because
  Ubuntu is merged-`/usr`.

Configuration:
- a real machine-id, so the first boot doesn't stop at firstboot prompts;
- the live session's locale, keyboard and time zone;
- NetworkManager for everything;
- a persistent journal;
- `fwupd` masked and the boot-loader packages held, per the owner's rules;
- `e2fsck` accepts superblock times "in the future". There is no RTC under
  ACPI (`\_SB.PRTC` reads through PMIC GLink, which isn't up), so the clock
  is wrong until chrony syncs.

It also installs `git` from the kit, and imports the live USB's persistent
home (read-only, `noload`) into `.work/`. Credentials, keys, keyrings and app
settings are never imported.

### `make-kit.sh`

Assembles what goes onto the USB's FAT partition for the SSD install:

| Path | Contents |
|---|---|
| `glymur-tools/ssd/` | `install-ssd-root.sh`, the kernel tarball, `SHA256SUMS` |
| `glymur-boot/` | `vmlinuz-<krel>` (fallback; GRUB prefers the SSD's copy) |
| `glymur-tools/acpi-override/acpi-override.cpio` | the BIOS-gated `_OSC` fix |
| `glymur-workstation/` | a repository bundle, `SHA256SUMS` |
| `grub-entry.cfg` | entries to append to `boot/grub/grub.cfg` |
| `MANIFEST.sha256` | every staged file |

    scripts/linux/glymur-ssd/make-kit.sh <glymur-kernel-*.tar.gz> <partition-guid> [out-dir]

The partition GUID and the output are private; keep them in `.work/`.
Environment variables:
- `DSDT_FIX_DIR` (default `.work/dsdt-osc-fix-F.06`);
- `DEBS_DIR` (default `.work/ssd-debs`: `git`, `git-man` and
  `liberror-perl`, fetched with `apt-get download` on an Ubuntu 26.04 arm64
  host).

### `install-from-usb.sh`

One command for any boot that can see the USB stick: an ACPI boot, or
"device tree (GPU and USB-A test)", whose USB-A port works. Run it as your
normal user; it asks for your password through sudo:

    bash "/media/$USER/UBUNTU 26_0/glymur-tools/kernels/install-from-usb.sh" [--keep-ubuntu-mesa] [kernel release]

It checks every file against `SHA256SUMS`, then installs:
- the kernel package, unless it is already the newest (default: the newest
  staged release);
- the Adreno GPU firmware;
- the newest Mesa build, and switches the system to it (`--keep-ubuntu-mesa`
  skips the switch);
- the scmi-cpufreq boot service;
- Ubuntu's test tools;
- lscpu from util-linux PR #4657 (Oryon-2), into `/usr/local`, when
  `lscpu-oryon2.tar.gz` is staged;
- the check scripts, into your home directory.

### `install-kernel.sh`

    sudo bash install-kernel.sh <glymur-kernel-*.tar.gz | build-output-dir>

Installs a kernel from `build-qcom-next-glymur.sh`, as its tarball or its
output directory. It rotates `/boot/vmlinuz-glymur` (booted by "ACPI, newest
glymur kernel") and `vmlinuz-glymur.old` (booted by "ACPI, previous glymur
kernel"), so nothing on the USB or the EFI partition changes. The device
trees go to `/boot/dtbs/<release>/` behind `/boot/glymur-dtb`, and the boot
report tool is refreshed.

Build with `GLYMUR_SUFFIX=-N` so every build has its own release. Installing
the running release is refused, because it would replace the live kernel's
modules.

### `install-firmware.sh`

    sudo bash install-firmware.sh

Installs HP's firmware from `boards/hp-omnibook-5-16-bf1xxx/firmware`
(checked against its `MANIFEST.tsv`) into `/usr/lib/firmware/updates`, so no
packaged file is replaced:
- **ADSP and CDSP:** `qcom/glymur/HP/omnibook-5-16-bf1xxx/` gets the images,
  dtbs and `.jsn` files, at the `firmware-name` paths in the DTS.
- **Bluetooth (QCC2072):** `qca/ornbtfw11.tlv` and `qca/ornnv11.*` are HP's
  "Colorado" `clnbtfw10.tlv`/`clnbtnv10.*` under btqca's "Orion" names.
    - The "10" in HP's names is not the ROM version: the patch header says
      ROM build 0x0101, the ROM 1.1 the controller reports. So btqca asks for
      `ornbtfw11.tlv` and `ornnv11.b<board>`; board 0x17 has its own HP file.
    - These override linux-firmware's generic ROM-1.1 pair with the files
      Windows uses on this laptop. Earlier versions of this script used ROM-10
      names, which btqca never asks for.

### `install-mesa.sh`

    sudo bash install-mesa.sh mesa-glymur-<version>.tar.gz
    mesa-glymur-run eglinfo -B

Installs the Mesa from `build-mesa-glymur.sh` under `/opt/mesa-glymur`, next
to Ubuntu's Mesa, plus `/usr/local/bin/mesa-glymur-run`, which runs one
program with it.

To switch the whole system (login screen, GNOME Shell, Xwayland, every
program), run `sudo mesa-glymur-run --system on`, then reboot.
- It puts `/opt/mesa-glymur` ahead of Ubuntu's Mesa for the dynamic linker
  (`/etc/ld.so.conf.d/00-mesa-glymur.conf`) and adds its Vulkan driver.
- To undo it, log in on a text console (Ctrl+Alt+F3) and run `--system off`.
- `--system status` reports the current state.
- `--desktop on|off` is the older per-user switch (environment.d). It never
  reached GNOME Shell.

### `install-cpufreq-service.sh`, `install-gpu-firmware.sh`

These install the boot service that loads scmi-cpufreq when the device tree
has the SCMI polling fix, and linux-firmware's `gen80100` GPU firmware.

## Checking

All of these write their reports to `/var/log/glymur/` or `~/glymur-logs/`.

### `check-usb.sh`

    sudo bash check-usb.sh [--previous]

The USB report for "device tree (GPU and USB-A test)". It covers:
- the USB-A port (`usb_2`);
- the USB-C ports: `usb_0` next to the hinge, `usb_1` away from it;
- the camera's controller (`usb_hs`, from `-8`);
- the SPMI PMICs and eUSB2 repeaters (from `-8`);
- full kernel warnings;
- Type-C partners, the topology with each device's controller, and block
  devices.

`--previous` reports on the previous boot's kernel log instead, for when
this boot has no working USB.

Before running it, plug in what you have: a USB stick, hub or phone in each
USB-C port, and a mouse in each port in turn.
- On `-7`, a mouse (low or full speed) failed on all three ports.
- `-8` adds the USB-C repeaters. On USB-A, a mouse is still expected to fail.
- A charger makes its port a sink and USB device, which is correct.

### `check-ec.sh`

    sudo bash check-ec.sh

The embedded-controller report for "device tree (GPU and USB-A test)",
from kernel `-9` (`docs/ec-2026-09-30.md`):
- the EC bus (`i2c9`, `0xa84000`) and the `hp-omnibook-5-ec` driver in the
  kernel log;
- the fan speed and the four EC thermistors, five samples 2 s apart;
- full kernel warnings;
- the keyboard backlight timeout (`kbd_backlight_timeout`, from `-10`):
  it tries `30s` and `always` and asks whether the backlight went off;
- the F6/F9 mute LEDs (`platform::mute`, `platform::micmute`): it asks
  what Windows last had muted and what is lit, then lights each LED alone;
- a 30 s key capture while you press F6, F9, F11, F5 and Fn, from the
  keyboard, the consumer-control device and the EC hotkeys device.

Run it at a terminal on the desktop; it waits for your answers.

If the driver did not bind, it sends HP's read commands by hand with
`i2ctransfer` (from `i2c-tools`), and nothing that changes the EC's
state.

To set the keyboard backlight timeout by hand (`30s`, `3min` or `always`):

    echo always | sudo tee /sys/bus/i2c/devices/9-0076/kbd_backlight_timeout

### `charging-watch.sh`

    sudo bash charging-watch.sh

Watches USB-C charging live until you type `q`. Type a note and press Enter
whenever something happens ("unplugged", "LED on"); notes are timestamped
into the same log as the machine state. It records:
- every change of the Type-C ports, the UCSI and battmgr power supplies, and
  the battery status (with a heartbeat every 30 s);
- the firmware's own connector status, polled every 2 s through the UCSI
  debugfs command interface (read-only `GET_CONNECTOR_STATUS`), so a missed
  notification can't hide it;
- the UCSI tracepoints and debug messages from `ucsi_glink`, `typec_ucsi`,
  `pmic_glink` and `qcom_battmgr`.

The background readers run as separate process groups, and cleanup (or a
watchdog, if the script dies) kills the whole groups. On 2026-09-30 a `cat
trace_pipe | while read` pair outlived the script and set off hung-task
warnings (`docs/usb-c-charging-2026-09-29.md`).

### `gpu-corruption-test.sh`

    bash gpu-corruption-test.sh

Run it from a text console (Ctrl+Alt+F3), as yourself; it needs `kmscube`.
kmscube renders on the GPU and scans out through KMS, the same path as GNOME
Shell. After each 8-second case, you answer whether the screen was clean.

| Case | Setting | Meaning |
|---|---|---|
| 1 | `FD_MESA_DEBUG=sysmem` | no GMEM (the clean reference) |
| 2 | default | GMEM size from the kernel |
| 3 | `FD_MESA_GMEM` = 15.75 MB | the size for 3 slices |
| 4 | half of that | a safe under-estimate |

On `-6`, only case 2 was corrupted. On `-7`, which has the GMEM fix, all four
are clean (`docs/gpu-corruption-2026-09-30.md`).

### `check-gpu-test.sh`, `check-mesa.sh`

    sudo bash check-gpu-test.sh [--charging] [--cpufreq]
    bash check-mesa.sh

`check-gpu-test.sh` is the one-boot check for "device tree (GPU test)": GPU,
display, CPU frequency scaling and charging. Run `--cpufreq` only with
nothing unsaved: loading scmi-cpufreq without the polling fix hung the laptop
in lab run 1. `check-mesa.sh` checks which Mesa each program and GNOME Shell
use.

### `glymur-boot-report.sh`

Run by `glymur-boot-report.service` 60 s after each boot; it writes
`/var/log/glymur/boot-*.txt`.
