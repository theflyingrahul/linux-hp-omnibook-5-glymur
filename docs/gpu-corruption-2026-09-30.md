# GPU-Rendered Desktop Corruption, September 30, 2026

## What happened

On kernel `7.3.0-rc2-glymur-6` with Mesa `26.2.3-2` switched on
system-wide (`mesa-glymur-run --system on`), "device tree (GPU and USB-A
test)" came up with GNOME composited on the GPU. GNOME Settings, About:

- Graphics: **Adreno X2-85**
- Kernel: 7.3.0-rc2-glymur-6

So the compositor is on the new Mesa. But the screen is corrupted, from
the owner's photos:

- speckled, dashed noise bands across the top and through the middle;
- a dotted overlay over otherwise readable windows (the About dialog's
  text is legible);
- later, large black rectangles with block-shaped garbage and only parts
  of the wallpaper and windows drawn.

The eDP link and the display pipeline are not the problem: the same panel
was clean with software rendering on `-5`. The corruption comes with the
GPU rendering the desktop.

("Processor: (null) × 12" is a separate, cosmetic gap: the CPU name comes
from the DT or SMBIOS processor strings and is not set here.)

## Ruled out so far (sources, not tests)

- **Kernel UBWC table.** `drivers/soc/qcom/ubwc_config.c` has
  `qcom,mahua` → `glymur_data` (UBWC 5.0, swizzle levels 2 and 3 off,
  highest bank bit 16, or SMEM's value). The GPU driver and the display
  controller (`msm_mdss.c`) both read this one table, so the two halves
  of the kernel agree with each other.
- **GMEM size and slice count.** The kernel has one catalog entry for
  this GPU family, `0x44070001` (21 MB GMEM, `max_slices = 4`), which
  both dies match. qcom-next's `mahua.dtsi` deletes the slice-3 GPU
  thermal zones, so Mahua runs 3 slices. That is not a mismatch:
    - msm reads the active-slice mask from hardware and writes the count
      into the chip ID (`a8xx_gpu_get_slice_info`), which is how Mesa
      sees `0x44070031`;
    - Qualcomm's own driver does the same. KGSL (`qualcomm-linux/kgsl`,
      `adreno-gpulist.h`) has one entry for `0x44070001`, "Adreno X2-85",
      with `gmem_size = 21 MB` and the note "bits[7:4] patched at runtime
      with active slice count". KGSL uses 21 MB for 3-slice parts too.
      **Wrong, corrected below:** KGSL keeps 21 MB in its table but reports
      GMEM for the active slices only (15.75 MB here).
- **The reference setup works.** Rob Clark reports GNOME Shell working on
  a Glymur laptop (chip `0x44070041`, 4 slices) with Mesa 26.1.6.
    - Mesa describes our 3-slice part differently: 6 CCUs and 96×32 tile
      alignment, against 8 CCUs and 64×64 for `0x44070041`.
    - Qualcomm added another 3-slice X2-85 ID to Mesa main on 2026-09-25,
      noting only that "basic functionality" was verified.
    - So the 3-slice gen8 configuration is the least-tested path.
- **Mesa main after 26.2.3.** It has gen8 fixes: a barrier for indirect
  buffers, query barriers, LRZ fast-clear size, multisample-resolve blits
  and a register layout. None names this symptom. The 26.2 branch has no
  commits after 26.2.3.

## The test that decides it

`scripts/linux/glymur-ssd/gpu-corruption-test.sh` runs from a text
console, with the desktop logged in and switched away from. It uses
`kmscube`, which renders on the GPU and scans out through KMS, the same
path as the compositor. The cases:

- llvmpipe, as the reference;
- the GPU default;
- a linear scanout buffer;
- `FD_MESA_DEBUG=noubwc`, `nolrz` and `sysmem`, each alone;
- all three together.

After each case the owner answers whether the screen looked clean, and
the script records the kernel's GPU messages with the answers. What each
result points to:

