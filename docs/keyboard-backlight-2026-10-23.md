# Keyboard Backlight: Nothing Sets the Level from the OS, October 23, 2026

Issue #12 asked for the command HP's own software uses to set the keyboard
backlight level, so that Linux could expose a writable `kbd_backlight` LED.
Read-only work on this laptop's Windows driver store and HP's ACPI tables.

## Findings

- **HP's ACPI tables have no level command.** `WMID.SBKT` and `SKTR` send
  `HQEX(0x05, n)`, which sets the backlight *timeout* (30 s, 3 min, never),
  as corrected in `docs/ec-2026-09-30.md` for kernel `-10`. The level is
  only read (`0x05`/`0xff`) and reported by EC event `0x0d`.
- **HP's Windows drivers are stubs or WMI clients.** The two HP devices
  Windows binds, `HPIC0003` ("HP Application Driver", `\_SB.IPPF`) and
  `HPIC0005` ("HP Mute LED", `\_SB.MLED`), are empty ACPI devices in SSDT
  `8F47` (only `_HID` and `_STA`). A third, `HPIC0014` (`HRBL`), has an
  empty `STXS` method and is hidden unless `WMID.HROL` is set.
- **No HP binary mentions a backlight.** A search of every binary in the
  HP driver packages (`hpcustomcap*`, `hpmuteled`), in ASCII and UTF-16,
  found no "backlight" or "keyboard light" string.

So the level belongs to the EC and F5 alone, on Windows as on Linux.
Linux can read it and see it change, but not set it.

## What that means for Linux

The standard interface, a `kbd_backlight` LED that reports hardware
changes (`LED_BRIGHT_HW_CHANGED`, as the ThinkPad T14s EC driver does),
assumes the level can also be set: the users of that flag checked (the
T14s EC, Logitech G15 keyboards) all have a `brightness_set`. A read-only LED would show a slider in GNOME that does
nothing. The driver keeps its read-only `kbd_backlight_level` attribute
and the writable `kbd_backlight_timeout`. With the event register fixed
(`docs/audit-2026-10-22.md`), event `0x0d` should now arrive on each F5
press; `ec-event-capture.sh` can confirm it on the next boot.
