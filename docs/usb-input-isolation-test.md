# USB 2.0 Input Isolation Test

The Ubuntu 26.04.1 live capture showed the right-port controller
`QCOM0F9A:00` with a one-port USB 2.0 root hub (bus 2) and a one-port USB 3
root hub (bus 3). The installer appeared only on bus 3 at 5 Gbit/s. The
internal camera was on a different controller's USB 2.0 bus. Therefore the
capture does **not** establish whether a USB 2.0 mouse can enumerate on the
right USB-A port.

## One-time test without changing the installer

At GRUB, select **Try or Install Ubuntu**, press `e`, and on its `linux` line
replace `persistent` with `toram nopersistent`. For readable boot output,
also remove `quiet splash` and append `plymouth.enable=0` after `---`.
Press `Ctrl+X` to boot. These edits affect only this boot. Leave the existing
`$cmdline` intact; it carries the image's Snapdragon clock/power workarounds.

Wait for a successful `Copying live_media to ram` step and for the live desktop
to appear. A desktop alone is insufficient: Casper can continue from USB if
the memory copy is skipped for lack of space. **Do not remove the installer if
the copy fails, is uncertain, or boot fails.** Then remove the installer from
the right USB-A port, insert a known working wired USB 2.0 mouse directly
into that port, and check whether its pointer works within 30 seconds. Do
not use a hub, an adapter, or a USB-C port in this test. Reinsert the
installer afterward. A working pointer establishes USB 2.0 input on that
port only; it says nothing about internal
I²C input or either USB-C port. No pointer is an observation, not proof of a
USB 2.0 PHY fault; without logs it does not distinguish enumeration, HID,
power, or port-routing failures.

Casper 26.04.2 parses `toram`, checks free memory, copies the live media to a
tmpfs, and replaces the original `/cdrom` mount. `nopersistent` also prevents
its automatic log-persistence path from mounting the installer's second
partition. The installer partition contains about 4.2 GB of files and the
machine has 32 GB RAM, but successful copying must be confirmed by the boot
itself. The installed USB volume is currently reported unhealthy/dirty by
Windows, so no persistent collector was staged for that first test.

Sources: [Ubuntu Casper 26.04.2 boot script](https://git.launchpad.net/casper/plain/scripts/casper?id=bf9d00f6054157333969548b0f196012d0e2e1df),
private capture under `.work/ubuntu-live-boot-20260925/`.

## Reported result and next evidence

On September 26 the user reported that the pointer did not work after the
swap, and confirmed Ubuntu remained running after the installer was removed
and the wired USB 2.0 mouse works elsewhere. This rules out the installer
occupying the port and an obviously faulty mouse. There is no hot-plug
`dmesg`, USB sysfs, or input-device capture from that run, so it cannot
distinguish a failed USB 2.0 link from a device that enumerated without
working HID input.

The Windows capture maps `QCOM0F9A` to the standard xHCI driver plus Qualcomm
`QcXhciFilter_8480`. The private DSDT has `USB2.PHYC` configuration data and
`USB2._DEP` references to `PEP0` and `UCS0`. The [generic Linux xHCI platform
driver](https://github.com/torvalds/linux/blob/master/drivers/usb/host/xhci-plat.c)
binds through the `PNP0D15` compatible ID, but these observations do
not show which Windows-specific action, if any, is needed for USB 2.0 on the
right port. Do not apply `PHYC` register writes speculatively.

Next capture should record `dmesg -w`, USB `udevadm` events, `lsusb -t`,
`/sys/bus/usb/devices/2-1/uevent` if present, and `/proc/bus/input/devices`
during the same no-hub mouse swap. Keep logs in RAM until the installer is
reinserted and positively identified; do not write to the internal NVMe.
A September 26 read-only `chkdsk E:` found no file/folder errors, but
`fsutil dirty query E:` still reported a dirty volume and Windows reported
`Full Repair Needed`. With the user's approval, `chkdsk E: /f` completed;
`fsutil` then reported **NOT Dirty** and Windows showed Healthy/OK. No backup
was made at the user's request. The observational collector and separate
GRUB entry are maintained in `scripts/linux/`.
After the repair, the collector was staged on the installer as a separate,
default-off GRUB entry named **Glymur right USB-A 2.0 hot-plug capture (RAM
live)**. The original GRUB prefix was byte-for-byte preserved, the staged
script hash matched its repository source, and read-only `chkdsk` found no
file errors after staging. The FAT volume remained Healthy/OK and not dirty.
The first boot of this entry reached a text-only multi-user system, but no
`usb2-hotplug-*` log directory was created. The entry mistakenly included
`systemd.unit=multi-user.target`, which bypassed the target generated for
`systemd.run=` and therefore did not launch the collector. That conflicting
option has been removed from the repository entry and installer copy; the
normal Ubuntu entry remains unchanged. The photo from that attempt shows a
Dell Universal Receiver (`413c:301b`) enumerating as USB 2.0 full speed on
`QCOM0F9A:00` bus 2, with HID keyboard/mouse interfaces and repeated USB
resets before disconnection. This establishes that USB 2.0 enumeration works
on the right USB-A port, but does not establish whether pointer events work:
the test used a wireless receiver rather than the specified wired mouse,
and a text-only boot cannot display a pointer. No hot-plug logs were saved.

For the corrected capture, select only the optional **Glymur right USB-A 2.0
hot-plug capture (RAM live)** entry. Wait for the collector's `Glymur USB 2.0
hot-plug observation` banner and its explicit `Now swap installer for mouse`
message before removing the installer. If neither appears, leave the installer
plugged in. Use a known-working wired USB 2.0 mouse directly in the right
USB-A port; reinsert the installer when prompted. The collector saves under
`glymur-logs/usb2-hotplug-*` and then powers off. This is a text-only capture:
there is no on-screen pointer, so inspect the saved USB and input logs rather
than using pointer movement as the success criterion.

The completed capture in `glymur-logs/usb2-hotplug-20260727T204532Z.mV5qsb`
shows the Dell Universal Receiver (`413c:301b`) enumerating at 12 Mb/s on
`QCOM0F9A:00` bus 2. Linux bound `usbhid` and created a mouse event device.
It reset once, then disconnected when removed. USB 2.0 descriptor errors
(`-71`) occurred after receiver removal and before the SanDisk installer
successfully returned at SuperSpeed; those errors do not identify a device
or establish a persistent USB 2.0 fault. The capture did not record evdev
movement events, so it cannot prove pointer data arrived. The next optional
run adds a read-only observer that opens only right-controller event devices
advertising both relative X and Y axes, and records motion/button events in
`mouse-events.txt`; it does not record keyboard events or write hardware
settings. Move and click the mouse while it is connected for the 45-second
window. Keep the private capture outside Git.
