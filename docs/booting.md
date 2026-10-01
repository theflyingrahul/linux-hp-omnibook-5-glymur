# Booting Linux on the HP OmniBook 5 16-bf1xxx

## Disclaimer

**Read this first.**

- This is an unofficial, experimental bring-up. It is not affiliated with,
  endorsed by or supported by HP, Qualcomm or Canonical.
- It has run on exactly one laptop: a 16-bf1107nr (product `D3ZN3UA`,
  Snapdragon X2 Elite X2E-84-100, 32 GB) with BIOS F.06. Other models,
  CPUs, memory sizes, panels and BIOS versions are untested.
- The device tree describes this board's pins and power rails. Never use it
  on a different laptop, and never boot another machine's device tree on
  this one.
- You will repartition the internal SSD. A mistake there can destroy
  Windows and your data. Back up first and keep your BitLocker recovery key
  somewhere off the laptop.
- Things that do not work yet include audio, suspend, the NPU, full- and
  low-speed USB-C devices, and the TPM (see [`status.md`](status.md)).
  Closing the lid does not suspend; shut down instead.
- Everything here is provided as is, without warranty of any kind (see
  [`LICENSE`](../LICENSE)). You are responsible for what you run on your
  machine.
- This is a developer setup, not an installer. Expect to read the scripts
  and adapt them. If a step fails, stop and open an issue rather than
  improvising on the SSD.

## How it boots

```
USB stick (right-hand USB-A port)        internal SSD
  Ubuntu 26.04 installer's GRUB  --->   Linux partition (ext4, "glymur-root")
  + this project's entries                /boot/vmlinuz-glymur   kernel
                                          /boot/glymur-dtb/      device trees
                                          /                      Ubuntu 26.04
```

- The USB stick holds the only boot loader that knows about Linux: the
  Ubuntu installer's GRUB, with this project's menu entries added after the
  stock ones.
- GRUB loads the kernel and the device tree from the Linux partition on the
  SSD and boots it directly (no initramfs; NVMe and ext4 are built in).
- The SSD's EFI partition, Windows and Recovery are never written. Without
  the stick, the laptop boots Windows as before.
- The stick has to stay in the right-hand USB-A port to boot Linux. It is
  the port that works in every boot mode.

There are no prebuilt downloads yet: you build the kernel yourself.

## What you need

- The laptop described above, with Windows installed and BitLocker's
  recovery key saved elsewhere.
- **Secure Boot off.** GRUB refuses a self-built, unsigned kernel when it
  is on. It was already off on the tested laptop. Changing it is your
  decision; BitLocker may then ask for the recovery key at the next Windows
  boot.
- A USB stick of 16 GB or more. The tested one is a 64 GB stick written
  with Rufus (a FAT32 partition plus a persistence partition).
- 150 to 300 GB of free space on the SSD for Linux.
- An arm64 Linux machine to build the kernel, such as WSL with Ubuntu 26.04
  on the laptop itself (what the project uses), or the laptop's own Linux
  install later on.

## Steps

### 1. Make room on the SSD (Windows)

1. Back up. Save the BitLocker recovery key off the laptop.
2. In Disk Management, shrink C: to leave 150–300 GB unallocated.
3. In an elevated PowerShell, create the Linux partition in that space,
   unformatted, with the GPT type "Linux filesystem". Check the disk number
   with `Get-Disk` first; the internal NVMe is usually disk 0:

       New-Partition -DiskNumber 0 -Size 256GB -GptType '{0FC63DAF-8483-4772-8E79-3D69D8477DE4}'

4. Note the new partition's GUID; the installer and GRUB find it by that:

       Get-Partition -DiskNumber 0 | Select-Object PartitionNumber, Size, GptType, Guid

   Keep the GUID private: it identifies your disk.

### 2. Build the kernel

On the arm64 build machine, from this repository
([`scripts/linux/README.md`](../scripts/linux/README.md) has the details):

    bash scripts/linux/setup-native-kernel-build.sh ~/src
    GLYMUR_SUFFIX=-1 bash scripts/linux/build-qcom-next-glymur.sh \
        ~/src/linux-qcom-next-glymur ~/src/build-glymur "$(nproc)"

The first fetches Qualcomm's qcom-next kernel at the pinned commit and
applies `patches/kernel/`. The second builds the kernel and the device trees
and writes a `glymur-kernel-7.3.0-rc2-glymur-1.tar.gz` package. Give every
build its own `GLYMUR_SUFFIX`.

The GPU also needs Mesa newer than Ubuntu 26.04's:
`scripts/linux/build-mesa-glymur.sh`.

### 3. Prepare the USB stick

1. Write the Ubuntu 26.04 ARM64 desktop image to the stick with Rufus.
   Back up the stick's `boot/grub/grub.cfg` before changing it.
