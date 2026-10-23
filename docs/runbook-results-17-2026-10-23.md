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
(Corrected after the second boot: the speaker filter topology was never
installed. The topology on disk was the plain one, sha256 `4f81077a…`, the
same file `-16` used, so the filter is not the cause.)

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
Run the runbook from step 3 in order. If the blue-screen freeze comes back,
the next diagnostic boot drops `quiet splash` (press `e` in GRUB) so the
console shows the last messages.

## Second boot, with the matching initramfs (17:21)

Raw: `captures/2026-10-23-k17/boot2/` (sanitized). Private data is on the
USB stick, for the Windows-side session too, in
`glymur-logs/k17-2026-10-23/` (both boots' dmesg and journals, the
WirePlumber debug logs, the UEFI variable dump, with `SHA256SUMS`), and in
`.work/k17-boot1-*` and `.work/k17-boot2-*`.

| Check | Result |
|---|---|
| boot | clean; the `-17` initramfs loads, `msm` initializes inside it, plymouth shows; no freeze |
| 3.1 EC interrupt | **fixed**: 3 interrupts in total, 0 in 20 s idle (about 90 per 10 s on `-16`). Reading register `0x00` (`docs/audit-2026-10-22.md`) clears the event |
| EC sensors | fan 0 rpm, thermistors 36-38 °C, backlight attributes read |
| boot-time APM timeout | `CMD timeout [1001021]` (`APM_CMD_GET_SPF_STATE`) at 9.696 s again; it is in every boot back to `-15`, so it is old and harmless |
| direct playback | `aplay -D plughw:0,0`, 3 s, played in 3.2 s with no DSP timeout: the DSP path works |
| audio session | **broken from boot**, before anything was touched: the card's profile is `off`, PipeWire offers only "Dummy Output", streams never link (see below) |
| USB | `check-usb.sh`: no errors; full and low speed still need a device plugged in by hand |
| battery manager | 60 s baseline on battery: `qcom_battmgr_callback` 52 calls, `qcom_battmgr_state_callback` 0 (no plug events in this run) |
| video `--diag` | see below |
| UEFI dump | 98 variables, `SmartAmpCalibrationData` (80 bytes) present, no `RTCInfo`; private |

### The audio session stall: WirePlumber's v4l2 monitor

WirePlumber 1.6.8 never ran the events that pick the card's profile, choose
the default sink and link streams: the card sat on profile `off`, PipeWire
offered only "Dummy Output", and `default.audio.sink` stayed `auto_null`
although `default.configured.audio.sink` named the speakers. Setting the
profile by hand created the sinks, but streams still never linked.

Bisected with one WirePlumber restart per step:

| Change | Session |
|---|---|
| Iris video nodes disabled by a `monitor.v4l2.rules` entry | stuck |
| the HP WirePlumber rule file moved aside | stuck |
| `~/.local/state/wireplumber` moved aside | stuck |
| `monitor.v4l2` and `monitor.libcamera` disabled | **works**: HiFi profile, speakers default, `pw-play` plays |
| only `monitor.v4l2` disabled | **works** |

So the **v4l2 monitor** blocks WirePlumber's event queue on `-17`. Its
attempt to open the Iris decoder times out (`spa.v4l2: Cannot open
'/dev/video0': 110`) because Iris cannot power on; on `-16` the open
succeeded. (Disabling only the Iris devices by rule was not enough; the
monitor still enumerates them.) The libcamera monitor still offers the camera
to PipeWire.

Workaround, in place for the next boots:
`~/.config/wireplumber/wireplumber.conf.d/52-no-v4l2-monitor.conf`, also
committed as `boards/hp-omnibook-5-16-bf1xxx/audio/wireplumber/52-no-v4l2-monitor.conf`
(not yet installed by `install-audio.sh`). Remove it once Iris opens again.

Also ruled out: the speaker filter topology (never installed) and
`upstream/qcom-next/0008` (same `SET_CFG` payload for a valid topology). The
kernel PCM path works: `aplay` with plain RW access and with MMAP and a
1024-frame period both played 3 s without a DSP timeout. The device offers
only S16_LE, 2 channels, 48 kHz.

### Why the whole system freezes: the clock prepare lock

At 1442 s, 5.5 s after the last WirePlumber restart and with the session now
working, the DSP stopped answering again exactly as on the first boot (APM
`1001004`, `1001003`, `1001000`, then PRM `1001010` and `100100f`, 5 s
each). The D-state tasks (`captures/2026-10-23-k17/boot2/freeze-stacks.txt`)
show how one hung DSP request freezes the laptop:

- PipeWire sits in `clk_core_prepare` -> `clk_vote_q6dsp_block` ->
  `q6prm_vote_lpass_core_hw` -> `audioreach_send_cmd_sync`: it holds the
  clock framework's global prepare lock while it waits up to 5 s for the DSP,
  and the next request takes it again.
- The GPU's runtime suspend (`a6xx_gmu_stop` -> `clk_bulk_unprepare`) waits
  for that lock, so GPU jobs wait in `msm_gpu_submit` -> `rpm_resume`. That
  is the "GPU lockup" of the first boot, which killed the terminal: the GPU
  was not hung, its power management was.
- The GENI I2C controllers' runtime resume (`geni_i2c_xfer`) waits for it too,
  and they carry the EC, the keyboard, the touchpad and the touchscreen: the
  input freezes the owner saw.

Stopping the audio services released the lock (no D-state task left).

So there are two problems. The trigger is the DSP that stops answering APM
and PRM commands, seen twice, both times within seconds of a WirePlumber
restart while the audio graph was in use; whether it also happens without a
restart is not known. The amplifier is the multiplier: a 5 s synchronous DSP
call under the global clock prepare lock (`q6prm` via
`clk_vote_q6dsp_block`) turns any DSP stall into a system-wide freeze. That
is worth raising upstream: the LPASS vote should not block for seconds with
the prepare lock held.

### Video `--diag` trials

`video-test-20261023T172620.txt`:

| Trial | Result |
|---|---|
| default (core 1), pipes 4, 2 or 1 | firmware: `Configured core 1 is not supported`, then `core 0 is not supported`; fatal session errors |
| `diag_core_id=2`, pipes 4 or 2 | **no "not supported" and no fatal error**; but no frame within 30 s, and `ffmpeg` then hung past its timeout and had to be killed |
| `diag_core_id=0` | `can't configure decoder` (`EINVAL`) |

Core ID 2 is the one the firmware accepts; the decode then stalls rather
than fails. With every open, `qcom-iris ... failed to suspend` (`skip power
collapse, wfi=0x0, idle=0x0`) repeats; the `mvs1` GDSC still never turns on.

### Configuration left for the next boot

- The plain topology (`install-audio.sh`, the same file as before).
- The `-17` initramfs, `initrd-glymur.old` for `-16`.
- `~/.config/wireplumber/wireplumber.conf.d/52-no-v4l2-monitor.conf` (above).

Not run this boot: the GPU load test (`check-mesa.sh`), because the DSP had
wedged and the result would not have been clean; the hands-on steps (F-keys,
listening, charger, USB devices).

### Next boot

1. Use audio normally; do not restart PipeWire or WirePlumber. If the
   freezes come back, check `dmesg` for `CMD timeout`: if present without
   any restart, the DSP stall happens on its own.
2. Runbook steps 3.2 (`check-hotkeys.sh`), 4 (listen, `check-audio.sh`),
   5 (charger), 6 (USB devices), then `check-mesa.sh`.
