# Speaker protection for the WSA8845 speakers, November 10, 2026

The speakers are quiet on Linux because the card driver caps them, on
purpose. This note records why, what Windows does instead, what upstream
and other laptops have, what HP's own data provides, and a step plan.
Research only: nothing here was booted. Sources were read on 2026-11-10
(qcom-next `17bbb4b37bbc`, unchanged; linux-next `next-20261109`).

## The cap

`sound/soc/qcom/x1e80100.c`, which also drives `qcom,glymur-sndcard`,
limits the speaker controls when the WSA link starts, "to reduce the risk
of speaker damage until we have active speaker protection in place"
(Tobias Heider's "ASoC: qcom: x1e80100: limit speaker volumes",
`0a5ee0e520ef`, in mainline since 7.1-rc2, after Johan Hovold's same limit
for sc8280xp in 2024):

| Control | Range | Limit |
|---|---|---|
| `WSA WSA_RX0/1 Digital Volume` | 0–124, 84 = 0 dB | 81 = −3 dB |
| `SpkrLeft/SpkrRight PA Volume` (the desktop slider, merged as `Speakers Volume` by UCM) | 0–31, −9 dB + 1.5 dB per step | 6 = 0 dB |

So 100% on the slider is 0 dB of amplifier gain. alsa-ucm-conf's own start
values (digital 84, PA 12) lie above the limits and should be refused; the
`-20` headset check dumps every control with its range, which will show it.
The cap must not be lifted without working protection: even capped,
X1E users report damaged speakers (the Vivobook project below).

## What Windows does

HP's ACDB (`acdb_cal4.acdb`, `docs/audio-tuning-2026-10-17.md`) builds the
speaker device subgraph `0xB0000001` with Qualcomm's speaker protection v5
(`MODULE_ID_SPEAKER_PROTECTION` `0x070010E2`, instance `0x411a`, 19
calibrated parameters) and a V/I feedback graph with
`MODULE_ID_SPEAKER_PROTECTION_VI` `0x070010E3` (`SP_VI_STATIC_CFG`
`0x080011F6`, `SP_VI_CHANNEL_MAP_CFG` `0x08001203`). The feedback module
measures each coil's voltage and current, estimates its resistance and so
its temperature, and passes that to the protection module over a control
link (intent `0x08001204`, 15 references in the ACDB). The protection module
holds the coil below a temperature target and the cone below its maximum
excursion, so the amplifiers can run at full gain.

HP's limits, from parameter `0x08001532` (988 bytes, at the offsets the
Vivobook project found for the same SPv5 layout):

| Value | Left | Right |
|---|---|---|
| coil temperature target (`temp_tgt_q6`, offsets 312/352) | 90 °C | 90 °C |
| maximum excursion (`max_excursion_mm_q27`, offsets 376/688) | 0.38 mm | 0.38 mm |

Parameter `0x080011E8` starts 48000, 16, 2 (rate, bits, channels).

The per-unit calibration is in the UEFI variable `SmartAmpCalibrationData`
(76 bytes, read on Windows; layout in `docs/audio-tuning-2026-10-17.md`):
R0 7.197 Ω and 7.299 Ω, T0 25.0 °C, flag "valid" = 1. It matches
`PARAM_ID_SP_TH_VI_R0T0_CFG` (`0x080011F5`, `vi_r0t0_cfg_t`: `r0_cali_q24`,
`t0_cali_q6`), which is not in the ACDB: Windows sends it at run time from
the variable. Linux can read the variable since `-17` (QSEECOM allowlist,
`upstream/qcom-next/0009`).

Not known: how Windows stages the amplifier gain on this laptop. HP's INFs
carry no WSA884x settings; on the Vivobook, Windows writes `DRE_CTL_1 = 0`
(DRE-controlled gain up to +21 dB), and the protection model assumes that
staging. On Linux it would have to be confirmed against the V/I data (the
measured output should match the model), as the Vivobook project did.

## Upstream on November 10

- The kernel has both modules: `audioreach.c` sets the protection module's
  operating mode (normal) and the feedback module's operating mode, channel
  map and "ex" mode (mainline `0db76f5b2235`, `3e43a8c033c3`,
  `b481eabe5a19`). It sends no thermal model and no R0/T0; those come from
  the topology's calibration blobs and the per-unit data.
- Qualcomm's series "ASoC: qcom: AudioReach and WSA88xx fixes"
  (Srinivas Kandagatla and Ravi Hothi, 2026-10-23, merged by Mark Brown,
  `e163f6f079` in linux-next) fixes the calibration blob size, gives the
  WSA884x V/I port its two channels (V and I), accepts temperatures across
  the full trim range, and disables runtime PM on unbind. `-20` carries all
  of it (`ee381a4d9071`, `3bfe62a9834e`, `fb21afc4f684`, `d4d60beb8e39`),
  plus `3aeb44cd43bf` ("send static calibration for every module"), the
  mechanism that carries HP's ACDB records in a topology.
- No published topology (`linux-msm/audioreach-topology`, newest
  `d6bb205aca`, 2026-10-20) and no alsa-ucm-conf profile uses either module;
  the UCM keeps `VISENSE Switch` at 0.
