# Keyboard Hotkeys, LEDs, and Backlight: Evidence Before Reboot, September 29, 2026

Live checks on the GPU test DT (kernel `7.3.0-rc2-glymur-5`), gathered on
the owner's report that the mute/mic-mute LEDs, keyboard backlight status/
timer, and some special/Fn keys "don't seem functional." Method: a small
raw-evdev capture (`scripts/linux/glymur-keycap.py`, decodes
`struct input_event` from `/dev/input/event0` [gpio-keys], `event6` [the
touchpad's Consumer Control HID collection], and `event7` [the keyboard])
while the owner pressed F6, F9, the Copilot key, and other special keys in
sequence. Keycodes decoded against
`/usr/include/linux/input-event-codes.h`. Raw output:
`docs/keyboard-hotkeys-2026-09-29-capture.txt`.

## F6 (speaker mute) and F9 (mic mute): the same HID usage, not two keys

```
F6: MSC scan=0xC0022 KEY_MUTE(113) down/up
F9: MSC scan=0xC0022 KEY_MUTE(113) down/up   <- identical scancode and keycode
```

`0xC0022` is USB HID Consumer-page usage `0x0022`, literally defined as
"Mute" in the HID Usage Tables. **Both keys send the exact same HID report.**
This is not a Linux driver gap: the keyboard's own HID report descriptor
gives F9 no distinct usage (there is no "Mic Mute" consumer-control usage
being sent at all). Nothing on the Linux side — not `evdev`, not a future
audio stack — can tell these two keys apart as long as the keyboard reports
them identically. If HP's Windows driver distinguishes them, it must be
reading something other than this HID report (a vendor HID collection, an
EC/WMI signal, or a separate report ID not seen here).

The keyboard's own LED capability bitmap
(`input9/capabilities/led` = `0x1f`, i.e. only the five standard
Num/Caps/Scroll-lock, Compose, Kana LEDs) has **no mute or mic-mute LED
bit at all**. A generic HID keyboard has no way to expose one. If these
indicator LEDs exist physically, they are driven by something outside the
standard keyboard HID interface — most likely the EC, which has no node in
any of this repository's device trees (`docs/status.md`'s established EC
gap) — or possibly logic in the audio codec that also doesn't exist here
yet (no ALSA soundcard on any DT boot).

## The Copilot key and other special keys: received correctly, just unbound

```
Copilot key:  LEFTMETA(125) + LEFTSHIFT(42) + F23(193, held) down/up together
Special key A: LEFTCTRL(29) + F17(187) down/up together
Special key B: PLAYPAUSE(164) down/up  [standard consumer-control key]
Special key C: LEFTMETA(125) held, P(25) x3, then
               LEFTMETA+LEFTCTRL+LEFTALT+LEFTSHIFT+SPACE together, released
Special key D: LEFTSHIFT(42) + DELETE(111) down/up together
```

Every one of these arrived at the kernel's evdev layer as a clean,
well-formed key combination — nothing was dropped, garbled, or missing.
The Copilot key generating `Meta+Shift+F23` matches a known pattern: since
`F23` has no assigned function on a stock keyboard, several OEMs wire a
dedicated key to send `Win+Shift+F23` so a Windows-side driver/shortcut can
claim it without a kernel driver of its own — evidence the keyboard
hardware itself is working exactly as designed, independent of Linux.

**None of these combinations do anything visible because nothing in this
GNOME session is bound to them** — not because Linux fails to see them.
`Meta+Shift+F23`, `Ctrl+F17`, and the five-key chord in "Special key C" are
not standard GNOME shortcuts. `KEY_PLAYPAUSE` is a normal consumer-control
key that most desktops do bind by default; if it visibly "worked" that is
consistent with this. This is a desktop-configuration gap (bindable in
GNOME Settings or via a udev/systemd hwdb entry), not a kernel, DT, or
driver problem — nothing here needs a code change to "fix" at the Linux
input layer.

## Keyboard backlight: confirmed no OS-visible control path

`/sys/class/backlight/` has only `dp_aux_backlight` (the eDP panel, from
`docs/edp-display-working-2026-09-29.md`) — no keyboard-backlight device.
A search for `*kbd*backlight*`/`*kbd_led*` anywhere in `/sys` found nothing,
and there is no HP-specific platform driver bound on this boot. Whatever
turns the keyboard backlight on, off, or auto-off after a timeout is
entirely invisible to and uncontrolled by Linux right now — consistent
with the owner's report that it "works" (lights, times out) but has no
status/brightness/timer surfaced in the OS. This point squarely at EC
firmware running the whole feature autonomously, the same shape as the
already-documented fan-RPM and (probable) charging-LED gaps: real hardware
behavior that Linux cannot see or influence until the EC has a driver.

## Power key LED: not tested further

The owner reports it lights correctly already; its suspend/sleep
"breathing" behavior needs an actual suspend cycle to check, and suspend is
masked project-wide (`docs/status.md`) — not tested this session.

## Summary

| Item | Status | Cause |
|---|---|---|
| F6 speaker mute | Keycode correct | — |
| F9 mic mute | **Keycode identical to F6** | Keyboard HID hardware sends the same Consumer/Mute usage for both; not distinguishable in Linux |
| Speaker/mic-mute LEDs | Don't light | No LED bit for them on the keyboard's HID interface; most likely EC- or codec-driven, neither present in any DT yet |
| Keyboard backlight (on/off) | Works | Autonomous, EC-driven presumably |
| Keyboard backlight auto-off timer | Works | Same, autonomous |
| Keyboard backlight status/brightness/timer in OS | Missing | No backlight class device exists; needs an EC or vendor driver |
| Power key LED (lit) | Works | Autonomous |
| Power key LED (sleep breathing) | Not tested | Suspend is masked |
| Copilot key | Keycode correct (`Meta+Shift+F23`) | No GNOME binding for it yet — not a kernel/DT issue |
| Other special/Fn keys | Keycodes correct (see combos above) | Same — unbound in the desktop, not broken in the kernel |

No DT or kernel change is proposed from this investigation. The one
concrete, fixable-in-principle finding is the F6/F9 HID collision, which
would need to be re-verified against HP's Windows driver behavior (does it
actually distinguish them, and how?) before assuming it's fixable at all.
