# Audio: The Headset Codec Path and What It Needs, October 17, 2026

Follows `docs/audio-evidence-2026-09-29.md` and
`docs/audio-acpi-tree-2026-09-30.md`. Read-only work: Windows PnP and
registry on this laptop, HP's driver store, the DSDT kept privately in
`.work/`, and the Linux MSM laptops kernel (`topic/glymur-laptops`,
`c9f816899dc2`). Nothing was booted.

## The codec is the WCD9378, and Linux can now drive it on a device tree

The only SoundWire peripheral, `MAN_0217&PART_0110`, is Qualcomm's WCD9378
("Tambora"). Two things that blocked it on 2026-09-29 are gone in
linux-next (both accepted, 2026-09-25):

- `ASoC: codecs: add Qualcomm Tambora (WCD9378) SDCA codec` matches
  `sdw20217011000` and carries a static SDCA description, transcribed
  from the part's DisCo tables, for ARM machines without ACPI.
- `ASoC: SDCA: allow building without ACPI` drops the `depends on ACPI`.

## HP's evidence against the reference design

The Lenovo ThinkPad T14s Gen 7 (Mahua) device tree in the laptops kernel
enables the same codec. Each of its values, checked against this laptop:

| T14s | HP OmniBook 5 evidence | Agrees |
|---|---|---|
| `reset-gpios = <&tlmm 191 GPIO_ACTIVE_LOW>` | DSDT `ASCD` `GpioIo` pin 191 | Yes |
| no interrupt line | DSDT `ASCD` `GpioInt` (PDC 640 = GPIO 193); `ASCDResources.bin` configures TLMM GPIO 193 | HP has one more line |
| — | DSDT `ASCD` `GpioIo` pin 2 | Unknown purpose |
| `vdd-buck`, `vdd-rxtx`: L15B 1.8 V | `ACDResources.bin` and `ASCDResources.bin` vote LDO15_B 1.8 V | Yes |
| `vdd-io`: L18B 1.2 V; `vdd-mic-bias`: BOB | no vote from either audio device | Not evidenced |
| DMIC bias (`vdd-micb`): L1B 1.8 V | both files vote LDO1_B 1.8 V | Yes |
| codec on `swr2` with `swr1` as one multi-master bus, 4 lanes | DSDT `QSJ0` maps lanes 1–4 to manager lanes 1–4 | Yes |
| data ports: 2 capture; 6, 7, 8 playback | DSDT `QSJ0`: source ports 2 and 4, sink list `0x1C0` (6, 7, 8) | Yes |
| `reg = <0 3>` (unique ID 3) | `QSJ0` `_ADR` is zero; `SJ01` `_ADR 3` is the SDCA function number | Not evidenced |

`ACDResources.bin` and `ASCDResources.bin` are the `AeoB` power-resource
files of HP's `qcaucd_ext` and `qcascd_ext` driver packages (the same
format as the PEP tables). The registry of the audio core
(`ADCM\…\Device Parameters\AUCD`) adds: MBHC (headset detection) on,
an external mic bias, two SoundWire slave types (one enabled), and AUCD's
two GPIOs (ACPI pins 204 and 205) starting low.

## Speakers and microphones

From HP's driver pack (`qualcomm-driver-pack/src/Driver/`) and the
installed drivers:

- **HP runs Qualcomm's CRD audio configuration.** Every `_ext` package
  (`qcaucd_ext_crd8480`, `qcascd_ext_crd8480`, `qcasd_CRD_HWoffload`,
  `qcacsp_crd8480`) matches `SUBSYS_CRD08480` and HP's `8F03103C`,
  `8F46103C` and `8F47103C` with one shared settings section. Only the
  calibration (this laptop: `acdb_cal4.acdb`, `REV_04`) and the speaker
  calibration variable (`HpCustomGuid`, `SmartAmpCalibrationData`) are HP's.
  So HP's audio hardware is close enough to the Glymur CRD to run its
  configuration.
- **Speakers: stereo, WSA884x-class smart amplifiers.**
  `qcasd_CRD_Extension8480.inf` gives the speaker endpoint two channels
  (front left and right, 48 kHz, 24-bit), a loopback (V/I feedback) pin and
  speaker protection; `qcadcm8480.inf` sets up the 8 kHz, 32-bit V/I-sense
  stream. The internal-codec driver `qcaucd8480.sys` drives WSA884x
  (`wsa884x_configure_pa_fsm`, `GetWSAData`, `kundu_wsa_enable`) and no other
  amplifier family. The Glymur CRD has four WSA8845 (left on `swr0`, right on
  `swr3`, reset by LPASS TLMM pins 12 and 13); the T14s has two on `swr0`.
  HP's amplifier count, bus and reset lines are not evidenced. `AUCD`'s two
  GPIOs (ACPI pins 204 and 205, driven low at start by `qcaucd`) are SoC
  eGPIO pins (192–244 can be handed to LPASS); whether they are the
  amplifier resets is not shown.
- **Microphones: two.** `MicArray1` has `NumberOfMicrophones = 2` through
  the internal codec, which points to DMIC0/1 on the VA macro (the T14s uses
  `dmic01`; the CRD `dmic01` and `dmic23`). HP votes LDO1_B at 1.8 V, the
  T14s DMIC bias rail.
- **The SoundWire controller driver** (`QCASCD8480.sys`) runs SoundWire
  multi-master on its RX and TX links and writes `TAMBORA_DIGITAL_INTR_MODE`
  for the SimpleJack function, confirming the WCD9378 path above.
- **Remaining sources:** the ACDB (`acdb_cal4.acdb`, AudioReach chunk
  format) holds the codec-peripheral module data the SoundWire driver reads
  (`AcdbGetCodecPeriphModuleData`): the amplifier and port configuration.
  A boot that brings up the SoundWire controllers would list every
  peripheral that attaches, with its manufacturer, part and unique ID.

qcom-next already carries the Glymur CRD's WSA speaker and VA DMIC sound
card (`glymur-crd.dtsi`), so the speaker and microphone path, unlike the
headset codec, does not depend on unposted patches.

## What a headset-jack build would need

| Piece | Upstream state |
|---|---|
| WCD9378 codec driver and binding; SDCA without ACPI; SDCA class library | Accepted (linux-next) |
| SoundWire: match by DT compatible; SCP address-page caching | Accepted (linux-next) |
| SoundWire multi-master (`add multi-master support`, `program MM_SYNC`) | Posted, v2, 2026-10-01 |
| Glymur LPASS and LPASS audio clock controllers | Posted, v3, 2026-10-02 |
| `glymur.dtsi` LPASS glue and SoundWire nodes; RX/TX macro v2.9 and NPL clock; multi-port streams, per-port channel masks, multi-master broadcast and SSP; SDCA per-port bandwidth | Not posted (laptops kernel only) |
| AudioReach topology | `linux-msm/audioreach-topology` has `MAHUA-LENOVO-ThinkPad-T14s-Gen7.m4`; HP needs its own |

qcom-next has none of the accepted or posted pieces yet.
