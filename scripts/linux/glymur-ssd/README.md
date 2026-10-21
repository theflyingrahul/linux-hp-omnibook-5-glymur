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
home (read-only, `noload`) into `.work/`. Hidden files and directories, which
hold credentials, keys and app settings, are never imported.

### `make-kit.sh`

Assembles what goes onto the USB's FAT partition for the SSD install:

| Path | Contents |
|---|---|
| `glymur-tools/ssd/` | `install-ssd-root.sh`, the kernel tarball, `SHA256SUMS` |
| `glymur-boot/` | `vmlinuz-<krel>` (fallback; GRUB prefers the SSD's copy) |
| `glymur-tools/acpi-override/acpi-override.cpio` | the BIOS-gated `_OSC` fix |
| `glymur-workstation/` | with `REPO_BUNDLE=1`: this checkout as a bundle, and `SHA256SUMS` |
| `grub-entry.cfg` | entries to append to `boot/grub/grub.cfg` |
| `MANIFEST.sha256` | every staged file |

    scripts/linux/glymur-ssd/make-kit.sh <glymur-kernel-*.tar.gz> <partition-guid> [out-dir]

The partition GUID and the output are private; keep them in `.work/`.
Environment variables:
- `DSDT_FIX_DIR` (default `.work/dsdt-osc-fix-F.06`);
- `REPO_BUNDLE` (default `0`; `1` bundles this checkout, `.work` included, for
  the live session and the SSD install);
- `DEBS_DIR` (default `.work/ssd-debs`: `git`, `git-man` and
  `liberror-perl`, fetched with `apt-get download` on an Ubuntu 26.04 arm64
  host).

### `install-from-usb.sh`

One command for any boot that can see the USB stick: an ACPI boot, or
any device-tree boot of kernel `-10` or later, whose USB ports work. Run it as your
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
- the audio topology and UCM profile (`install-audio.sh`), when `audio/` is
  staged;
- HP's video firmware (`qcvss8480.mbn`), when `hp-fw/` is staged;
- the check scripts, into your home directory.

### `install-kernel.sh`

    sudo bash install-kernel.sh <glymur-kernel-*.tar.gz | build-output-dir>

Installs a kernel from `build-qcom-next-glymur.sh`, as its tarball or its
output directory. It rotates `/boot/vmlinuz-glymur` (booted by "Ubuntu on
SSD" and the test, fallback and ACPI entries) and `vmlinuz-glymur.old`
(booted by "Ubuntu on SSD: previous kernel"), so nothing on the USB or the
EFI partition changes. The device
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
- **Video (Iris):** `qcvss8480.mbn` into the same directory (from kernel
  `-15`'s test device tree).
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

The USB report for the device-tree boots. It covers:
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

The embedded-controller report, from kernel `-9`; the event line needs
"Ubuntu on SSD: test device tree" (`docs/ec-2026-09-30.md`):
- the EC bus (`i2c9`, `0xa84000`) and the `hp-omnibook-5-ec` driver in the
  kernel log;
- the fan speed and the four EC thermistors, five samples 2 s apart;
- full kernel warnings;
- the keyboard backlight timeout (`kbd_backlight_timeout`, from `-10`):
  it tries `30s` and `always` and asks whether the backlight went off;
- the keyboard backlight level (`kbd_backlight_level`, from `-11`,
  read-only): it reads it after each of three F5 presses;
- the F6/F9 mute LEDs (`platform::mute`, `platform::micmute`): it asks
  what Windows last had muted and what is lit, then lights each LED alone;
- the EC event line: its interrupt count and GPIO 66's state;
- a 30 s key capture while you press F6, F9, F11, F5 and Fn, from the
  keyboard, the consumer-control device and the EC hotkeys device;
- the keyboard's HID report descriptor, read-only.

Run it at a terminal on the desktop; it waits for your answers.

If the driver did not bind, it sends HP's read commands by hand with
`i2ctransfer` (from `i2c-tools`), and nothing that changes the EC's
state.

To set the keyboard backlight timeout by hand (`30s`, `3min` or `always`):

    echo always | sudo tee /sys/bus/i2c/devices/9-0076/kbd_backlight_timeout

### `install-audio.sh`, `check-audio.sh`

    sudo bash install-audio.sh
    sudo bash check-audio.sh

The speaker and microphone userspace and test
(`docs/audio-headset-path-2026-10-17.md`). The sound card itself is in the
test device tree, which comes with the kernel package from `-14` on.
`install-audio.sh` takes `audio/` next to it: the AudioReach topology built
from `boards/hp-omnibook-5-16-bf1xxx/audio/` and the ALSA UCM profile from
`boards/hp-omnibook-5-16-bf1xxx/audio/ucm2/`. The kernel asks for
`qcom/glymur/<sound card model>-tplg.bin`; as in linux-firmware, the file
goes into a board directory
(`/usr/lib/firmware/updates/qcom/glymur/HP/omnibook-5-16-bf1xxx/`) with a
link at that name, under `updates/` like the HP firmware, so no package's
file is touched. It removes the `-13` test's topology
(`HP-OmniBook-5-16-bf1xxx-tplg.bin`). The UCM files go to
`/usr/share/alsa/ucm2/` as new files only: it refuses to replace a file the
`alsa-ucm-conf` package owns. Without a UCM profile PipeWire shows "Dummy
Output", because every path of a Qualcomm ASoC card starts switched off in
the mixer; no `alsa-ucm-conf` release has Glymur profiles yet (upstream
`master` has them, Ubuntu 26.04 ships 1.2.15.3). Then boot "Ubuntu on SSD:
test device tree".

`install-audio.sh` also installs the WirePlumber rule from
`boards/hp-omnibook-5-16-bf1xxx/audio/wireplumber/` to
`/etc/wireplumber/wireplumber.conf.d/`, which gives the card and its two
devices the names Windows uses ("Internal Speakers" and "Microphone Array" on
"Qualcomm(R) Aqstic(TM) ACX Static Endpoints Audio Device").

`check-audio.sh` lists every SoundWire device that attached (named
link:manufacturer:part:version:unique id, also when no device-tree node
matches), the amplifier reset candidates (LPASS TLMM GPIOs 12 and 13, TLMM
GPIOs 204 and 205; direction and function only), the audio modules and
kernel log, the ALSA card, the UCM profile as `alsaucm` parses it,
PipeWire's view and names (`wpctl status`, `pw-dump`), and the mute
switches, their `ctl-led` binding and the F6/F9 LEDs. Only when asked, it
records 5 s from the microphones and plays a 1 kHz tone at -20 dBFS on the
left, then the right speaker, both through PipeWire as the desktop user
(the card belongs to PipeWire, so raw ALSA access is busy); mutes the
speakers and then the microphones from software, asks which LED is lit and
checks that a recording made while muted is silent (the mute switches are
UCM-created controls, so PipeWire must still mute the samples);
and asks for F6 and F9 presses, recording the mute state, the LEDs and the
EC interrupt count across F9. It no longer unbinds the amplifier driver,
which crashed kernel `-14` (`docs/audio-mute-leds-2026-10-20.md`). The log
goes to `/var/log/glymur/audio-test-*.txt`.

### `watch-audio.sh`

    sudo bash watch-audio.sh [seconds]

Leave it running while using the laptop (default 30 minutes). It logs the
speaker amplifiers' SoundWire status and runtime-PM state, the SoundWire
master's, and the L15B/L18B rails once a second whenever one changes, with a
full dump (reset line, rail use counts, the last kernel messages about
SoundWire, the amplifiers and the APM) at each change, and turns on the
SoundWire and `wsa884x` driver debug messages through dynamic debug. It is
how to find what makes the amplifiers leave the bus
(`docs/audio-speakers-down-2026-10-21.md`). The log goes to
`/var/log/glymur/audio-watch-*.txt`.

### `check-video.sh`

    sudo bash check-video.sh

The Iris video decoder, from kernel `-15`'s test device tree
(`docs/video-iris-2026-10-20.md`): the firmware file, the kernel log, the
V4L2 devices and their formats, then a 10 s 1080p H.264 clip generated
with `ffmpeg` and decoded in software and with the hardware decoder
(`h264_v4l2m2m`), with the time and CPU each took. It needs `v4l-utils`
and `ffmpeg` (`sudo apt install v4l-utils ffmpeg`). The log goes to
`/var/log/glymur/video-test-*.txt`.

### `check-display.sh`

    sudo bash check-display.sh

External displays over USB-C, from kernel `-15`'s test device tree
(`docs/external-display-2026-10-20.md`): the DRM connectors and their
modes, each USB-C port's partner and alternate modes (DisplayPort is SVID
`ff01`), the DisplayPort and alt-mode kernel log, and the monitors GNOME
uses. Run it with nothing plugged in, then with a monitor or a USB-C to
DisplayPort/HDMI adapter on one port, then on the other. The log goes to
`/var/log/glymur/display-test-*.txt`.

### `check-battmgr-notify.sh`

    sudo bash check-battmgr-notify.sh [seconds]

From kernel `-13`. While you plug and unplug the charger (60 s by
default), it counts calls to `qcom_battmgr_state_callback`, which
`backports/0023` adds for the Glymur firmware's state notifications
(pmic_glink owner 32782), and to the regular `qcom_battmgr_callback`, with
the function tracer in its own tracing instance. It prints the battmgr AC,
USB and battery state every 10 s. Calls to the state callback on each plug
confirm the patch's premise on this laptop; none means the firmware does
not send them here. The log goes to `/var/log/glymur/battmgr-notify-*.txt`.

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

`check-gpu-test.sh` is the one-boot check of the GPU,
display, CPU frequency scaling and charging. Run `--cpufreq` only with
nothing unsaved: loading scmi-cpufreq without the polling fix hung the laptop
in lab run 1. `check-mesa.sh` checks which Mesa each program and GNOME Shell
use.

### `glymur-boot-report.sh`

Run by `glymur-boot-report.service` 60 s after each boot; it writes
`/var/log/glymur/boot-*.txt`.

### `check-hotkeys.sh`

    sudo bash check-hotkeys.sh

From kernel `-16`. Asks for one special key at a time (F9 twice, F11 twice,
F6, F5, Fn alone, the Copilot key), ending each step with Enter, and prints
the key codes the kernel saw from the keyboard, the touchpad's consumer
collection, the EC input device and `gpio-keys`. It settles which key sends
what, for the mic-mute work (`docs/runbook-results-16-2026-10-21.md`). The
log goes to `/var/log/glymur/hotkeys-*.txt`.
