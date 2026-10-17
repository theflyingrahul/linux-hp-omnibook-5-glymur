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

### The calibration database

HP's ACDB (`acdb_cal4.acdb`) is in the AudioReach format that
`AudioReach/audioreach-graphservices` (`acdb/`) parses: an `ACDB` header
and tagged chunks (`CSLU` → `CAKT`/`CDLU` → `CDDE`/`CDDO` → `POOL`). Walked
that way, all 1,479 calibration rows resolve (Qualcomm's own Linux ACDBs for
GLYMUR and MAHUA in `AudioReach/audioreach-conf`, 399 and 400 rows, check
the walker). What it shows:

- One codec DMA interface record: the **WSA** interface (LPAIF type 2),
  index 3, channel mask `0x3`, with a 32-bit, 2-channel format, which fits the
  V/I-sense feedback of two amplifiers. (This does not decide between one
  and two WSA buses: the CRD also plays to all four amplifiers on `swr0`
  and `swr3` through `WSA_CODEC_DMA_RX_0`.)
- HP's key IDs (`0x0100000E` and up) are a Windows namespace, not the
  Linux `kvh2xml.h` one (where the speaker-protection keys `SP_Dev_Map`
  `0xBE000000` and `SP_VI_Map` `0xBF000000` carry stereo or quad); there is no
  public dictionary for them, so they are not decoded here.

The "codec peripheral" data the Windows SoundWire driver reads
(`AcdbGetCodecPeriphModuleData`) is the ACDB's driver-data section (`GCLU`
→ `GCKT`/`GCDT` → `GCDE`/`GCDO` → `POOL`, as in `acdb_command.c`): 17
module records (`0x08000020`–`0x080000a0`, `0x09000090`) in a Qualcomm
format with no public description. The one readable record, module
`0x08000070`, names its clocks: LPASS `RX_CORE_TX_MCLK`/`2X` (`0x312`,
`0x313`) and `TX_CORE_MCLK`/`NPL` (`0x30c`, `0x30d`) at 19.2 MHz, so it
configures a codec on the RX and TX macros, the WCD9378. No record names a
WSA or WSA2 clock, and none holds a recognisable GPIO or reset line, so the
driver data neither confirms nor rules out a second WSA bus and does not
give the amplifier resets.

A Windows ETW trace of `Microsoft-Windows-GPIO-ClassExtension` (all
keywords, informational level) around one system sound on the speakers
(2026-10-17, kept in `.work/`) recorded only interrupt-flow events on one
`GIO0` bank, after the sound had ended, and no output writes at all. That
provider does not trace pin writes, so it neither shows nor excludes GPIOs
204 and 205 switching the amplifiers. The read-only Windows evidence for the
amplifier reset lines is exhausted.

Every Glymur and Mahua topology in `linux-msm/audioreach-topology` plays
through `WSA_CODEC_DMA_RX_0`; the ThinkPad T14s Gen 7 one describes "2x
WSA8845 speakers, 2x DMIC". HP's stereo speakers, two microphones and
single WSA interface match the two-amplifier count of that layout.

### HP's ACPI interrupts settle the buses

`AUCD`'s three `Interrupt` resources (GSIV 202, 203, 170) are GIC
interrupts, not GPIO-routed ones (the 2026-09-30 note took them for ADSP
identifiers). GSIV = SPI + 32: GSIV 202 is `GIC_SPI 170`, `swr0` (WSA), and
GSIV 203 is `GIC_SPI 171`, `swr3` (WSA2), in `glymur.dtsi`; GSIV 170
(SPI 138) is not in qcom-next's or the laptops kernel's tree. `ASCD`'s GSIV
793 is `GIC_SPI 761`, `swr2`, the WCD9378's primary bus, as expected. So
HP's own DSDT gives the speaker device both WSA SoundWire masters and two
output GPIOs, the CRD's structure of one reset line per bus. With stereo
speakers, one amplifier per bus is the reading the test checks.

## The speaker and microphone test (staged 2026-10-17)

