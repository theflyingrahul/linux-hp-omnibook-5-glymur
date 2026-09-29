# Audio: What Windows Binds and What Linux Has, September 29, 2026

Groundwork for audio, the next subsystem after the GPU. This note uses
read-only Windows PnP queries on this laptop and the pinned qcom-next tree
(`e428097a36d` plus our series). Nothing has been tested on Linux yet.

## Windows device tree (read-only `Win32_PnPEntity`)

| Device | Windows driver | Meaning |
|---|---|---|
| `ADCM\VEN_QCOM&DEV_0FB7&SUBSYS_8F47103C` "Qualcomm Aqstic" | `qcaucd` | LPASS audio core |
| `ADCM\VEN_QCOM&DEV_0FF4` "Aqstic AudioDriverX" | `qcadx` | Qualcomm ACX audio driver |
| `AUCD\VEN_QCOM&DEV_0FCD` "Aqstic ACX Audio Device" | `qcasd` | Audio endpoints |
| `QCASD\...DEV_0FCD...` "ACX Static Endpoints Audio Device" | (child) | Fixed endpoints: the internal speakers and microphones |
| `SOUNDWIRE\SDCA_PERIPHERAL_10&MAN_0217&PART_0110&VER_00` | Microsoft `SdcaMfd` | The only SoundWire peripheral |
| ...`FUNC_0001&TYPE_0A` | Microsoft `SdcaHid` | SDCA HID function: jack buttons |
| ...`FUNC_0003&TYPE_08` (+ dynamic speaker/microphone endpoints) | Microsoft `SdcaClass` | SDCA SimpleJack function: the headset jack |
| "Aqstic ACX Headset Render/Capture Audio Device", "QCSDCA Speaker/Microphone (Ext)" | (ACX children) | Headset endpoints and Qualcomm's SDCA extension |

The type codes come from `include/sound/sdca_function.h`: `0x08` is
`SDCA_FUNCTION_TYPE_SIMPLE_JACK` and `0x0A` is `SDCA_FUNCTION_TYPE_HID`.

## What this says

- **The SoundWire codec is Qualcomm's.** MIPI manufacturer `0x0217` is
  Qualcomm; the in-kernel WCD937x/938x/939x and PM4125 SoundWire codecs
  use the same ID. Part `0x0110` is not in any Linux driver.
- **It is a headset-jack codec, driven by class drivers.** Windows runs it
  with Microsoft's generic in-box SDCA drivers, not a Qualcomm codec
  driver. That makes it an SDCA-class-compliant device: jack audio plus
  jack buttons.
- **The internal speakers and microphones are not on it.** They are
  "static endpoints" of Qualcomm's ACX driver, and Windows lists no other
  SoundWire peripheral (no WSA amplifier). How they connect (LPASS macros
  to DMICs and an amplifier on another bus) is still unknown. HP's DSDT
  audio devices and the ADSP audio configuration are the evidence to read
  next.

## What Linux has (qcom-next)

- **Machine driver:** `sound/soc/qcom/x1e80100.c` matches
  `qcom,glymur-sndcard`, and the ASUS Zenbook A16 DTS uses it, so there is
  precedent for Glymur audio on DT.
- **Hardware nodes:** `glymur.dtsi` has the LPASS pieces: `q6apm`,
  `q6prm`, the WSA/WSA2/VA macros, and SoundWire controllers
  (`qcom,soundwire-v3.1.0`).
- **SDCA:** the core (`sound/soc/sdca/`) exists, but `SND_SOC_SDCA`
  **depends on ACPI**. `sdca_functions.c` reads the function descriptions
  (DisCo `_DSD`) from ACPI device nodes. On a device-tree boot the Linux
  SDCA stack has nowhere to read them from.
- **SDCA class driver:** `sdca_class.c` matches only three Cirrus Logic
  parts (`0x01FA`: `0x4245`, `0x4249`, `0x4747`). This build has no SDCA
  options set.

## Consequences

- The headset jack needs SDCA on a DT boot, which upstream Linux does not
  support today. Alternatively, it needs a Qualcomm part-specific driver
  for `0x0110`, which does not exist.
- The internal speakers and microphones may be reachable sooner through
  the LPASS path the Zenbook A16 uses, once HP's topology is known. Rails,
  GPIOs and the amplifier must come from HP evidence, not from the
  Zenbook.
- Next evidence: HP's DSDT audio and SoundWire devices (their `_DSD`
  DisCo tables), and the ADSP audio configuration (`adspr.jsn`,
  `adsps.jsn`, `adspua.jsn` in the driver pack), for which endpoints and
  backends exist.