2. Build the live-session input modules. Stock Ubuntu has no internal
   keyboard, touchpad or touchscreen on this laptop, and the only working
   USB port holds the stick. `scripts/linux/glymur-acpi-input/`
   ([README](../scripts/linux/glymur-acpi-input/README.md)) builds them for
   the live image's kernel (`7.0.0-30-generic` on the tested image; a
   different image needs a rebuild) and stages them with the
   "Glymur workstation" boot entry.
3. Stage the Wi-Fi files, which the live session and the SSD installer
   both need:
    - linux-firmware's `ath12k/QCC2072/hw1.0/firmware-2.bin`, at
      `glymur-tools/firmware/ath12k/QCC2072/hw1.0/` on the stick;
    - a `board-2.bin` with HP's board data, built by
      `scripts/linux/ath12k-board-add.py` from
      `boards/hp-omnibook-5-16-bf1xxx/firmware/` and passed to the input
      kit's `make-kit.sh`, which puts it in `glymur-tools/acpi-input/wifi/`.
      It contains HP's file: do not publish it.
4. Generate the ACPI override for the ACPI boot entry (the first boot) from your own
   DSDT and BIOS version, with `scripts/linux/glymur-dsdt-osc-fix.py`.
5. Assemble the SSD kit:

       DSDT_FIX_DIR=<override dir> \
           scripts/linux/glymur-ssd/make-kit.sh glymur-kernel-*.tar.gz <partition GUID> <out-dir>

   ([README](../scripts/linux/glymur-ssd/README.md)). Copy `<out-dir>` to the
   stick's FAT partition, and append its `grub-entry.cfg` to the stick's
   `boot/grub/grub.cfg`, after the stock entries. Leave the stock
   "Try or Install Ubuntu" entry first and unchanged.
6. Check the copied files against the kit's `MANIFEST.sha256`.

### 4. Install Ubuntu onto the Linux partition

1. Boot from the stick (the BIOS boot menu) and choose
   "Glymur workstation".
2. In a terminal:

       sudo bash /cdrom/glymur-tools/ssd/install-ssd-root.sh <partition GUID>

   It refuses any partition that is not an empty 150–300 GB Linux-type
   partition on the internal NVMe, asks you to type `INSTALL`, then asks
   for a user name and password. It never touches the EFI partition,
   Windows or Recovery, and it disables `grub-install` and firmware updates
   inside the new system.

### 5. First boot: ACPI

The installer puts only the kernel on the SSD, not the device trees, so the
first boot uses ACPI:

1. Reboot, keep the stick in, and choose
   **Ubuntu on SSD: ACPI (no device tree)**. Keyboard, touchpad and Wi-Fi
   work; the display runs on the firmware's framebuffer.
2. Connect to Wi-Fi, install `git` if it is missing
   (`sudo apt install git`), and clone this repository.
3. Install HP's firmware for the audio/sensor DSP (which also carries the
   battery and USB-C), the compute DSP and Bluetooth:

       sudo bash scripts/linux/glymur-ssd/install-firmware.sh

4. Install the GPU firmware from linux-firmware (`qcom/gen80100_sqe.fw` and
   `qcom/gen80100_gmu.bin`), Mesa, and the CPU frequency service, with
   `install-gpu-firmware.sh`, `install-mesa.sh` and
   `install-cpufreq-service.sh` in `scripts/linux/glymur-ssd/`
   ([README](../scripts/linux/glymur-ssd/README.md)).

### 6. Install the device trees

`install-kernel.sh` installs a kernel together with its device trees, and
points the boot entries at them. It refuses to replace the running kernel,
so build a second one with a new suffix, either on the laptop (now running
Linux) or on your build machine:

    bash scripts/linux/setup-native-kernel-build.sh ~/src
    GLYMUR_SUFFIX=-2 bash scripts/linux/build-qcom-next-glymur.sh \
        ~/src/linux-qcom-next-glymur ~/src/build-glymur "$(nproc)"
    sudo bash scripts/linux/glymur-ssd/install-kernel.sh ~/src/build-glymur

Then reboot and choose **Ubuntu on SSD**. Every later kernel installs the
same way, and the one before it stays available as "previous kernel".

## The boot menu

| Entry | Use it for |
|---|---|
| Ubuntu on SSD | daily use: everything that is proven |
| Ubuntu on SSD: test device tree | the daily tree plus items under test |
| Ubuntu on SSD: previous kernel | going back after a bad kernel |
| Ubuntu on SSD: fallback, firmware display (minimal device tree) | if the display or GPU fails |
| Ubuntu on SSD: ACPI (no device tree) | last resort; fewer devices |
| Glymur workstation | the live session from the stick |

If a boot hangs, hold the power button to switch off and pick another
entry. For display problems, press `e` on an entry and add
`drm.debug=0x102` to the `linux` line.

## Reporting what happened

See [`CONTRIBUTING.md`](../CONTRIBUTING.md#reporting-a-result). The boot
report in `/var/log/glymur/` and the check scripts in
`scripts/linux/glymur-ssd/` collect most of what is needed.
