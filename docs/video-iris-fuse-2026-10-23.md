# Video: Why the Iris Firmware Refuses Every Core, October 23, 2026

Issue #9. Read-only work on HP's video firmware (`qcvss8480.mbn`, committed
under `boards/hp-omnibook-5-16-bf1xxx/firmware/qcdx8480/`), Windows'
Adreno kernel driver (`qcdxkm8480.sys`, driver store) and Qualcomm's
out-of-tree Linux video driver (`qualcomm-linux/video-driver` `9cc7751`).
Nothing was run on the laptop.

## What `-16` showed

With the one-core variant (since dropped), every H.264 session failed with
two firmware messages (`docs/runbook-results-16-2026-10-21.md`):

- `vDec_SetProperty_c2(2421): Configured core 1 is not supported, Monitor=88000800`
- `vDec_Start(2951): Configured core 0 is not supported, Monitor=88000800`

## The "Monitor" value is a fuse word

- The firmware's encoder carries the same check with a fuller message:
  "`%d X %d @ %d with %d Pipe and fuseMonitorVal %x is not supported`".
- Qualcomm's own driver reads a register of that name,
  `WRAPPER_EFUSE_MONITOR` (wrapper base + `0x08`), on Iris 4, where bits
  29, 28 and 27 mark the VPP0, VPP1 and APV blocks as fused off and the
  driver skips their power domains.
- In the firmware, both log calls pass the session's core field (offset
  `0x150` of the session context) and a word from a global at `0x16abf0`:
  the fuse word the firmware read at boot.

`0x88000800` has bits 31, 27 and 11 set. The Iris 3.6 bit layout is not in
any source we have, so which block each bit fuses off is unknown. It fits
the `-15` result, where the second video core's power domain
(`video_cc_mvs1_gdsc`) never came on: on this Mahua die one of the two
cores is most likely fused off.

## What Linux sends, and what Windows sends

- Upstream Iris (`iris_vpu36_check_core_load()`) picks a core per session
  and sends `HFI_PROP_CORE_ID` (`0x030001a9`) as `IRIS_VCODEC0` = 1 or
  `IRIS_VCODEC1` = 2. Qualcomm's driver does the same
  (`MSM_VIDC_VCODEC0`/`1`). Neither reads the fuse word on Iris 3.6, and
  neither knows Mahua.
- Windows' host driver logs "`HFI: type, 1Lshift core_id`", so it also
  sends a one-bit mask (1 for core 0, 2 for core 1). Its load balancer
  ("`VedGetVideoEngineIdWithMinimalWorkload`") weighs both cores.
- Windows decodes in hardware on this laptop: DirectX lists H.264, VP9 and
  AV1 decode modes for the X2-85 (`dxdiag`, driver 32.0.146.0).
- The firmware has two property paths, "`Prop: HFI_PROP_CORE_ID`" and
  "`DX: HFI_PROP_CORE_ID`". Windows uses the DX one (it sends
  `HFI_PROP_DX_ARCH_VERSION`); Linux uses the other ("`_c2`" functions).

So the encoding matches Windows. Linux asked for mask 1 and was refused;
the `Start` message then reports the session's core as 0, the value left
when the property was refused.

## Not established

The comparison itself sits in Qualcomm's wide (FLIX) Xtensa bundles, which
generic Xtensa binutils (`binutils-xtensa-lx106`) cannot decode without
Qualcomm's core configuration. The exact rule (which mask this fuse word
allows) is therefore not read from the code.

Two explanations fit, and the code does not separate them:

- **The wrong core.** If the fused-off core is core 0, mask 1 is refused
  and mask 2 would pass. But `-15` saw core 1's power domain fail, which
  points the other way.
- **Too many pipes for the core.** Linux sends `HFI_PROP_PIPE` = 4, the
  Glymur value, just before the core. The encoder's version of the check
  names the pipe count and the fuse word together. If Mahua's core has
  fewer pipes, the firmware would refuse the core for the pipe count.

## Next boot (a test-tree experiment, not a fix)

1. Log `WRAPPER_EFUSE_MONITOR` once at Iris probe, after the controller
   powers on (a read of a powered wrapper register).
2. Decode with `HFI_PROP_PIPE` = 2 and core mask 1, then with 4 pipes and
   core mask 2, and log what the firmware answers to each.

Built for `-17` as `patches/kernel/glymur-bringup/0003` (default-off
`qcom_iris.diag_*` parameters) with Iris on again in the test device tree;
`sudo bash check-video.sh --diag` runs seven trials (pipes 4, 2, 1; core
mask driver's choice, 2, or not sent), reloading the module for each.

Whichever is accepted gives Mahua its own Iris platform data (pipes, the
core that exists and its power domain), which is how upstream would take
it. The daily device tree keeps Iris off.
