# Runbook results, kernel `-17`, first boot, October 23, 2026

First boot of `7.3.0-rc4-glymur-17` on "Ubuntu on SSD: test device tree"
(`docs/linux-runbook-2026-10-23.md`), plus the `-16` boot before it that
froze at a blue screen. Raw excerpts: `captures/2026-10-23-k17/` (sanitized).
Full dmesg and journals stay private in `.work/k17-boot1-*`.

The runbook stopped after step 2: at 815 s the audio DSP stopped answering
and the GPU locked up within the same three seconds, and from then on the
desktop froze repeatedly. Steps 3 to 9 still need a clean boot.

## Results so far

| Step | Result |
|---|---|
| 1 boot report | release `-17`, model `(test)`; the only probe failure is `rtc-pm8xxx` (below) |
| 1 boot logo | plymouth runs `custom-status`, not `bgrt`: a theme from a side project (below) has the higher priority |
| 2 RTC | **no RTC**: `rtc-pm8xxx ... probe ... failed with error -2`. The firmware has no `RTCInfo` variable, which `qcom,uefi-rtc-info` reads |
| 2 UEFI variables | readable through QSEECOM, mounted `ro`, 98 variables; `SmartAmpCalibrationData` is there (issue #3); `RTCInfo` is not |
| video (seen, not run) | every open of the decoder fails: `video_cc_mvs1_gdsc status stuck at 'off'`, `qcom-iris: power on failed`, 12 times this boot (`v4l_id`, WirePlumber, GStreamer). `-17` dropped the one-core patch, so this is the `-15` failure again |

The RTC needs another offset source. `RTCInfo` is a name Windows keeps on
other machines; HP's firmware here does not expose it, so `qcom,uefi-rtc-info`
cannot work as is on this laptop.

## GPU lockup and audio DSP stall, 815-835 s

`captures/2026-10-23-k17/gpu-hang-dsp-stall.txt`, `dsp-timeouts.txt`.

- 815.6 s: `qcom-apm gprsvc:service:2:1: CMD timeout for [1001004] opcode`.
- 818.7 s: `qcom-prm ... CMD timeout for [1001010]`, then
  `hangcheck detected gpu lockup rb 2!` (completed fence 6749, submitted 6750).
- 834.0 s: `hangcheck recover!`, offending task `ptyxis`; 835.0 s:
  `a8xx_recover: cx gdsc didn't collapse`. The terminal died with
  `VK_ERROR_DEVICE_LOST`. No GPU error followed.
- From then on every LPASS clock vote through the DSP's power manager timed
  out after 5 s (`q6prm_vote_lpass_core_hw` -> `CMD timeout [100100f]`,
  `__pm_clk_enable ... error -110` on `wsa_macro`, `va_macro`, the LPASS
  pinctrl). WirePlumber sat in D state in `audioreach_send_cmd_sync`
  (`wireplumber-d-state.txt`), retried every few seconds, and GNOME, waiting
  on the audio session, froze for seconds at a time. The ADSP itself still
  read `running`, with no PDR or crash notice.
- Stopping the audio services (PipeWire, WirePlumber, pipewire-pulse) for the
  rest of the boot ended the retries and the D-state task.

What led up to it. One APM timeout came already at 9.7 s (`APM_CMD_GET_SPF_STATE`,
`1001021`), before anything was done by hand. Then, debugging why PipeWire had
no default sink and linked no stream, the session was restarted several times
(at 700, 729, 773, 810 and 823 s); a direct `aplay` to `plughw:0,0` at about
570 s played 3 s normally. The first timeout of the stall came 5 s after the
restart at 810 s. That restart may have pushed a DSP that was already slow
over the edge; it does not explain the GPU.

Two failures in three seconds point to something both depend on (a power or
bus resource) more than to two separate bugs, but nothing here proves which.
New in `-17` on the audio side is the speaker filter topology
(`install-audio.sh --speaker-eq`, module `0x6053`); it is the first suspect
for the DSP, and `install-audio.sh` without options goes back to the plain
topology.

One session problem was self-inflicted: stopping `pipewire.service` while
testing `aplay` was cancelled while its socket was re-created, so the old
daemon kept serving a deleted socket and `wpctl` hung. A full restart of all
five units fixes that.

## The `-16` boot that froze at a blue screen

`captures/2026-10-23-k17/frozen-boot-k16.txt`. Boot -2 in the journal,
kernel `-16`, `quiet splash`, with an initramfs.

- Its journal ends at 3.67 s, right after the root takes over (journal flush,
  udev coldplug starting). Whatever hung came after, and never reached the
  disk; there is no pstore (the EFI backend is off by design).
- It is the only one of six boots with plymouth that froze. In all of them
  the display driver (`msm`) loads inside the initramfs at about 1.5-1.9 s
  while plymouth is drawing on simpledrm, and the GPU firmware, which the
  initramfs lacks, loads later from the root.
- The blue screen is not plymouth's: both installed themes have black
  backgrounds.
- What is new since 2026-10-22, all outside the repository: a side project
  (`~/plymouth-interactive`) installed a script theme, a
  `plymouth-job-monitor` service that queries systemd over its private
  socket during boot, an initramfs (`/boot/initrd-glymur`), and `quiet splash`
  plus `initrd` lines in the USB's `grub.cfg`. The same work mounted the SSD's
  EFI partition read-only and read it raw, which the working rules exclude.
- `/boot/initrd-glymur` still pointed at the `-16` initramfs, so `-17` booted
  with modules it could not load (its display driver then loads from the root
  at about 4 s instead).

## Changes made

- `-17` initramfs built (`update-initramfs -c -k 7.3.0-rc4-glymur-17`);
  `/boot/initrd-glymur` points at it, and a new `/boot/initrd-glymur.old`
  at the `-16` one.
- `install-kernel.sh` keeps both in step when an initramfs is in use: it
  builds one for the new kernel and rotates the two links like the kernels.
- `grub-entry.cfg` (the template `make-kit.sh` fills) now has what the USB
  already had: `quiet splash` and the optional `initrd` line, with
  `initrd-glymur.old` for "previous kernel".
- USB `grub.cfg`: the "previous kernel" entry loads `initrd-glymur.old`
  (two lines; backup in `.work/grub-before-initrd-old-20261023.cfg`, stock
  entry first and unchanged, FAT checked clean).

## Next boot

Boot `-17` again (now with its own initramfs). Do not restart audio services.
Run the runbook from step 3 in order; if the DSP timeouts come back without
any session restarts, go back to the plain topology (`sudo bash
install-audio.sh`) for the boot after. If the blue-screen freeze comes back,
the next diagnostic boot drops `quiet splash` (press `e` in GRUB) so the
console shows the last messages.
