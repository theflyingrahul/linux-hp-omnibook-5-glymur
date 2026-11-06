# GPU management unit and the clock controllers' sync_state, November 6, 2026

Read-only work: the `-18` boot report and kernel log
(`captures/2026-11-05-k18/`), qcom-next `17bbb4b37bbc`, the laptops tree,
linux-next `next-20261105` and Patchwork (linux-arm-msm).

## What happens

Every device-tree boot logs, about 22 s in:

    gxclkctl-kaanapali 3d64000.clock-controller: sync_state() pending due to 3d6c000.gmu
    gcc-glymur 100000.clock-controller: sync_state() pending due to 3d6c000.gmu
    gpucc-glymur 3d90000.clock-controller: sync_state() pending due to 3d6c000.gmu

The GPU's management unit (`3d6c000.gmu`) is a consumer of these clock
controllers' clocks and power domains, but no driver ever binds to it: the
Adreno driver reaches it through `of_find_device_by_node()`. Until every
consumer has probed, the providers' `sync_state` never runs, and a power
domain the firmware handed over enabled stays on for good.

## What it costs here

On `-18` (boot report, genpd section) the GCC power domains of the
multiport USB controller, which this laptop does not use, are on with no
consumer at all: `gcc_usb30_mp_gdsc`, `gcc_usb3_mp_ss0_phy_gdsc` and
`gcc_usb3_mp_ss1_phy_gdsc`. Lloyd Hazlett found the same on the ASUS
Zenbook A14 (linux-arm-msm, 2026-10-24): firmware-enabled GDSCs are
registered as stay-on and nothing can release them before `sync_state`.
`pd_ignore_unused` on our command line (from Ubuntu's generic GRUB entry)
keeps them on as well, so both have to go; `-19`'s runbook part D tests the
command line.

## Existing work

The fix is Akhil P Oommen's series "drm/msm: Attach a driver to GMU": the
GMU gets a driver and joins the DRM component master.

- v1 (RFT, 2026-05-13), carried in the laptops tree (`f698585ba9` and its
  prerequisites `9a415d0552`, `bb1efe2b44`, `6871f393b1`, `a59fc7bf26`).
- v2 (8 patches, 2026-10-30): reworked after review; devfreq is set up
  only after the GPU and GMU bind, the GPU is made quiescent before the GMU
  unbinds. Konrad Dybcio (2026-11-02): Reviewed-by on 1–2, Acked-by on 3,
  and changes asked on 4 ("otherwise we get an intermittent regression")
  and 6. Not accepted, not in linux-next; a v3 is expected.
- Earlier: Neil Armstrong's RFC (2025-10-22), which failed GPU init on
  sdm845 and was superseded.

## Plan

Not in `-19`: the series reworks how the msm driver probes the GPU, which
works on this laptop today, and its current revision has a known open
regression. Take v3 once posted (or whatever is accepted) into a test
kernel together with dropping `pd_ignore_unused` if part D of the `-19`
runbook boots cleanly, and compare the boot report's genpd section: the
three multiport USB domains should then turn off.