| Clean only with | Points to |
|---|---|
| linear scanout (and `noubwc`) | Compressed scanout: GPU encode and display decode disagree (kernel DPU or Mesa UBWC 5 layout) |
| `noubwc`, not linear scanout | UBWC in textures or intermediate buffers inside Mesa |
| `nolrz` | Mesa's gen8 LRZ on 3-slice parts |
| `sysmem` | GMEM tiling (bin layout) for the 3-slice configuration |
| none of them | Something outside these paths: kernel command stream or GPU state, or power (`vdd`/`vddcx` are dummy regulators) |

## Until then

The desktop can go back to software rendering: on a text console, run
`sudo mesa-glymur-run --system off` and reboot. Per-program GPU use
through `mesa-glymur-run` stays available.

## First run: isolated to GMEM tiling (`sysmem`)

Ran on kernel `-6`, `captures/2026-09-30-gpu-corruption/gpu-corruption-111000.txt`.
Cases 2–7 (all real GPU rendering; each ran the full 8 s, `exit 124` from
`timeout`) split cleanly:

| Case | Setting | Clean? |
|---|---|---|
| 2 | GPU default | No |
| 3 | linear scanout buffer | No |
| 4 | `noubwc` | No |
| 5 | `nolrz` | No |
| 6 | `sysmem` | **Yes** |
| 7 | `noubwc,nolrz,sysmem` | **Yes** |

Only `sysmem` — disabling GMEM tiling (bin layout) — cleaned it up, alone
and in combination; linear scanout, `noubwc` and `nolrz` alone all stayed
corrupted. Per the table above, this points specifically at **GMEM tiling
for the 3-slice configuration**, not UBWC compression, LRZ, or compressed
scanout — narrowing "Mesa's barely tested 3-slice gen8 path" to one part
of it. `renderer:` printed `"Adreno (TM) X2-85"` in every case, including
case 1, confirming the compositor and every kmscube instance load the new
Mesa consistently.

**Case 1 (the llvmpipe reference) didn't produce a usable baseline**:
`exit 139` (SIGSEGV) and answer `b` (blank/no cube). `LIBGL_ALWAYS_
SOFTWARE=1` doesn't force software rendering through kmscube's GBM/KMS
path the way it does for GLX — the process crashed before showing
anything, rather than falling back to llvmpipe. That's a gap in the test
script, not a new finding about the corruption; it just means there's no
confirmed-clean reference frame from this run to compare against, only
the already-established fact that the same panel was clean under software
rendering on `-5`.

**Next:** try `FD_MESA_DEBUG=sysmem` as the permanent setting for
`mesa-glymur-run --system on` (or hardcode it into the freedreno 3-slice
gen8 path) and confirm the desktop itself, not just kmscube, is clean.
Worth reporting upstream: Mesa's 3-slice gen8 GMEM/bin-layout tiling
produces visible corruption on real hardware, with `sysmem` as a working
avoidance.

## Root cause: msm reports GMEM for four slices, this GPU runs three

Found from the first run's result (GMEM rendering is the only broken path)
by comparing how KGSL and msm report GMEM to userspace:

- **KGSL** keeps the catalog size (21 MB) for its hardware setup, but
  `gen8_get_gmem_size()` returns
  `gmem_size / GEN8_1_0_NUM_PHYSICAL_SLICES * active slices` for this GPU
  family: 21 MB / 4 × 3 = **15.75 MB** (16515072 bytes) on a 3-slice part.
  GMEM is split evenly between the slices, so the fused-off slice's share
  does not exist.
- **msm** (qcom-next `e428097a36d`, msm-next `d33622598496`, mainline
  v7.3-rc5+37) answers `MSM_PARAM_GMEM_SIZE` with the catalog value,
  **21 MB**, whatever the slice mask. It reads the slice mask
  (`a8xx_gpu_get_slice_info()`) only to patch the chip ID.