Test device tree only, on kernel `-13`, qcom-next with no extra patches
(it already has the CRD's WSA and VA path): `swr0` and `swr3` enabled, one
WSA8845 node on each (`reg = <0 0>`, reset GPIO 204 and 205, HP's pin
settings), DMIC0/1 on the VA macro, and a `qcom,glymur-sndcard` with the
topology from `boards/hp-omnibook-5-16-bf1xxx/audio/`. No PMIC rail is
declared. Unknown unique IDs do not stop the test: the Qualcomm SoundWire
driver adds every device that attaches (`sdw_slave_add`), so
`/sys/bus/soundwire/devices/` names each amplifier by link, manufacturer,
part, version and unique ID. `check-audio.sh` reports that and, only when
asked, records the microphones and plays a quiet tone per channel.

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

## Live test, kernel `-13` test device tree (2026-10-17): microphones work, speakers don't

`check-audio.sh`, interactive, on the test DT boot:

- **SoundWire enumeration.** `swr0`'s amplifier (`sdw:1:0:0217:0204:00:0`,
  master `6c80000.soundwire`) shows `status: Attached`. `swr3`'s
  amplifier (`sdw:4:0:0217:0204:00:0`, master `6ca0000.soundwire`) shows
  `status: UNATTACHED`. Both reset GPIOs (204, 205) read back `out high`,
  so both amplifiers are held out of reset the same way; only one of the
  two actually joined its bus.
- **Microphones: working.** A real 5 s stereo recording from DMIC0/DMIC1
  through the VA macro: peak 32768 (clipping) on both channels, RMS
  1980/1640 — genuine signal, not silence or noise floor.
- **Speakers: silent, both channels.** The left-tone and right-tone
  playback tests both came back "none" (owner-confirmed). The kernel log
  during playback shows why: `swrm_wait_for_rd_fifo_avail err read
  underflow` and `trf on Slave 0 failed:-5` on `sdw-master-4-0` — the same
  link whose amplifier never attached — then `DPN_PortCtrl register write
  failed for port 1`, `Program transport params failed: -5`, and the
  playback link itself fails to prepare (`WSA Playback: ASoC error (-5)
  at snd_soc_link_prepare()`). The same `qcom_swrm_irq_handler: SWR CMD
  error` on `6ca0000.soundwire` appears at boot, before any test runs.

**Correction, same day:** the SoundWire list in the log has a third
device that the summary above missed: `sdw:1:0:0217:0204:00:1`, a second
WSA884x on `swr0` (unique ID 1), `status: Attached`, unbound because the
test DT declared only ID 0 there. So both amplifiers sit on `swr0`, with
unique IDs 0 and 1, as on the ThinkPad T14s Gen 7, and `swr3` has no
device: its `UNATTACHED` node and command errors are a node for hardware
that is not there, not a fault in `swr3`. Playback failed because the
playback link included that absent amplifier. The reading of HP's ACPI
(one amplifier per bus) was wrong; the interrupt list names both WSA
masters but only `swr0` is populated. Which of GPIO 204 and 205 releases
the amplifiers is still open (both were driven high). Next test: both
amplifiers on `swr0` sharing GPIO 204, `swr3` off, GPIO 205 untouched,
plus an unbind/rebind check that ties the reset line to attach.

## Kernel `-14` test device tree: the upstream reset line

Rechecked against the device trees of the Glymur CRD (qcom-next), HP's
EliteBook X G2q and the ThinkPad T14s Gen 7 (Linux MSM laptops kernel): all
three reset their WSA8845 amplifiers through the LPASS TLMM, GPIO 12 (left)
and 13 (right) on the CRD and the EliteBook. The T14s Gen 7 has this
laptop's layout, two amplifiers on `swr0` (IDs 0 and 1, the same port
maps) sharing LPASS TLMM 12, with no extra pin state on `swr0`. HP's AUCD
GPIOs 204 and 205 are TLMM eGPIOs (192–244, `pinctrl-glymur.c`), and
192 + 12 and 192 + 13 are exactly them. Since HP runs the CRD
configuration, they are taken to be the same two lines. The `-14` test
device tree therefore uses `<&lpass_tlmm 12 GPIO_ACTIVE_LOW>` for both
amplifiers and keeps TLMM 204 reserved, as in the daily tree.
`check-audio.sh` reports LPASS TLMM 12 and 13 and TLMM 204 and 205, and
its unbind/rebind check shows whether LPASS TLMM 12 takes the amplifiers
off the bus. The sound card model is now `MAHUA-HP-OmniBook-5-16-bf1xxx`,
the upstream naming, so the topology is
`qcom/glymur/MAHUA-HP-OmniBook-5-16-bf1xxx-tplg.bin`.
