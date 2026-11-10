# Linux runbook for kernel -21, November 10, 2026

`-21` is `-20` (same qcom-next base `17bbb4b37bbc`, same device trees) with
the fixes from `-20`'s first boots (`docs/runbook-results-20-2026-11-10.md`).
It is the first kernel built on the 48-core cross-build host (kernel.org GCC
15.2; the same kernel options as the WSL builds). What changed:

| Patch | Change | Tested by |
| --- | --- | --- |
| `upstream/qcom-next/0005` | EC driver v2 corrected: `fn_lock` read-only with the EC's polarity; the backlight events also notify `kbd_backlight_timeout`; the standby exit is retried on resume | A4b, A13 |
| `upstream/qcom-next/0010` | SDCA: statically described controls get their widths and types (the WCD9378's jack detection, the two UBSANs) | A6 |
| `backports/0086` | revert of Qualcomm's superseded GENI I2C early-resume patch (the "Unbalanced pm_runtime_enable!" warnings and the EC bus's failed first transfer after resume) | A13 |
| `glymur-bringup/0005` | Iris: the partial-data buffer for AV1 only, behind `qcom_iris.diag_partial_av1_only` (default off) | B6 |
| kit | suspend is s2idle only (`/etc/systemd/sleep.conf.d/glymur-s2idle.conf`); `check-rtc.sh` logs the RTC service's replies | A4, A13 |

The rules of the `-20` runbook still hold (UEFI writes only through
`check-efivars-write.sh`, no TPM tools, a monitor only at the end of B, the
audio-session escape). "Ubuntu on SSD: previous kernel" now boots `-20`.

## Install (on `-20`, now)

From the USB stick's `glymur-tools/kernels/` directory:

    bash install-from-usb.sh

`setup-npu.sh` already ran on this install; run it again only if
`check-npu.sh` says the FastRPC tests are missing. Reboot into "Ubuntu on
SSD: test device tree".

## A. First boot: test device tree

Steps not listed here are as in `docs/linux-runbook-20-2026-11-09.md`.
Have at hand: the USB mouse (no hub), the USB-C stick, the combo headset,
the charger.

1. **Input**, then the **boot report** reads `7.3.0-glymur-21`, model
   `(test)`. Check: `journalctl -k -b | grep -E "UBSAN|Unbalanced"` should
   print nothing.
2. **UEFI write** (not run on `-20`): `sudo bash ~/check-efivars-write.sh`.
3. **RTC:** `sudo bash ~/check-rtc.sh`. New first section: the service's
   replies to each request, with debug logging. Hand back its log even if
   the RTC still fails.
4. **EC:** `sudo bash ~/check-ec.sh`. Now: `fn_lock` reads 0 while F7 is
   volume-down; Left Shift+Fn twice, each notified, and F7 follows; nothing
   is written. Then hold F5 for 3 s, and then F6, and say what changed and
   whether anything showed.
5. **Speakers and microphones:** `sudo bash ~/check-audio.sh` (then the
   hour-long `watch-audio.sh 3600` with music, as in `-20`).
6. **Headset:** `sudo bash ~/check-headset.sh` with the combo headset.
   If `0010` fixed the widths: `GE 35 Detected Mode` has a real range,
   `Headphone Jack` follows the plug (on `-20` it read on with nothing
   plugged), and plugging raises a jack event.
   The tones may still not play (no headset UCM yet); the jack and button
   lines are what this boot checks.
7. **USB** (not run on `-20`): the mouse in each USB-C port, then USB-A,
   `sudo bash ~/check-usb.sh` after each; the USB-C stick in each USB-C port.
8. **Charging** (not run): `sudo bash ~/charging-watch.sh`, then
   `sudo bash ~/check-battmgr-notify.sh`.
9. **GPU:** `bash ~/check-mesa.sh`. **NPU:** `sudo bash ~/check-npu.sh`.
10. **Power button:** a short press opens GNOME's power-off dialog; cancel.
11. **Suspend, last:** mouse in one USB-C port, stick in the other, Wi-Fi
    on, charger in. `sudo bash ~/check-suspend.sh`. `/sys/power/mem_sleep`
    should now show `[s2idle]`, so no cycle tries "deep". The RTC cycle
    still has no alarm unless step 3 found one; wake it with a key. Each
    cycle now prints how long the SoC spent in CX collapse (`cxsd`), AOSS
    sleep (`aosd`) and DDR low power (`ddr`); on `-20` all three stayed at
    0, so the SoC never slept (`docs/suspend-2026-11-10.md`). At the end,
    answer `y` to the 10-minute drain cycle (on battery, lid closed): it
    gives the sleep power in mW. Check afterwards:
    `journalctl -k -b | grep -E "cannot tell the EC|Unbalanced|GPI transfer failed"`
    should print nothing.
12. **Suspend with the boot votes released:** if the cycles came back, run
    `sudo bash ~/check-suspend.sh --sync-state` once more, again with the
    drain cycle. It releases the three clock controllers that wait for the
    GPU management unit (`sync_state`) and keep their boot votes; whether
    `cxsd` then moves is the main question of this boot.

## B. Second boot: A/V device tree (as in `-20`, B)

Do step 1 first this time (the WirePlumber file that keeps it away from the
video nodes), then the GRUB edit to `-test-av.dtb` without `$cmdline`.

- B3: `sudo bash ~/check-efivars-write.sh --verify`.
- B6: `sudo bash ~/check-video.sh --mahua`. The first trial is new: the
  `-20` Windows-like settings with the partial-data buffer kept to AV1. If
  it decodes (`ffmpeg exit: 0`), that was the stall.
- B7: external displays, last.

## C. The daily entry (the reboot after B)

As in `-20`'s C: "Ubuntu on SSD", model without `(test)`, speakers,
microphones, F6/F9, the USB-C stick at SuperSpeed.

## Hand back

`/var/log/glymur/*.txt` from all three boots, the times of any freeze, and
which suspend cycles came back.
