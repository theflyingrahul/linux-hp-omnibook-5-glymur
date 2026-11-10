# Runbook results, kernel `-20`, boot A (partial), November 10, 2026

`7.3.0-glymur-20` on "Ubuntu on SSD: test device tree"
(`docs/linux-runbook-20-2026-11-09.md`). Sanitized logs:
`captures/2026-11-10-k20/` (the four hardware-ID files are unsanitized on
purpose: they hold hashes of public DMI strings, no serials).

| Step | Result |
| --- | --- |
| 1 input | keyboard, touchpad, touchscreen, EC hotkeys, power key all registered |
| 2 boot report | release `-20`, model `(test)`; hardware RNG is `qcom_hwrng` |
| 2 chid | `check-chid.sh` saved `systemd-analyze chid`, stubble's `hwids.py` output (with the panel EDID `SDC4214`) and `fwupdtool hwids` for the stubble pull request |
| 4 RTC | `rtc0` registers (`rtc_qcom_glink`) but logs `0x68 failed (-110)` and `all time sources failed`; `check-rtc.sh` not run |
| 4b EC | see below; fan 2.5 krpm and four thermistors read; backlight timeout 30 s / always / 3 min write and read back (30 s and always behaved as set); F5 cycles 1, 0, 2 with the GNOME OSD each time; `platform::kbd_backlight` ignores writes as intended; both mute LEDs follow their `platform::*` writes |
| 5 audio | three SoundWire devices attached (both amplifiers and the `wcd9378` headset codec on link 3); left and right tones on the right sides; muted recording silent; **F6 and F9 showed no GNOME icon**: the function row was in function-key mode (below) |
| 9 GPU | glmark2 10881, vkcube 1000 frames, GPU at 1.35 GHz, no hangcheck |
| 10 NPU | the CDSP runs and `/dev/fastrpc-*` exist, but `fastrpc-tests` is not an apt package here (`Unable to locate package`), so no FastRPC test ran |
| not run | efivars write, USB, headset, charging, battmgr notifications, power button, suspend, boot B and C |

## Boot warnings new in `-20`

- `UBSAN: shift-out-of-bounds` in `sound/soc/sdca/sdca_asoc.c:501`
  (`sdca_asoc_populate_dapm`, shift exponent 64 on a 64-bit type), at
  module load of `snd_soc_sdca_class_function`; once per boot.
- `snd_soc_sdca.SimpleJack.0: ASoC error (-16)` reading a register, four
  times in the first ten seconds after the card appears.
- `nvme: failed to set target rate Gen5 (-11), trying rollback to Gen1`.
- `soundwire sdw:3:0:0217:0110:00:3: no matching ACPI device found, ignoring
  peripheral` and `wcd9378 ... SWFT not available`.

## check-ec.sh changed the function-row mode

The row started in action-keys mode (F7 sent volume-down, `fn_lock` read 1).
After the script it was in function-key mode, and stayed there: the
terminal received F7 escape codes while the next question was waiting
(`answer: [18~[18~...`), and the F-key capture and the audio check afterwards
show F5, F6, F9 and F11 as plain F-keys.

Why, from the script and `patches/kernel/upstream/qcom-next/0005`:

- `fn_lock_show` returns 1 when the EC's `0xBD/0x01` reply is 1, and that
  is the **action-keys** state (read 1 with F7 = volume-down; read 0 after
  Left Shift+Fn with F7 = F7).
- `fn_lock_store` follows the ABI text instead, where 1 means function
  keys: it writes the OS flag `0x80` *without* the set bit for 1, which
  clears action-keys mode.
- So `echo "$orig" > fn_lock`, the script's restore, flips the mode instead
  of restoring it. This is the same flag as the 2026-10-22 incident (clearing
  `0x80` made the row plain F-keys).
- The effect on the keyboard also trails the write by one step: F7 after
  `wrote 0` still sent F7 and F7 after the restore sent volume-down, then F7
  again on the next press. The `fn_lock` read after the restore (1) did not
  match the keyboard either.

The sysfs read now says 1. The mode on the keyboard is whatever F6 and F7
do (press them without Fn); `Left Shift+Fn` toggles it back without any
write from us. Not fixed in the series yet: show and store need the same
polarity (`show` as `reply[0] != ON`, matching the ABI text), and the
script's restore must write the value in the polarity it read.

## Open: F6 long press

Per the owner, a long press of F6 changes the keyboard backlight timeout
(an EC-side action, the same three values as `kbd_backlight_timeout`), and
GNOME shows nothing. No `EC event` line for it exists in these logs (event
logging was on, and no long press was made). To capture it: leave
`dyndbg` on, read `kbd_backlight_timeout`, long-press F6, read it again
and `journalctl -k | grep "EC event"`. If the EC raises an event the driver
can notify `kbd_backlight_timeout` and the OSD can be a desktop-side matter;
if it raises none, nothing can tell the desktop.

