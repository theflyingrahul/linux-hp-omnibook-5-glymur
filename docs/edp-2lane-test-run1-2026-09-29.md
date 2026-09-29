# eDP 2-Lane Test, First Boot: September 29, 2026

Booted "Ubuntu on SSD: eDP test, 2 lanes (device tree)"
(`docs/edp-2lane-test-2026-09-29.md`), kernel `7.3.0-rc2-glymur-3`, model
"HP OmniBook 5 Laptop 16-bf1xxx (eDP 2-lane test)". **Result: dark, same as
the full DT.** `journalctl -k -b -1` (pasted by the owner from the next
boot) has the full sequence. Not yet copied into `.work/`.

## The lane/rate mismatch theory is now ruled out

The panel's own DPCD, read fresh on this boot:

```
max_lanes=2 max_link_rate=270000
SUPPORTED_LINK_RATES[0]: 162000
SUPPORTED_LINK_RATES[1]: 270000
version: 1.4
```

The panel itself cannot do more than 2 lanes at 2.7 Gb/s (HBR) — the same
ceiling the firmware runs at. msm reads this correctly and chooses
`link_rate=270000, num_lanes=2`, i.e. it is not being held back by the DT's
`data-lanes`/`link-frequencies` any more than the panel already holds it
back. **This test put the DT limit and the panel's own limit at the same
value, and it still failed.** The earlier theory — that a 4-lane DT
declaration was asking the panel to train lanes that were never wired — is
no longer a viable explanation for the dark screen: 2 lanes was always going
to be the ceiling here, DT or no DT.

## The real failure, confirmed a second time

Immediately after `msm_dp_ctrl_on_link` logs `rate=270000, num_lanes=2,
pixel_rate=149761` — before any DPCD training-pattern write —:

```
phy phy-faac00.phy.2: phy poweron failed --> -110
```

This is the identical failure lab run 3 found
(`docs/display-lab-run3-2026-09-28.md`): `-ETIMEDOUT` from a
`readl_poll_timeout()` inside the PHY driver's own v8 power-on sequence,
happening before link training's voltage-swing loop even starts. msm does
not treat this as fatal at this layer (`msm_dp_ctrl_on_link` presses on into
`msm_dp_ctrl_setup_main_link` regardless), so the log still shows a full,
familiar link-training attempt: pattern set, v_level climbs 0 -> 1 -> 2 -> 3
across a fixed number of AUX round-trips (the DPCD read after each write
never reports anything better than the previous level, so `msm_dp_link_adjust_levels`
just keeps asking for the max), "max v_level reached" at v_level=3,
`ret=-11`, "link training #1 on phy 0 failed". msm then downshifts to
`rate=162000` (RBR) and repeats the exact same v_level climb to the same
`ret=-11`, then gives up: `Failed link training (rc=-104)`, `DP display
prepare failed, rc=-104`. `msmdrmfb` still registers as a framebuffer device
(hence a black `fb0`, not a kernel panic), which is why the screen is dark
rather than showing any error.

The PHY driver reports `supply vdda-phy not found, using dummy regulator`
and the same for `vdda-pll`, as on every DT boot; this is expected (no rail
is declared, per the safety rule, and the firmware's own vote keeps the rail
powered regardless — see the correction in `docs/lab-boot-state-2026-09-28.md`)
and is very unlikely to be the cause, since the firmware runs the same
shared rails at the same voltage without a declared regulator.

## Conclusion

Two independent boots, two different code paths (the stock in-tree PHY
driver here; the instrumented `phy-qcom-edp-lab.ko` in lab run 3), same
`-110` at PHY power-on, same downstream link-training symptom, now with the
lane/rate question fully closed. **The cause is inside
`phy_qcom_edp_phy_power_on_v8()` / `qcom_edp_com_configure_pll_v8()` in
`drivers/phy/qualcomm/phy-qcom-edp.c`, not anything expressible in the
device tree.** The leading hypothesis remains the 10-register PLL
coefficient mismatch found in run 3 between the driver's hardcoded 2.7 Gb/s
table and the firmware's live PLL registers.

## Next

- No further DTS changes are worth testing for this failure; the full DTS
  should keep the 4-lane declaration reverted only if/when a real fix lands,
  not adjusted further on lane-count theories.
- The path forward is the lab's `lab_fw_pll` instrumentation (already
  written into `scripts/linux/glymur-lab/make-phy-edp-lab.py` and
  `glymur-lab-run.sh`'s W1-W4 variants, uncommitted, not yet built anywhere).
  It needs a WSL rebuild of `phy-qcom-edp-lab.ko`, re-staging the kit
  (`stage-kit.sh`), and a fourth lab run to test whether substituting the
  firmware's PLL register values lets the PHY power on.
- If W1 (firmware PLL coefficients alone) succeeds, the fix belongs in the
  driver's PLL table for this SoC/rate, which is an upstream-shaped
  question (Qualcomm's v8 PLL coefficients may assume a reference clock or
  VCO calibration path this hardware doesn't match), not a Glymur DTS
  change.
