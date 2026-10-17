# Audio: Carrying HP's Speaker and Microphone Tuning to Linux, October 17, 2026

Goal: the speakers and microphones should sound as they do on Windows. On
Windows, HP's tuning runs inside the audio DSP (ADSP), built from HP's
calibration database. Linux runs the same ADSP firmware (HP's
`qcadsp8480.mbn`), so the tuning can, in principle, run on Linux in the same
place. This note records what the tuning consists of and how to carry it
over. Read-only work on this laptop's driver store and HP's driver pack, and
open-source code from Qualcomm's AudioReach project.

## Where the tuning lives on Windows

- **Calibration database:** `acdb_cal4.acdb` from HP's `qcacsp_crd8480`
  package (selected for `SUBSYS_8F47103C&REV_04`). It is AudioReach's ACDB
  format, which `AudioReach/audioreach-graphservices` (`acdb/`) parses; the
  walk in `docs/audio-headset-path-2026-10-17.md` resolves all of it: 113
  graphs, 181 subgraphs, 1,248 module instances, 188 parameter IDs in 13,612
  calibration entries.
- **Per-laptop calibration:** the UEFI variable `SmartAmpCalibrationData`
  (GUID `{53559579-8753-4f5c-9130-E82ACFB8D893}`, from `qcadcm8480.inf`),
  most likely each speaker's measured resistance and temperature (R0/T0).
- **Dynamically loaded DSP modules:** the `fai__*.pmd` ("Fluence AI") and
  `ffv__*.pmd` files in the same package.

## The speaker path

Graphs ending in the speaker device subgraph (`0xB0000001`), one per stream
type (key `0x1000002` = 1–7). The deep-buffer graph (`0x1000002` = 2):

| Subgraph | Modules (calibrated parameters) |
|---|---|
| `0xB0000074` stream | PCM decoder, soft pause, MFC, **POPLESS_EQUALIZER** (`0x0800110C`, 112 B), volume |
| `0xB0000075` device processing | `0x07001097`, **SAL** limiter (`0x08001050`, 36 B), sync, volume, **`0x0701000D`** (`0x0800137B`, **87,396 B**, plus five small parameters), MFC |
| `0xB0000001` speaker device | **SAL**, splitter, logging, **SPEAKER_PROTECTION** v5 (19 parameters, among them `0x080011E8` 68 B, `0x08001258` 1,520 B, `0x0800134A` 2,188 B, `0x08001532` 988 B, `0x08001AEC` 3,104 B), codec DMA (WSA) |

The low-latency graph (`0x1000002` = 1) uses an **MSIIR** EQ (three
parameters: coefficients, stages, gains) in its device stage instead.
`0x0701000D`'s 87 KB parameter is the largest in the database and the most
likely carrier of HP's speaker voicing. The speaker-protection parameters
are the v5 set (`0x080011E8`–`0x080011EE`, as in
`spf/api/modules/sp_rx.h`), which is the generation the Linux kernel's
AudioReach driver supports (`PARAM_ID_SP_OP_MODE` = `0x080011E9`). The V/I
side has `SP_VI_STATIC_CFG` (`0x080011F6`, 44 B) and `SP_VI_CHANNEL_MAP_CFG`
(`0x08001203`, 20 B: a channel count and four V/I entries, two speakers).

## The microphone path

The microphone graphs use `SMECNS_V2` (echo cancellation and noise
suppression) with `EC_SYNC`, `IIR_MBDRC`, MSIIR, gain and volume, and module
`0x070010D9`, which HP's endpoint INF names "Fluence NN NS" (neural noise
suppression). Which graph serves "Microphone Array" is still to be mapped.

## The modules exist in the firmware Linux runs

Each of `0x0701000D`, `0x070010D9`, `0x070010E2` (speaker protection),
`0x07001014` (MSIIR) and `0x07001097` occurs exactly once in HP's
`qcadsp8480.mbn`, consistent with a module registry entry (a chance 4-byte
match in 21 MB is unlikely for one ID, let alone five). The DSP accepting
the module at graph setup is the proof. `0x0701000D` also occurs in two
`fai__*.pmd` files.

## What Linux can take today