- Qualcomm's own userspace already does it on Glymur: AudioReach PAL
  "GLYMUR: enable speaker protection support" (PR #109, Shashank Pathmudi,
  merged 2026-11-05): speaker-protection devices and routing for the Glymur
  CRD, quad-channel WSA884x handling, and calibration that reads the WSA
  speaker temperatures from `/sys/class/hwmon`. PAL drives the DSP through
  AGM and a userspace ACDB, not through the kernel's topology route that
  desktop distributions use, so it is the reference for the sequence, not
  code to run here.

## Other laptops

- **Asus Vivobook S15 X1E** (`github.com/justririll/x1e-speakers`,
  GPL-2.0, pushed 2026-10-23, marked experimental): SP RX and SP VI running
  with the Windows ACDB parameters and gain staging. Ten kernel patches: both
  V/I channels (now upstream), a V/I feedback capture DAI on the WSA884x,
  S32_LE capture in q6apm-dai (V in bits 31–16, I in 15–0; S16/S24 lose I),
  per-module config blobs from the topology (the size fix is now upstream),
  module control links (`APM_PARAM_ID_MODULE_CTRL_LINK_CFG` at graph open),
  the SP VI channel map `[2, 1, 4, 3]` (I before V) instead of `[1, 2, 3, 4]`,
  V/I at the stream rate (8 kHz beside 48 kHz playback gave SoundWire bus
  clashes), and two default-off parameters for the Windows gain staging. A DT
  overlay adds a "WSA VI Capture" link and per-port block packing for the
  V/I master ports (the X1E default packs per channel, which gives garbage
  with both channels on). A service keeps a V/I capture running while the
  speakers play and mutes them if the feedback stops; starting V/I before
  playback hung the DSP's APM. Their findings that matter here: without
  R0/T0 the module assumes 2.0 Ω, sees a hot coil and holds −12 dB; with the
  Linux gain cap the protection is about 20 dB more cautious than its model.
  Tests on that laptop: thermal target and excursion limits react as
  expected; about one hour of loud music; V/I sometimes lost on a loud
  track start (amplifiers dropping off the bus, recovered by the service).
- **Surface Pro 11 X1E** (`github.com/geocausa/SP11X1e-audio`): a protected
  speaker graph, also community and unsupported.
- **Apple Silicon** (`speakersafetyd`, Asahi Linux): the same idea in
  userspace, a coil and magnet temperature model fed by the amplifiers' V/I
  sense, acting as a dynamic limiter; the kernel keeps hard limits. It shows
  the split upstream accepts: hard caps in the kernel, the model elsewhere.

## What this laptop has that the Vivobook did not

Measured R0/T0 per speaker (the Vivobook used the ACDB's "safe" values),
HP's own temperature target and Xmax, and the same SPv5 module instance
(`0x411a`) that Windows links. What it lacks: the V/I path in the device
tree, and evidence of HP's gain staging.

## Plan

Each step is testable on its own; the cap stays in place until step 5.

1. **V/I capture with the cap on.** Kernel: the V/I capture DAI and S32_LE
   capture (port the Vivobook patches, checked against upstream style). DT
   (test tree only): the "WSA VI Capture" link on `WSA_CODEC_DMA_TX_0`, and
   the block-pack mode of the Glymur `swr0` master ports that carry V/I,
   whose numbering differs from X1E and must be read from
   `glymur.dtsi`/HP's ACPI first. Test: capture V/I at −30 dBFS and check
   both channels per speaker are alive (no `0x80008000` words) and that I
   tracks V.
2. **Factory test mode.** The feedback module's FTM measures each coil's
   resistance; compare with `SmartAmpCalibrationData` (7.197 / 7.299 Ω).
   A match proves the V/I scaling and the channel map.
3. **Protection in the graph, still capped.** Topology: SP RX in the WSA
   playback device graph and SP VI on the V/I graph, linked, with HP's 19
   SP RX records and the VI records from the ACDB (`acdb-extract.py`; it
   lists SP RX but not yet the VI subgraph, so the tool needs that first),
   and R0/T0 built from the UEFI variable at boot rather than stored. Kernel:
   control links and the channel-map fix. A userspace V/I keeper as the
   Vivobook has, with mute on lost feedback. Test: quiet tones are not
   attenuated, and a test build with a 35 °C target (as the Vivobook did)
   limits smoothly.
4. **Gain staging evidence.** Establish what Windows writes to the WSA884x
   PA/DRE registers on this laptop (Windows driver and registry, read-only),
   then check on Linux that the measured output matches the model.
5. **Lift the cap, only for this card and only with the feedback running.**
   A kernel change that keeps the limits unless protection is active (the
   Vivobook uses a module parameter; upstream would need a cleaner signal),
   then the volume ladder up slowly with the coil temperature logged.

Risks: a wrong channel map or scaling makes the model protect against the
wrong numbers; a lost feedback stream leaves the model blind (hence the
keeper and mute); starting V/I before playback hung the APM on the
Vivobook; the DSP stalls of `-17` show this ADSP can wedge the system. Every
loud test waits for steps 1–4, and nothing is tried loud on the first boot.

Upstream route: steps 1–3 are generic (the DAI, S32 capture, control
links, channel map) and belong on alsa-devel, with Qualcomm's
2026-10-23 series as the base; the topology belongs in
`linux-msm/audioreach-topology`; HP's parameters stay in our board files.
