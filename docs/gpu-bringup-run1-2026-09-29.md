# GPU and CPU Frequency Scaling: First Live Confirmation, September 29, 2026

Booted "Ubuntu on SSD: device tree (GPU test)" on kernel `7.3.0-rc2-glymur-5`
(`docs/gpu-bringup-2026-09-29.md`). **Both the Adreno GPU and SCMI cpufreq
work.** Four `sudo bash check-gpu-test.sh [...]` runs from this boot are
preserved privately in `.work/gpu-bringup-run1-2026-09-29/`, alongside the
full `journalctl -k -b`.

## GPU: bound, GMU loaded, devfreq scaling live

Kernel log, unprompted at boot:

```
adreno 3d00000.gpu: supply vdd not found, using dummy regulator
adreno 3d00000.gpu: supply vddcx not found, using dummy regulator
msm_dpu ae01000.display-controller: bound 3d00000.gpu (ops a3xx_ops [msm])
msm_dpu ae01000.display-controller: [drm:adreno_request_fw [msm]] loaded qcom/gen80100_sqe.fw from new location
msm_dpu ae01000.display-controller: [drm:adreno_request_fw [msm]] loaded qcom/gen80100_gmu.bin from new location
[drm] Loaded GMU firmware v5.2.38
msm_dpu ae01000.display-controller: Zap shader not enabled - using SECVID_TRUST_CNTL instead
```

Exactly the sequence the bring-up doc predicted from the upstream Glymur
laptops: no zap shader needed, `SECVID_TRUST_CNTL` used instead, both
firmware files load from linux-firmware's paths. The dummy-regulator lines
are expected (no PEP-evidenced rail for `vdd`/`vddcx` is declared yet;
firmware keeps them powered, same pattern as the eDP PHY before it).

`/sys/class/devfreq/3d00000.gpu` is live: `governor=simple_ondemand`,
`cur=310000000` (idle, the lowest OPP), `min=310000000 max=1350000000`, with
the full 9-step OPP table available (310/410/572/760/820/915/1070/1185/1350
MHz) — the test DT's 1.35 GHz cap, as designed. This is a real devfreq
governor actively managing the GPU clock, not just a bound-but-idle device.

Display kept working on the same boot: `card1-eDP-1`
`status=connected enabled=enabled`, `1920x1200` — the GPU and display bind
together cleanly, as expected (msm treats them as one component).

Not yet tested: an actual render/compute workload (`glxinfo`/`vulkaninfo`
aren't installed, so `check-gpu-test.sh`'s GL/Vulkan section is empty on
every run so far). Devfreq activity is strong evidence the GPU itself is
alive, but nothing has issued it a real command stream yet.

## CPU frequency scaling: works, no hang

This is the one qcom-next perf-protocol path that hung the laptop hard in
`docs/display-lab-run1-2026-09-28.md` (`modprobe scmi-cpufreq` →
`arm-scmi` protocol 0x13 timeout → silent hang, no oops). The GPU test DT
adds `arm,no-completion-irq` to `/firmware/scmi` (the upstream SCMI polling
fix). This run:

```
$ modprobe scmi-cpufreq
arm-scmi arm-scmi.0.auto: Failed to query supported version for protocol 0x13.
arm-scmi arm-scmi.0.auto: Trying version 0x40000. Backward compatibility is NOT assured.
arm-scmi arm-scmi.0.auto: Failed to get FC for protocol 13 [...] - ret:-22. Using regular messaging.
```

Still logs warnings (the fast-channel negotiation fails, same as before),
but this time it falls back to **regular (polling) messaging instead of
hanging**, and cpufreq comes up for real:

```
policy0: cpus=0 1 2 3 4 5   cur=902400   min=355200 max=3417600 driver=scmi
policy6: cpus=6 7 8 9 10 11 cur=4032000  min=355200 max=4032000 driver=scmi
```

Two policies matching the 6+6 CPU cluster split, real frequency ranges
(policy0 up to 3.4 GHz, policy6 — the performance cluster — up to 4.03 GHz),
and a live `cur` value. This is the first working CPU frequency scaling on
this laptop under Linux, on any boot path.

## What this changes

- GPU bring-up on Mahua now has a live confirmation, not just upstream
  precedent from other Glymur boards — the first for this die.
- `scmi-cpufreq`'s hang was specifically the missing completion-IRQ
  handling that upstream already fixed; it is not a fundamental
  incompatibility with this firmware. The fix is confined to the GPU test
  DT for now (`arm,no-completion-irq` on `/firmware/scmi`); it has no
  display/GPU dependency and could be carried by the full/minimal DTs too
  once the GPU result is trusted more broadly.
- The `-3`/`-4`-era status rows for GPU and CPU frequency scaling
  ("Disabled"/"No") are stale for the GPU test DT specifically; the full
  and minimal DTs still keep the GPU block off by design and are
  unaffected.

## "Software Rendering" explained: a Mesa version gap, not a kernel problem

GNOME Settings' About page (and any GL/Vulkan client) reports software
rendering. Traced to the journal (`org.gnome.Settings`, `gnome-shell`,
`xdg-terminal-exec`, all sessions on this boot):

```
MESA: error: fd_pipe_new2:49: unsupported GPU id 0x0 / chip id 0x16544070031
TU: error: .../tu_device.cc:1553: device (chip_id = 16544070031, gpu_id = 0) is unsupported (VK_ERROR_INCOMPATIBLE_DRIVER)
libEGL warning: MESA-LOADER: failed to retrieve device information
Xwayland glamor: GBM Wayland interfaces not available
Failed to initialize glamor, falling back to sw
```

`msm_dri.so` (freedreno's OpenGL driver) and `TU` (turnip, its Vulkan
driver) are both present (installed Mesa `26.0.8-1ubuntu0.3`), but neither
recognizes this chip ID — the Adreno X2-85 (`qcom,adreno-44070001`) is new
enough that Ubuntu 26.04's shipped Mesa predates its entry in freedreno's
hardware table. This is entirely a **userspace** gap: everything this
session confirmed at the kernel level (bind, GMU firmware, devfreq
scaling) is real hardware bring-up, unaffected by this. GNOME falls back
to `llvmpipe`/`swrast` (CPU rendering) because libEGL can't get a working
DRI2/GBM device for the GPU, and Xwayland's glamor acceleration fails the
same way. A newer Mesa (once one ships with X2-85/gen8 support, likely
needed upstream first) would be required to see real acceleration; nothing
in this repository can fix a missing Mesa hardware-table entry.

## Not yet done

- **USB-C charging**: still open. Two live, tightly-polled (0.5 s
  resolution, ~60 s each) attempts at a fresh unplug/replug on this boot
  both stayed completely flat — no partner, no `ONLINE=1`, not even a
  brief blip — in contrast to the owner's report that the charging LED lit
  once during an earlier replug on the hinge-side port. Whether the LED
  lit on these two live-polled attempts was not confirmed before wrapping
  up. See `docs/usb-c-charging-2026-09-29.md` for the full timeline; this
  needs a session where the LED state and the sysfs poll are watched
  together in real time, ideally also compared against the ACPI/Windows
  path.
- A real GL/Vulkan workload once Mesa ships X2-85 support, to confirm the
  GPU renders and not just clocks (devfreq activity is strong but indirect
  evidence).
- Whether GPU + cpufreq survive being carried into the full DT alongside
  the working display, rather than only the GPU-only test DT.