- **Topology modules with private data:** the kernel's AudioReach topology
  stores a per-module configuration blob (`SND_SOC_AR_TPLG_MODULE_CFG_TYPE`)
  and `audioreach_set_module_config()` sends it to the DSP unchanged, as a
  list of `<instance, parameter, size>` records, which is the ACDB's own
  calibration format. This is upstream's mechanism for exactly this job:
  `c7ed4c2debfd` ("ASoC: qcom: audioreach: add support for static
  calibration", Srinivas Kandagatla, 2025) adds it "for ECNS and speaker
  protection", with the blob written in the topology as a `SectionData`
  of words. Upstream calls it only for `MODULE_ID_SMECNS_V2` (linux-next of
  2026-10-17 too); every other module's blob is ignored.
- **Speaker protection:** the kernel enables the SP and SP VI modules (mainline
  `0db76f5b2235`, `3e43a8c033c3`, `b481eabe5a19`) with the operating mode and
  V/I channel map only; no topology in `linux-msm/audioreach-topology` uses
  them yet.
- **EQ and dynamics parameter layouts** are public:
  `audioreach-engine/modules/processing/filters/multi_stage_iir/api/api_msiir.h`
  and `.../gain_control/iir_mbdrc/api/mbdrc_api.h`.

## Plan

1. **Kernel (done, `-14`):** `patches/kernel/upstream/qcom-next/0006`
   sends a topology module's configuration blob for every module that has
   one, not only `SMECNS_V2`, before the media format and the driver's own
   parameters (an upstream candidate once a topology uses it).
2. **Speaker processing on the DSP:** a topology that mirrors HP's
   deep-buffer speaker graph (stream EQ, device processing with SAL and
   `0x0701000D`, device SAL), each module carrying HP's calibration records.
   HP's ACDB is committed unmodified under
   `boards/hp-omnibook-5-16-bf1xxx/firmware/qcacsp_crd8480_fixvoice_WHQL/`
   (from HP's driver pack, identical to the copy Windows installed); a
   tool extracts the records from it and builds the topology.
3. **Speaker protection:** the SP RX module with HP's parameters, the V/I
   feedback capture from the WSA amplifiers (`VISENSE` on, a WSA TX codec DMA
   path into the SP VI module) and the per-laptop R0/T0 from
   `SmartAmpCalibrationData` (below), sent as `PARAM_ID_SP_TH_VI_R0T0_CFG`. Until this works, the volume stays at the
   upstream-style cap.
4. **Microphones:** map the "Microphone Array" graph, then carry
   `SMECNS_V2` (already supported upstream) and the other built-in modules the
   same way. Fluence NN (`0x070010D9`) follows if the DSP accepts it without
   the `.pmd` loading Windows does.
5. **Fallback:** where a DSP module cannot be used, rebuild its effect in
   PipeWire from the decoded parameters (MSIIR and popless EQ as biquads, the
   limiter as a compressor; WebRTC noise suppression for the microphones).

## The per-laptop speaker calibration

Read on Windows as administrator (read-only `GetFirmwareEnvironmentVariableEx`;
the raw variable stays private in `.work/`). It is 76 bytes, attributes
non-volatile, boot-service and runtime access. As 32-bit little-endian words:

| Words | Contents | This laptop |
|---|---|---|
| 0 | 0 | |
| 1 | number of speakers | 2 |
| 2–9 | R0 per speaker, ohms in Q24 (eight slots) | 7.197 Ω, 7.299 Ω, rest 0 |
| 10–17 | T0 per speaker, °C in Q6 (eight slots) | 1600 = 25.0 °C for both, rest 0 |
| 18 | calibration valid | 1 |

The units match `vi_r0t0_cfg_t` in `spf/api/modules/sp_vi.h` (`r0_cali_q24`,
`t0_cali_q6`), and the R0 values sit inside its range (2–64 Ω) and near a
nominal 8 Ω speaker's DC resistance. The values are measured per unit, so
they are read from each laptop, never copied. Linux cannot read the variable
yet (see below); until then they can be captured once on Windows and stored
with the board configuration.

## Checked against upstream practice (2026-10-17)

- **Topology:** `MAHUA-HP-OmniBook-5-16-bf1xxx.m4` builds to a file
  byte-identical to `linux-msm/audioreach-topology`'s
  `GLYMUR-ASUS-Zenbook-A14-UX3407NA.m4` (two WSA884x, two DMICs). As there,
  the file is named after the sound card's `model`
  (`qcom/glymur/<model>-tplg.bin`, `<SoC>-<vendor>-<product>`), and
  installed into a board directory with a link at that name.
- **UCM:** upstream alsa-ucm-conf (`master`, not yet in a release; Ubuntu
  26.04 ships 1.2.15.3) selects Glymur laptops by DMI in
  `Qualcomm/glymur/glymur.conf` and shares the WSA884x and WSA-macro
  sequences. HP's profile is the Zenbook A14 one with those sequences
  copied from `master`, selected by the card's long name, which UCM tries
  before the driver-wide file, so it works with any release and never
  replaces a packaged file. Upstreaming it means one DMI entry there.
- **Speaker tuning in userspace** (PipeWire filter-chain EQ, as some
  laptops without DSP tuning use) stays the fallback of step 5: HP's
  tuning runs in the ADSP on Windows, and the same firmware runs here.
- **Speaker protection:** upstream has the SP and SP VI modules and their
  operating mode only; no published topology uses them yet. Until it runs
  here, the gains are upstream UCM's for two WSA884x (WSA digital volume
  84, PA volume 12 at enable); users report 84 as loud, so a lower
  default is worth checking on this laptop's speakers.

## Open questions

- What `0x0701000D` and `0x07001097` are (vendor speaker processing is the
  working assumption for the first).
- Whether Linux can read UEFI variables at all on this laptop (needs QSEECOM,
  not allowlisted for this model).
