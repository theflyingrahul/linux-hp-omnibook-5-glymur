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

- **Speakers:** a smart amplifier with speaker protection.
  `qcadcm` (the ADSP calibration manager) sets up a V/I-sense feedback
  stream (8 kHz, 32-bit) and an HP UEFI variable `SmartAmpCalibrationData`;
  the speaker endpoint has a loopback pin and the `SpeakerProtection`
  feature. On the T14s the speakers are two WSA8845 on `swr0`, reset by
  LPASS TLMM pin 12, and WSA884x is the Qualcomm amplifier with V/I sense.
  Whether HP uses WSA884x, on which bus and with which reset line is not
  evidenced: Windows drives such amplifiers inside its audio stack without
  PnP devices, and the calibration files (`qcacsp_crd8480`, this laptop uses
  `acdb_cal4.acdb`) name nothing readable. The ACDB is AudioReach's chunk
  format and can be parsed for its hardware endpoints if needed.
- **Microphones:** a "Microphone Array" static endpoint and the LDO1_B
  vote point to DMICs on the VA macro, as on the T14s. Pins not evidenced.

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
