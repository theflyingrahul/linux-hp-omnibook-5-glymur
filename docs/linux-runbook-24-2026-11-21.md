# Linux runbook for kernel -24, November 21, 2026

`-24` is `-23` plus (`patches/README.md`, "Kernel `-24`"):

| Change | For | Tested by |
| --- | --- | --- |
| The PMK8850 RTC, read-only, as `rtc1`, in the **test** tree | the clock: does the PMIC counter hold wall time, or does an SDAM hold Windows' offset? (`docs/rtc-2026-11-21.md`) | A2 |
| The EC driver retries the event read and the write that clears it | hotkeys and backlight events stopping after one failed transfer (from Birk's review) | A3 |
| `backports/0089–0091`: Qualcomm's Mahua Iris (one core), on in the **A/V** tree only | hardware video decoding | B3 |

Base, device trees and the USB-A test are otherwise as on `-23`. Still
open from `-23`'s runbook: A7 (suspend) and B. "Ubuntu on SSD: previous
kernel" now boots `-23`.

## Install (on `-23`, now)

From the USB stick's `glymur-tools/kernels/` directory:

    bash install-from-usb.sh

It installs `-24` and the refreshed `check-rtc.sh`. Eject "UBUNTU 26_0" in
Files, then reboot into "Ubuntu on SSD: test device tree".

## A. Test device tree

1. **Boot report:** it reads `7.3.0-glymur-24`, model `(test)`. Then:

        ls /sys/class/rtc/
        cat /sys/class/rtc/rtc1/name /sys/class/rtc/rtc1/date /sys/class/rtc/rtc1/time
        journalctl -k -b | grep -iE "pm8xxx|rtc"

   `rtc1` is the PMK8850 RTC (`rtc1` is its alias) and `rtc2` the PMIC
   GLink one. Note the date and time `rtc1` shows next to a clock you
   trust, such as your phone.
2. **The clock measurement:** with Wi-Fi connected, run
   `sudo bash ~/check-rtc.sh`. Its first new section, "PMK8850 RTC counter
   and SDAM", needs nothing from you. It prints:
    - the raw counter and the counter as a date;
    - the counter minus UTC and minus IST;
    - any SDAM word that brings the counter within an hour of UTC or IST.

   It saves the SDAM to `/var/log/glymur/pmk8850-sdam-*.txt`. That file is
   private: it is copied into `.work/` and never committed. The rest of the
   script is the GLink checks as before; answer `n` if it offers
   `set-local-rtc`.
3. **EC events:** press each special key a few times quickly: F5 (also
   hold it for 3 s), F6, F9, the brightness keys and Left Shift+Fn. Then:

        journalctl -k -b | grep -E "hp-omnibook-5-ec|cannot (read|clear) EC event"

   Every key should still work at the end, and nothing should mention
   `cannot`.
4. **Headset left and right:** with the headset worn the right way round,
   run `sudo bash ~/check-headset.sh` once more. Answer which side each
   tone is on, every time. This settles whether the swap comes and goes per
   stream.
5. **A7 from the `-23` runbook** (suspend from a text console, then the
   10-minute drain cycle on battery), unchanged. If it freezes, save
   `journalctl -b -1 -k | tail -200 > ~/suspend-freeze-k24.txt` after
   the reboot.

## B. A/V device tree (optional, after A)

As in the `-23` runbook's B: the WirePlumber file stays in place, then the
GRUB edit to `-test-av.dtb`, without `$cmdline`.
1. The boot options and the quick check, as there.
2. Iris now comes up with Qualcomm's Mahua data. Check that it bound:

        journalctl -k -b | grep -iE "iris|video-codec|mvs0" | tail -20

3. **Video:** `sudo bash ~/check-video.sh`, with no option. This is
   Qualcomm's own configuration. Only if that fails, run
   `sudo bash ~/check-video.sh --mahua`.
4. The external display last, as before.

## C. The daily entry

The boot report's USB-A section, as on `-23`, and nothing else new. The
daily tree has no PMK8850 RTC and no Iris.

## Hand back

- Which steps you ran.
- The time on your phone when `check-rtc.sh` ran.
- Photographs, if any.
- `~/suspend-freeze-k24.txt`, if A5 froze.
