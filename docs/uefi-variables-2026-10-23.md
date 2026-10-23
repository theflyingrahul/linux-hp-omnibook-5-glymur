# UEFI Variables from Linux, Read-Only First, October 23, 2026

Issues #17 (RTC) and #18 (UEFI variables). The owner allowed UEFI variable
access on 2026-10-23, after it was deferred on 2026-10-20 until the system
was stable. This note records the risk assessment and what kernel `-17`
does. Nothing has run on the laptop yet.

## How Linux reaches the variables

On Snapdragon laptops, UEFI's runtime variable services are not usable from
the OS; the variables sit behind Qualcomm's UEFI secure application in the
TrustZone, which Linux reaches through QSEECOM (`qcom_qseecom_uefisecapp`,
built into our kernels). The kernel enables it per machine through
`qcom_scm_qseecom_allowlist`. Mainline lists more than 40 Snapdragon X
machines, among them the Mahua CRD, the ThinkPad T14s Gen 7 (Mahua), the
Glymur CRD and QCB, and HP's EliteBook X G2q (Glymur, `665d237915`, merged
for 7.4). `upstream/qcom-next/0009` adds `hp,omnibook-5-16-bf1xxx`, the
same one-line change.

## Risk

Reading has no known risk. Writing does:

1. **A full or corrupted variable store.** The classic case is the EFI
   pstore backend writing crash logs into the store on every panic until it
   fills; some firmware then fails to boot. `-17` builds with
   `CONFIG_EFI_VARS_PSTORE_DEFAULT_DISABLE=y`, so the backend stays off.
2. **The boot order rewritten** by `grub-install`, `efibootmgr`, `fwupd`
   or `mokutil`. Windows stays reachable from the boot menu, and the boot
   order is not part of what BitLocker measures. The installer already
   made `grub-install` a no-op and masked `fwupd`.
3. **Secure Boot keys and `dbx`** take only signed writes, so nothing on
   Linux changes them by accident.
4. **A firmware call that hangs** costs a reboot, not data.

So `-17` allows reads only:

- `install-from-usb.sh` adds `efivarfs ... ro` to `/etc/fstab` before
  the first `-17` boot, so nothing writes a variable without an explicit
  `mount -o remount,rw /sys/firmware/efi/efivars`.
- The RTC node has `qcom,uefi-rtc-info` without `allow-set-time`:
  `rtc-pm8xxx` then only reads the offset variable (`RTCInfo`, the one
  Windows keeps) and never writes it.

## The RTC

Our device trees never included `pmk8850.dtsi`, so there was no RTC device
at all (`-16`: no `/dev/rtc`, the clock restarting from the last saved time
until NTP). Every Glymur and Mahua laptop upstream includes it (ThinkPad
T14s Gen 7, Zenbook A14 and A16, EliteBook X G2q), and HP's PEP tables vote
this PMIC's clocks ("PMIC A"). The `-17` test device tree includes it,
which also brings the power key (`KEY_POWER`, so GNOME's power button
action applies), the PMIC GPIOs, its ADC and its RTC. The RTC follows the
Zenbook A16 and the QCB: `qcom,uefi-rtc-info` and `qcom,no-alarm`.

## First boot

`sudo bash ~/dump-efivars.sh` lists and copies every variable read-only to
`/var/log/glymur/efivars-*` (private: copy it into `.work/`, never commit
it). It shows whether `RTCInfo` and `SmartAmpCalibrationData` (the
speaker calibration for #3) are visible. `timedatectl` should then show an
RTC time.

Writes come later, once reads have been stable, by dropping the `ro` in
`/etc/fstab`, with the dump as the baseline to compare against.

## The boot logo

Plymouth's HP logo is a separate matter: it comes from the ACPI BGRT table,
which a device-tree boot never parses, so allowing UEFI variables does not
bring it back.