- **Mesa** sizes its bins from that value and, on gen8, places the CCU
  depth and color caches at the top of GMEM
  (`fd6_calc_gmem_cache_offsets()`). With 21 MB, both land past the end of
  the 15.75 MB that exists. That explains all six cases: only `sysmem`
  avoids GMEM. The kernel logged no GPU fault or hang: GMEM accesses do
  not go through the SMMU, so out-of-range ones corrupt silently instead
  of faulting (inferred, not measured).
- One detail does not follow on its own: Mesa computes the sysmem-mode
  cache offsets from the top of the reported GMEM too, so in `sysmem`
  mode the caches also sit past 15.75 MB. That is consistent if
  out-of-range GMEM addresses wrap or alias: with `sysmem`, nothing else
  is in GMEM for the caches to overwrite; with GMEM rendering, the tiles
  are. The `FD_MESA_GMEM` cases below test the explanation directly.
- Rob Clark's working Glymur has all four slices (`0x44070041`), where
  21 MB is correct. That is why nobody upstream has hit this.

**Kernel fix, in `-7`:** `upstream/qcom-next/0002` ("drm/msm/a8xx: report
the GMEM size of the active slices") stores
`info->gmem / max_slices × active slices` when it reads the slice mask and
reports that. The GMEM protection register and the UCHE setup still cover
the full range, as in KGSL. This fixes OpenGL (freedreno) and Vulkan
(turnip) together, with no Mesa change, and keeps GMEM rendering.
Forcing `sysmem` in Mesa, the other option, would give it up entirely.

**Test without the new kernel:** Mesa's `FD_MESA_GMEM=<bytes>` overrides
the size it got from the kernel. `gpu-corruption-test.sh` now runs:
`sysmem` (reference), the default, `FD_MESA_GMEM=16515072` and half of
that. On `-6`, cases 1, 3 and 4 should be clean and case 2 corrupted; on
`-7`, all four clean. (Turnip's equivalent is `TU_GMEM`.)

**Case 1 of the first run, corrected:** kmscube printed
`renderer: "Adreno (TM) X2-85"` in case 1 too, so `LIBGL_ALWAYS_SOFTWARE=1`
did not select llvmpipe on the GBM path at all; the crash (`exit 139`)
happened on the GPU driver. The new script drops that case and uses
`sysmem` as the clean reference.

## Second run: `FD_MESA_GMEM` confirms the root cause exactly as predicted

Ran the updated `gpu-corruption-test.sh` on kernel `-6` (not yet `-7`;
this tests the explanation without a new kernel),
`captures/2026-09-30-gpu-corruption/gpu-corruption-115735.txt`:

| Case | Setting | Predicted | Actual |
|---|---|---|---|
| 1 | `sysmem` (reference) | clean | **clean** |
| 2 | GPU default (kernel-reported 21 MB) | corrupted | **corrupted** |
| 3 | `FD_MESA_GMEM=16515072` (15.75 MB, the real 3-slice size) | clean | **clean** |
| 4 | `FD_MESA_GMEM=8257536` (half of that) | clean | **clean** |

Exactly the predicted split. Case 2 is the only corrupted one — Mesa
using the kernel's (wrong) 21 MB value. Telling Mesa the correct 15.75 MB,
or even less than that, renders clean: an *under*-estimate of GMEM is
safe (Mesa just bins more conservatively than it needs to), while the
kernel's *over*-estimate is what let tiles and caches land past real
GMEM. This is about as clean a confirmation as a software-only test can
give without booting `-7` itself: the root cause is the GMEM size number
the kernel hands to userspace, not anything else in Mesa's gen8 path.

**Still open:** an actual boot of kernel `-7` with `upstream/qcom-next/
0002` applied, to confirm the in-kernel fix reports the corrected value
by itself (no `FD_MESA_GMEM` override needed) and that GNOME's own
compositor — not just kmscube — renders clean with `mesa-glymur-run
--system on`.
