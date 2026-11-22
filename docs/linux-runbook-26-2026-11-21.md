# Linux runbook for kernel -26, November 21, 2026

`-26` is `-25` with two test device tree changes; the kernel is the same.
`-25` moved to Linux 7.4: qcom-next `c6989d230fe6`
(`qcom-next-7.4-rc3-20261120`), with everything `-24` had rebased and 39 of
the old patches now in the base (`patches/README.md`, "Kernel `-25`"). Neither
`-24` nor `-25` was booted, so their tests are here. A new base can break
anything, so A1 checks the basics first. Do not use `-25` for headset tests:
its test tree lacks what 7.4's codec driver needs to bind.

| Change | For | Tested by |
| --- | --- | --- |
| Linux 7.4-rc3 base | staying in step with Qualcomm and upstream | A1, everything |
| The eDP v8 power-on fix, ported to 7.4's new eDP PHY code (Glymur only) | the internal display at 2.7 Gb/s, two lanes | A1 |
| Daily tree: PMK8850 (power key), LDO7_B and the USB-C repeaters' supplies, from the test tree | the power key and USB-C full speed on the daily entry | C |
| New GRUB entry "Ubuntu on SSD: A/V test device tree" | B without editing GRUB | B |
| From `-24`: the PMK8850 RTC read-only as `rtc1` (test tree), the EC event retry, Qualcomm's Mahua Iris (A/V tree) | the clock, hotkeys, video | A2, A3, B |
| `-26`, test tree: the headset codec node as 7.4 needs it (`qcom,sdca-compliant`) | the headset binding at all on 7.4 (`docs/headset-2026-11-21.md`) | A4 |
| `-26`, test tree: `i2c5` on, nothing on it | finding the USB-A port's repeater (`docs/usb-a-repeater-2026-11-21.md`) | A5 |

"Ubuntu on SSD: previous kernel" boots the kernel that was installed
before `-26`.

## Install (on the installed kernel, now)

From the USB stick's `glymur-tools/kernels/` directory:

    bash install-from-usb.sh

Eject "UBUNTU 26_0" in Files, then reboot into "Ubuntu on SSD: test device
tree".

**If the screen stays dark** (the display goes through the ported eDP
fix), or nothing responds after 2 minutes:
1. Hold the power button.
2. Boot "Ubuntu on SSD: fallback, firmware display (minimal device tree)".
   It does not use the eDP PHY. Then run:

       journalctl -b -1 -k > ~/k26-dark.txt

3. If that does not boot either, boot "Ubuntu on SSD: previous kernel".

## A. Test device tree

1. **The basics on 7.4:**
    - the boot report reads `7.4.0-rc3-glymur-26`, model `(test)`;
    - the panel, keyboard, touchpad, touchscreen and Wi-Fi work;
    - a sound plays on the speakers;
    - GNOME runs on the GPU (`bash ~/check-mesa.sh`).

   Then:

        journalctl -k -b -p warning | grep -vE "dummy regulator|failed to set target rate" | head -60
        journalctl -k -b | grep -E "UBSAN|Unbalanced|Oops|BUG:|WARNING:" | head

   The second command should print nothing. Note anything from the first
   that looks new.
2. **The clock measurement:** with Wi-Fi connected, run
   `sudo bash ~/check-rtc.sh`, and note your phone's time when it runs.
   It only reads; answer `n` if it offers `set-local-rtc`.
3. **EC events:** press F5 (also hold it for 3 s), F6, F9, the brightness
   keys and Left Shift+Fn a few times each, quickly. Every key should still
   work at the end, and this should print nothing:

        journalctl -k -b | grep -E "cannot (read|clear) EC event"

4. **Headset:** first check that the SDCA driver bound:

        journalctl -k -b | grep -iE "wcd9378|sdca" | head -20

   Then run `sudo bash ~/check-headset.sh`, worn the right way round. New
   step: six streams of the left tone; answer left or right after each. The
   script then lists the registers that differ between left and right
   streams. Also note whether the jack state changes when you plug and
   unplug.
5. **USB:**
    - **the USB-A repeater scan:** `sudo bash ~/check-usb.sh --repeater`
      (read-only, about a second);
    - the USB-C stick and the Dell receiver in each USB-C port, with
      `sudo bash ~/check-usb.sh` after each;
    - `sudo bash ~/check-usb.sh --ss-stress` for the boot stick on USB-A.
6. **Charging:** `sudo bash ~/charging-watch.sh` (unplug and replug).
7. **Suspend, last:** the `-23` runbook's A7, from a text console
   (Ctrl+Alt+F3), with the 10-minute drain cycle on battery. If it freezes,
   save `journalctl -b -1 -k | tail -200 > ~/suspend-freeze-k26.txt` after
   the reboot.

## B. A/V test device tree (optional, after A)

Reboot and choose **"Ubuntu on SSD: A/V test device tree"** at the menu; no
editing. It boots the `-test-av` device tree without the board command line
(`clk_ignore_unused`, `pd_ignore_unused`, `arm64.nopauth`). The WirePlumber
file stays in place.
1. A quick check: keyboard, touchpad, Wi-Fi, a sound, the camera, the
   brightness keys.
2. Iris with Qualcomm's Mahua data:

        journalctl -k -b | grep -iE "iris|video-codec|mvs0" | tail -20
        sudo bash ~/check-video.sh

   Only if that fails, run `sudo bash ~/check-video.sh --mahua`.
3. The external display last: `sudo bash ~/check-display.sh`, with a
   monitor on one USB-C port, then the other. If it hangs, hold the power
   button.

## C. The daily entry

"Ubuntu on SSD" now has what the test tree proved:
- **The power key:** a short press shows GNOME's power dialog only on a
  hold, as before; `journalctl -b | grep -i "power key"`.
- **Full speed on USB-C:** the Dell receiver in each USB-C port, with
  `sudo bash ~/check-usb.sh` after each.
- **The rest:** audio, F6 and F9, the USB-C stick at SuperSpeed.

## Hand back

- Which steps you ran.
- The phone time from A2.
- Any photographs.
- `~/k26-dark.txt` or `~/suspend-freeze-k26.txt`, if either happened.
