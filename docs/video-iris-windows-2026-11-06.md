# Video: How Windows Drives Mahua's One Video Core, November 6, 2026

Issue #9. Follows `docs/video-iris-fuse-2026-10-23.md` and the `-17` trials
in `docs/runbook-results-17-2026-10-23.md`. Read-only work on HP's
installed Adreno kernel driver (`qcdxkm8480.sys`, driver 32.0.146.0,
SHA-256 `23745b26…`) and the per-chip configuration files beside it in the
driver store, with LLVM's ARM64 disassembler (no decompiler was available on
this host). Nothing was run on the laptop. Addresses below are the driver's
virtual addresses (image base `0x140000000`).

## Findings

### 1. Mahua has one video engine, powered through `mvs0`

The driver package carries one configuration for the Glymur die
(`qcdxkmbase8480_185.bin`) and three for Mahua (`qcdxkmbase8480_ma_091.bin`,
`_ma_096.bin`, `_ma_185.bin`). They are condition scripts in the PEP format
(`FOOTSWITCH`, `BITWISE_AND`, `EQUAL`/`NEQUAL`, clock names).

- Glymur: two video engines, with properties `HwCoreId` = 1 and 2; its
  footswitch script switches `video_cc_mvs0c_gdsc`, `video_cc_mvs0_gdsc`
  **and** `video_cc_mvs1_gdsc`, the last two chosen by a bit test.
- All three Mahua files: one video engine, `HwCoreId` = 1, and only
  `video_cc_mvs0c_gdsc`, `video_cc_mvs0_gdsc` and `video_cc_mvs0_clk_src`.
  `mvs1` does not appear.

That is why `video_cc_mvs1_gdsc` never turned on under Linux (`-15`,
`-17`): Windows never uses it on this die. It also agrees with Qualcomm's
own `mahua.dtsi`, which deletes the second video thermal zone and points the
remaining one at the sensor Glymur gives core 1 (`tsens1` 8).

### 2. The firmware is told "core 1", chosen from socinfo

`VedParseACPIProperty` (`0x14060b260`) reads `HwCoreId` from that
configuration (the driver calls it an ACPI property) and sets the engine's
hardware core: 1 gives Core0 (`0x100`), 2 gives Core1 (`0x200`). With
Core0 it then checks a flags word, and if bit 0 is set and bit 1 clear it
logs "Overriding eVideoHwCore to Core1, videoPartQultivated" and uses
Core1. Without the property, sub-engine 0 defaults to Core0 under the same
override, sub-engine 1 to Core1.

The flags word is SMEM socinfo (`0x1400ef158` copies the socinfo structure
with checks on its format version that match Linux's `struct socinfo`): from
format 21 on, a second per-part array at the offset in field `0xdc`, whose
element 2 is read. Element 2 is `SOCINFO_PART_VIDEO` in Linux's
`enum qcom_socinfo_part`. So Qualcomm records the cultivated (fused-off)
video core in socinfo, and Windows moves the session to Core1 when core 0
is the one removed.

The host then sends `HFI_PROP_CORE_ID` as `1 << core` ("HFI: type, 1Lshift
core_id", `0x140089628`): mask 2 for Core1. `-17`'s trials found exactly
this: mask 1 refused ("Configured core 0/1 is not supported"), mask 2
accepted.

### 3. Power-on releases the wrapper and waits for core 1's status bit

`0x140611b90` (the video core power-on wait; it branches on the DSDT's SoC
code, `0xa1` Glymur, `0xa8` Mahua) powers Core0 alone when the engine is
Core0, otherwise Core1 alone (both only with a capability bit set). It
writes 0 to `WRAPPER_BASE + 0x84` (Iris wrapper, `0xb0084`), then polls
`WRAPPER_CORE_POWER_STATUS` (`0xb0080`) until bit 4 is set and then bit 5
clear, 5000 times at most. Linux defines bit 4 as `VCODEC1_POWER_STATUS`
too; it never writes `0xb0084`.

## What Linux did on `-17`, against this

| | Windows on Mahua | Linux `-17`, `diag_cores=1 diag_core_id=2` |
|---|---|---|
| power domain | `mvs0c`, `mvs0` | `mvs0c`, `mvs0` (vcodec0) |
| clock | `mvs0` | vcodec0 (`mvs0`) |
| HFI core | mask 2 | 2 |
| result | decodes | accepted, then no frame in 30 s |
| wrapper `0xb0084` | written 0 | never written |
| core power status and resets checked | core 1 (bit 4) | core 0's (vcodec index 0: bit 1, core 0 bridge and NOC handshake) |

So the earlier power and core-ID questions are answered; what is left is the
per-core register handling. Upstream Iris ties a core's power domain,
clocks and register bits to one index; Mahua needs core 0's power domain and
clock with core 1's ID and register bits.

## Prior work (searched 2026-11-06)

Searched: qcom-next (`17bbb4b37bbc`), linux-next `next-20261105`, the
laptops tree (`8c9d1255de`), Qualcomm's `kernel-topics` pull requests,
Qualcomm's out-of-tree `video-driver` (`a2883c1`), and Patchwork's
linux-arm-msm and linux-media queues (patch subjects, and the review comments
of the Glymur Iris series). lore's full-text search is not reachable from
here, so a patch that names neither Mahua nor Iris in its subject could be
missed.

- **Nobody has posted Mahua video support.** The upstream Glymur Iris series
  (Vishnu Reddy, v11, 2026-09-17, in qcom-next as FROMLIST) assumes two
  cores ("Add support to select core for dual core platforms"), and its
  reviews do not mention Mahua. Qualcomm's own Mahua CRD board includes
  `glymur-crd.dtsi`, which enables Iris with Glymur's two cores, and nothing
  overrides it for Mahua (qcom-next and the laptops tree), so Mahua CRD would
  hit the same `mvs1` failure. Qualcomm's Mahua QCB board (posted 2026-10-27)
  does not enable Iris.
- **Qualcomm's downstream driver already uses the socinfo data**, on Canoe
  (SM8750, `msm_vidc_canoe.c`): `socinfo_get_part_count(PART_VIDEO)` and
  `socinfo_get_subpart_info(PART_VIDEO, …)`, where `0x1` disables `vpp0`,
  `0x2` disables `vpp1`, `0x10` the APV block (and `0x11`, `0x12`
  combinations). That is the encoding Windows' rule implies (bit 0 = core 0
  fused off). Qualcomm's downstream Glymur platform has no such handling
  and no Mahua entry.
- **Upstream socinfo** reads only the subset-parts count and offset
  (debugfs); there is no part or sub-part API and no posted patch adding
  one (Patchwork, linux-arm-msm).

So a Mahua patch starts from Vishnu Reddy's Glymur series and from
Qualcomm's downstream socinfo sub-part encoding, rather than inventing its
own.

## Next step (a test kernel, not a fix)

A Mahua Iris platform entry for the test device tree:

- one vcodec, on the `vcodec0` power domain and clocks (`mvs0`);
- `HFI_PROP_CORE_ID` = 2, and core 1's status, bridge-reset and NOC
  handshake bits (`VCODEC1_*`) for that vcodec;
- `WRAPPER_BASE + 0x84` written 0 before waiting for bit 4, as Windows does;
- the core chosen from socinfo's video part entry, as Windows chooses it,
  once Linux's socinfo reads that array (it reads only the subset-parts
  count and offset today); a fixed value for the test.

Still unknown: the pipe count for this core (`-17` accepted both 4 and 2
with mask 2), what bit 5 of the power status means, and the socinfo value
on this laptop (to read once on Linux).