## Follow-up: the Fn toggle and the headset (same boot)

**Fn toggle.** After `check-ec.sh` Left Shift+Fn no longer toggled the
function row: no `EC event 0x88` and no interrupt for several minutes
(`captures/2026-11-10-k20/fn-lock-watch.txt`). Writing `fn_lock` 0 as the
owner did (action-keys flag set again) brought the media keys back, as on
2026-10-22. After a write the EC no longer reports the Fn+Shift toggle until
the flag is set again; the series needs the show/store polarity fix above
and a script that never restores through the inverted write.

**Headset (`headset-test-20261110T132742.txt`).** A 4-pole headset with a
microphone and one button: nothing played, the microphone recording was
silent (peak 0), the button sent no event, and no kernel line appeared when
the plug went in or out. What the log shows:

- The wcd9378 is `Attached` on link 3 and the headset reset line (TLMM 191)
  is high, so the codec is alive. No audio errors while the tones ran, and
  the DSP side routed `RX_CODEC_DMA_RX_0` (the script printed it on).
- **`FU 6 Channel Switch` is `off,off`** (muted) with the volume at 25088
  of 65535, and nothing in the UCM profile touches it: `HiFi.conf` has no
  headset device at all. That alone silences the headphone path. Not yet
  tried: set it on with a headset plugged in.
- **Jack detection is not working.** `Headphone Jack` reads on and `Mic
  Jack` off with nothing plugged, and the script's before/after jack state
  lines printed no values. `GE 35 Detected Mode Switch` is read-only with
  `min=0,max=0`, and reading it triggers a second UBSAN
  (`soc-ops.c:169`, `snd_soc_get_volsw` via `volatile_get_volsw` in
  `snd_soc_sdca`, shift exponent 64). The first UBSAN (`sdca_asoc.c:501`) at
  module load is the same shift: the SDCA control for the detected mode is
  built with a 64-bit width, hence `max=0`. The `ASoC error (-16)` reads of
  register `0x40c00908` fit a jack detect register being read while the
  codec is busy. So the jack-detect interrupt path and the control range
  both need the SDCA fix before the buttons or plug events can work.
- The microphone path (`TX_CODEC_DMA_TX_3`) was routed and recorded silence;
  with the jack not detected, the codec's input is probably not selected
  (`GE 35 Selected Mode` stays 0).

## Follow-up 2: unmuting the headset path, with the headset plugged in

Before: `FU 6 Channel Switch` off,off, volume 25088, `RX_CODEC_DMA_RX_0`
route off, `WSA_CODEC_DMA_RX_0` route on. Set `FU 6` on, the RX route on and
the speaker route off, then `pw-play` a 3 % amplitude 1 kHz tone, left and
right. Neither `pw-play` finished: each sat in `epoll` until killed (about
60 s), with no kernel message, no `CMD timeout`, `wpctl` answering and all
three SoundWire devices `Attached`. The stream never started, so no sound was
tested. Every control was put back to the values above. The sink PipeWire
plays to is still the speakers' (`Internal Speakers`, `MultiMedia1`) and the
card has no headset sink, so the mixer routing alone does not make a
stream run; the headset needs its own UCM device and sink, which waits for
jack detection (the SDCA `max=0` range bug above).

## NPU setup

