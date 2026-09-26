# Ubuntu Live Boot Collector

`scripts/linux/glymur-live-collector.sh` is a non-interactive diagnostic
collector for the target's Ubuntu ARM64 live media. It records the kernel
command line, kernel and system logs, ACPI table names and copies, PCIe, USB,
I²C, input, EFI, DMI, mount, and block-device state. It does not install
packages, change firmware, load a target DTB, or write to internal storage.

The collector is invoked through systemd's `systemd.run=` kernel parameter. The
temporary media GRUB entry also specifies `systemd.run_success_action=poweroff`
and `systemd.run_failure_action=poweroff`; the machine powers off after
collection so the USB can be removed safely. Output was successfully written
under `/cdrom/glymur-logs/` during the 2026-09-15 test. The temporary GRUB
configuration has since been restored from its USB backup.

Version 2 of the repository script additionally records ACPI and platform
device enumeration, USB-C class state, loaded modules, and available kernel
configuration. The existing capture used version 1. On 2026-09-25, version 2
and the previously successful diagnostic GRUB entry were staged on the verified
SanDisk installer USB. Their copied hashes were checked. Version 2 completed a
capture on the target; see `ubuntu-live-boot-results-2026-09-25.md`. The normal
GRUB menu was restored and hash-verified after collection, so the diagnostic
entry is no longer active. Backups of the prior USB files are in the ignored
`.work/usb-staging-20260925/` directory; the original GRUB backup also remains
on the USB as `boot/grub/grub.cfg.glymur-original-20260915`.

Use this only with the target Ubuntu ARM64 installer. Preserve the original
`boot/grub/grub.cfg` before applying the temporary entry and restore it after
the logs are retrieved. The collected archive may contain serial numbers,
UUIDs, and firmware identifiers; keep it private.
