# qcom-next Boot Kernel, SSD Install and Log Review: September 27, 2026

## Kernel

- qcom-next `a47c4c5aa` with the layered series (`patches/README.md`)
  builds as `7.3.0-rc2-glymur` with `scripts/linux/build-qcom-next-glymur.sh`.
  Applying the checked-in patch files to a clean worktree
  (`prepare-qcom-next-glymur.sh`) reproduces the build tree exactly.
- NVMe, ext4, the ACPI table upgrade and simpledrm are built in, so the SSD
  root boots without an initramfs. The GPIO/PDC driver, GPI DMA, GENI I²C,
  I²C-HID and ath12k are modules and autoload from their ACPI IDs.
- The bring-up modules carry no board values: the pin and controller lists
  come from `boards/hp-omnibook-5-16-bf1xxx/kernel-cmdline.conf`.
- The release string gained a `+` because the tree is untagged; the build
  now passes an empty `LOCALVERSION` and checks that the release ends in
  `-glymur`.

This kernel has been built but not yet booted. The input and EC-bus logic
is ported from out-of-tree modules that were proven on stock Ubuntu 7.0.

## Review fixes to the series

- `gpi_acpi_request_chan()` treated "driver data set" as "engine ready",
  but `gpi_probe()` sets driver data before `dma_async_device_register()`.
  Because udev loads `gpi` and `i2c_qcom_geni` in parallel, the EC bus
  could take a channel from an engine still registering. The function now
  holds the engine's device lock and requires `device_is_bound()`.
- The GPIO driver's header claimed that the EC event interrupt (GPIO 66)
  was proven. It is untested: the lid test ran without pin 66. The claim
  was removed.
- Checked and found correct:
  - GED defers while the GPIO module is absent, and frees the IRQs it has
    already requested when it fails;
  - the I²C firmware-state gate runs before any firmware load;
  - the runtime-PM callbacks tolerate missing power hooks;
  - driver data is set before `resources_init`;
  - the GPI channel arguments (channel, SE, protocol) match the DT
    translation;
  - the GPIO driver matches the proven module except for comments and its
    default-empty pin list.

## SSD root

The owner created partition 5 in the unallocated gap between C: and
Recovery: 256 GiB, GPT type Linux filesystem. Nothing else on the SSD was
changed. `scripts/linux/glymur-ssd/`:

- `install-ssd-root.sh`, run from the RAM live desktop:
    - It refuses anything but a 150–300 GB Linux-type NVMe partition with
      no filesystem, identified by its GPT GUID, and asks the operator to
      type `INSTALL`.
    - It builds the root the way curtin builds the full "Ubuntu Desktop"
      source: `minimal`, then `minimal.standard`, then
      `minimal.standard.<lang>`. Language layers are deltas that delete
      the other languages; `minimal.<lang>` belongs to the minimized source
      and is not stacked.
    - Ubuntu is merged-`/usr`, so the modules are copied into
      `usr/lib/modules`. Extracting `./lib/...` with tar would replace the
      `/lib` symlink.
    - It never mounts the EFI partition. `grub-install` is diverted to a
      no-op, grub and shim packages are held, and fwupd is masked.
    - It imports the live sessions' persistent home from the USB's
      `casper-rw` into the new checkout's `.work/`. The mount is read-only
      with `noload`, because the stick lost power with a dirty journal.
      Kernel trees and caches are skipped, and credentials (logins,
      SSH/GPG keys, keyrings, app configuration) are never copied. Windows
      cannot read that partition: `wsl --mount` does not support USB flash
      drives, and a failed attempt leaves the disk offline in Windows.
- `glymur-boot-report.sh`, installed as `glymur-boot-report.service`,
  writes a bring-up report 60 s after every boot to
  `/var/log/glymur/boot-*.txt`:
    - driver bindings for the ACPI IDs, module parameters, I²C clients and
      input devices;
    - lid, fan, thermal zones and cpuidle;
    - network, the clock, failed units, kernel warnings and oops lines.

  It needs no login, so a boot with dead input still leaves evidence that
  the live USB can read from the SSD.
- `make-kit.sh` also writes `glymur-setup-ssd.sh` to the USB root, with the
  partition GUID filled in. In the live session, the whole install is
  `bash /cdrom/glymur-setup-ssd.sh`.
- `grub-entry.cfg` and `make-kit.sh`: GRUB on the USB reads the kernel from
  the SSD's `/boot`, found by filesystem label, and falls back to a copy on
  the USB. Root is `PARTUUID=`. The only initrd is the BIOS-gated `_OSC`
  override.

## Findings from the collected logs

- **TPM wait: 90 s per boot.** In the live inventory journal, systemd
  expects `dev-tpm0` and `dev-tpmrm0` at 36 s and times out at 126 s. The
  firmware's TPM2 table makes systemd's TPM2 generator wait, but start
  method 9 has no Linux driver. The board command line now carries
  `systemd.tpm2_wait=0`.
- **No RTC.** No `rtc0` registers. `\_SB.PRTC` (`ACPI000E`, `_GCP`
  `0x1F7`, real-time supported) implements `_GRT` and `_SRT` through
  `\_SB.PMGK` fields, which is the PMIC GLink path that battery and AC also
  need. Until the ADSP/GLink path works, the clock starts wrong, which
  explains the July 27 dates on live logs. qcom-next's `acpi_tad` can
  register an RTC class device, but its reads will fail until then. The
  SSD install sets `broken_system_clock` in `e2fsck.conf`; chrony sets the
  time over Wi-Fi.
- **No CPU frequency scaling under ACPI** (confirmed). No table has `_CPC`,
  `_PSS` or `_PCT`, so the cores run at the firmware's clock. The Windows
  fan profile now records `% Processor Performance` and the processor
  frequency, so the comparison shows this difference.
- `pd-mapper.service` fails because it expects DT remoteprocs. This is
  harmless and expected until the DT path.
- `Win32_Fan` has no instances on Windows. Fan RPM on Windows can come
  only from HP's `HPBIOS_BIOSNumericSensor` (elevated), if HP exposes it.

## Next

1. Windows fan profile, elevated: `scripts/windows/fan-thermal-profile.ps1`.
2. Install from the RAM live desktop, then boot "Ubuntu on SSD: qcom-next
   7.3.0-rc2-glymur".
3. On the SSD system: `scripts/linux/fan-thermal-profile.sh`, then check
   input, the EC bus, lid and EC events (GPIO 66, first test) and Wi-Fi on
   the new kernel.