`check-npu.sh` asked apt for `fastrpc-tests`, which does not exist. Ubuntu
has `fastrpc-support` (daemons, udev rules), `libfastrpc1` and
`libfastrpc-dev`, and no test binary. `scripts/linux/glymur-ssd/setup-npu.sh`
installs those plus a toolchain, builds `fastrpc_test` and
`fastrpc-healthcheck` from Qualcomm's source (pinned at `8f59273`) into
`/usr/local/bin`; `check-npu.sh` now runs the healthcheck first. Not built
or run here (no compiler on the laptop, `sudo` needs the owner). Known
limit: the upstream test's skeletons are Hexagon v68/v75, and this NPU is
v81 (HP's `libQnnHtpV81Skel.so`), so `fastrpc_test` may start the CDSP
session and still fail to find a matching skeleton; the healthcheck and the
session setup are the first result to read. The `hexagon-dsp-binaries-*`
packages are other boards' files and are not installed.

## NPU, first run (`npu-test-20261110T134423.txt`)

`setup-npu.sh` and `check-npu.sh` ran as the owner. The CDSP and ADSP are
`running` in `/sys/class/remoteproc`, `/dev/fastrpc-*` exist, and
`fastrpc-healthcheck` still reports both DSPs `Offline`, DSP build ID and
dynamic libs path `N/A`. Two gaps on the Linux side, both about where
FastRPC looks:

- It maps the machine to its DSP directory with a YAML file in
  `/usr/share/qcom/conf.d/`, keyed on the device-tree model string; there
  was none. `setup-npu.sh` now writes one for the daily, test and A/V
  models (`DSP_LIBRARY_PATH: glymur/HP/omnibook-5-16-bf1xxx/dsp`, where
  install-from-usb puts HP's `fastrpc_shell_3` and `libQnnHtpV81Skel.so`).
- Its firmware check uses `/lib/firmware/<remoteproc firmware>`, while HP's
  files are in `/lib/firmware/updates/qcom/glymur/HP/...` (the kernel
  searches `updates` first), so it counts the firmware as missing. The
  script adds a symlink `/lib/firmware/qcom/glymur/HP` to the `updates`
  one.

Both land the next time `sudo bash ~/setup-npu.sh` runs (it is idempotent);
then `sudo bash ~/check-npu.sh` again. `fastrpc_test` itself printed `Error
opening directory /usr/local/lib/fastrpc_test`: it wants its sample skeletons
installed, and those are Hexagon v68/v75 while the NPU is v81, so it cannot
run a real offload here. The healthcheck result decides the next step
(a v81 skeleton, or a QNN-based test through HP's `libQnnHtpV81Skel.so`).

## NPU, second run (`npu-test-20261110T140603.txt`)

With the machine YAML and the firmware link in place, `fastrpc-healthcheck`
reports both DSPs `Online`, firmware build ID
`CDSP.HT.3.3-00304-GLYMUR-1_20260114_014505`, the DSP libraries path
`/usr/share/qcom/glymur/HP/omnibook-5-16-bf1xxx/dsp`, and for the CDSP signed
and unsigned PDs. It still said "Missing FastRPC user-space libs": the
healthcheck only searches the libdir it was configured with
(`/usr/local/lib`) and `/usr/lib`, not Ubuntu's
`/usr/lib/aarch64-linux-gnu`. With `LD_LIBRARY_PATH` set to that directory
(it reads the variable) the result is **CDSP: FastRPC Support Yes**. The
ADSP says "Missing shell build ID": HP ships a CDSP shell only, which is
fine for the NPU. `check-npu.sh` now sets the variable.

New: `scripts/linux/glymur-ssd/npu-caps.c`, a read-only query of the CDSP's
capabilities (architecture version, HVX, VTCM, HMX) through
`remote_handle_control`. Built as the owner it gets `rc=114` on everything
but `DOMAIN_SUPPORT` (1) because `/dev/fastrpc-cdsp` is root-only, so
`check-npu.sh` compiles and runs it as root. `fastrpc_test` is still blocked
on its v68/v75 sample skeletons.

## NPU, third run: first capabilities (`npu-test-20261110T140930.txt`)

`npu-caps` asked the CDSP through FastRPC, all calls `rc=0`: domain
supported, unsigned PD supported, HVX 128-byte contexts 8, 64-byte 0, VTCM
one 8 MiB block, `ARCH_VER` 32897 (`0x8081`: Hexagon v81), async FastRPC and
user-PD status notification supported, HMX depth/spatial reported 0 (the
query may not cover this HMX generation; unverified). So the NPU answers
FastRPC from userspace with HP's signed firmware and shell. What is missing
for real work is a v81 skeleton and its host stub: `fastrpc_test`'s samples
are v68/v75, and HP's `libQnnHtpV81Skel.so` needs Qualcomm's QNN host
libraries.

## Suspend (boot A, test tree) and boot B (A/V tree)

`captures/2026-11-10-k20/suspend-test-*.txt`,
`journal-kernel-suspend-freeze-boot.txt`.

**Cycles.** The first script run stopped at its own "Continue?" (answered
"stopped"). The second ran three cycles:

| Cycle | Result |
| --- | --- |
| rtc | `rtcwake: read rtc time failed`: the RTC has no time source (`rtc_qcom_glink ... all time sources failed`), so no alarm. The owner woke it: wake IRQ 257, the touchpad (`hid-over-i2c`, GPIO 3); asleep 108 s. Power LED breathing, keyboard backlight off, fan unsure. Wi-Fi came back. |
| lid | closed, charger unplugged and replugged while asleep, opened: woke on the lid line (GPIO 92) after 39 s. Wi-Fi came back; screen, keyboard and touchpad "seem ok"; USB untested. |
| button | **froze.** The log ends at "Suspending in 3 s". The journal's last kernel line is `PM: suspend entry (deep)` with nothing after it. |

**Deep sleep is not available.** Every cycle shows `suspend entry (deep)`,
`Freezing`, `Disabling non-boot CPUs`, then `Enabling non-boot CPUs` and
`suspend exit` within 0.2 s, with `last_failed_errno:-95` (not supported):
the firmware does not implement PSCI system suspend. systemd then retries as
`suspend entry (s2idle)`, and that is the sleep that worked. On the way down
the deep attempt logs `dwc3-qcom ... port-1 HS-PHY not in L2` for all four
USB controllers and `qcom-pcie 1bf0000.pcie: Timeout waiting for L2 entry!
LTSSM: 0x11`, and on the way up `geni_i2c ...: Unbalanced
pm_runtime_enable!` for four controllers. The freeze happened inside such a
deep attempt, before `Freezing user space processes`, so the journal could
not say more. `check-suspend.sh` now writes `s2idle` to `/sys/power/mem_sleep`
for the test (restored at the end; `--deep` keeps the default), turns on
`pm_debug_messages` and `pm_print_times` so each device step is logged, and
syncs the journal before each cycle. A permanent setting would be
`mem_sleep_default=s2idle` on the kernel command line. `last_failed_errno`
and the `Gen5` NVMe line (`failed to set target rate Gen5 (-11)`, every few
seconds) are also worth a look.

**Prompts.** The script's questions went through the log pipe, where `sed`
only passes complete lines, so a prompt appeared after the answer; and keys
pressed while it slept (the wake-up presses) answered the first question
with an empty line, shifting every answer by one. Questions now go to the
terminal directly, stale keys are discarded, and they are single short
questions with their options. Function-key escape codes are stripped from
answers in `check-ec.sh`, `check-audio.sh`, `check-headset.sh` and
`check-rtc.sh`.

**Boot B (A/V tree), checked from the running system.** Model `(test, A/V)`,
command line without `$cmdline` (no `clk_ignore_unused`, `pd_ignore_unused`,
`arm64.nopauth`): `paca pacg` in `/proc/cpuinfo`, `Address authentication
(architected QARMA3 algorithm)` detected, `clk: Disabling unused clocks` and
`PM: genpd: Disabling unused power domains` in the log. `DP-1` and `DP-2`
connectors exist (disconnected), no DP errors, no `CMD timeout`, three
SoundWire devices attached, keyboard, touchpad, Wi-Fi and the camera
(`xhci-hcd.0.auto`) work. Iris is on and fails exactly as before: twelve
`video_cc_mvs1_gdsc status stuck at 'off'` / `power on failed` from
`v4l_id` opening the node, because the WirePlumber file that keeps it away
from the video nodes (runbook B step 1) was not installed before this boot;
`wpctl` still answers. Not run: B step 3 (the UEFI write of A step 3 was
never made, so there is nothing to verify), step 5 (A's suspend did not
pass), step 6 `sudo bash ~/check-video.sh --mahua`, step 7 displays.

## Video, boot B step 6: `check-video.sh --mahua` (`video-test-20261110T144352.txt`)

The first attempt (`video-test-20261110T143803.txt`) stalled on a script bug:
`timeout` started `ffmpeg` in the background while it read the terminal, so
the shell stopped both (state `T`) and the 30 s limit could never fire.
`check-video.sh` now passes `-nostdin` to every `ffmpeg`.

Second run, four trials (one core, HFI core ID 2, with/without hardware core
1's bits, pipe 2, and the wrapper power release): **in every trial the
video firmware boots**, which the plain driver never gets to. The firmware
prints its banner (`video-firmware.3.6-aeb98f00...`, `PROD`, built Jan 5
2026), the driver answers its core ID and pipe properties, and a decode
session starts. No trial decodes: `ffmpeg` is killed after 30 s (exit 137)
and the driver then logs `skip power collapse, wfi=0x0 idle=0x0 pcr=0x0
ctrl=0x1` / `failed to suspend` about every 1.5 s (20 times per trial).
The wrapper power control still reads `0x3` after the release (`timed out,
bit 0x10`) in the trials that wait for it; trial 3 (no hardware-core bits)
reports the core on (bit 0x2).

One firmware complaint repeats in every trial and does not discriminate
between them: `vDec_AttachInternalBuffers(862): Buffer type 5 should be
used for AV1 only`. Type 5 is `HFI_BUFFER_PARTIAL_DATA`; in this kernel tree
`BUF_PARTIAL` sits in the decoder's input internal-buffer table for every
codec (`sm8550_dec_ip_int_buf_tbl`) and `iris_vpu_dec_partial_size()`
returns the AV1 IBC size from the picture size whatever the codec. Whether
that is what stalls the H.264 session, or only noise, is not established.
Next candidates: attach the partial-data buffer for AV1 only and rerun
trial 1; read the firmware's session messages before the stall; compare
with what Windows' log shows for the same stream.
