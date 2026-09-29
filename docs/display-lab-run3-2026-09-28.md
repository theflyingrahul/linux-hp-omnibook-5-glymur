# Display Lab, Third Run: September 28, 2026

Third run of the lab from `~/glymur-lab-kit` on the display-lab device tree
(kernel `7.3.0-rc2-glymur-3`), with the run-2 step-by-step logging
(`docs/display-lab-run2-2026-09-28.md`). Session directory on the machine:
`/var/log/glymur/lab-20260928T124446/`. **This run's raw logs were not yet
copied into `.work/` before the conversation that analyzed them was
compacted; that copy, and the exact register values quoted below, still need
to be re-pulled from the live system.** Everything else in this file reflects
what was read and traced live during the run.

## Result: phase 5 reached and completed the v0-baseline attempt

Unlike run 2 (hung right after the desktop stopped), this run got all the way
through `step 5.5` and the `v0-baseline` attempt logged a verdict of
`failed`, matching the earlier boot-time full-DT result rather than hanging.
That on its own rules the run-2 hang's cause down to something specific to
one of steps 5.1-5.4 (desktop stop, `chvt`, DRM debug enable, or the overlay
apply) rather than anything in phase 5 as a whole — it is not reproducing
every time.

## The finding: PHY power-on itself fails, before link training's retries

`50-display-v0-baseline.txt` contains:

```
phy phy-faac00.phy.2: phy poweron failed --> -110
```

This is a distinct, earlier failure point than the previously-documented
"max v_level reached" / "Failed link training (rc=-104)" symptom
(`docs/device-tree-first-boot-2026-09-28.md`). `-110` is `-ETIMEDOUT` from a
`readl_poll_timeout()` inside `phy_qcom_edp_phy_power_on()` in the pinned
driver (`drivers/phy/qualcomm/phy-qcom-edp.c`, v8 PHY generation:
`qcom_edp_phy_power_on_v8()` / `qcom_edp_com_configure_pll_v8()` /
`qcom_edp_phy_com_resetsm_cntrl_v8()`). The link-training voltage-swing
failure that msm logs afterwards is downstream of this: if the PHY's PLL
never locks, no swing level will ever complete clock recovery, so the
28-DT link-training analysis was chasing a symptom of this, not the cause.

## Working hypothesis: PLL coefficients

The driver programs the eDP PHY's PLL for each supported link rate from a
hardcoded per-rate register table (`phy-qcom-qmp-qserdes-dp-com-v8.h`). The
firmware's own working PLL configuration was captured live by
`glymur_lab.ko` (logged as `glymur-lab phy firmware pll +XXX: ...` lines at
module probe, since the panel was already lit and clocked by firmware at
that point).

Comparing the firmware's live register dump against the driver's hardcoded
values for the 2.7 Gb/s (HBR) rate — the rate the firmware actually uses,
per `docs/display-lab-run1-2026-09-28.md` — found **10 of the PLL registers
differ**:

- `DEC_START_MODE0`
- `DIV_FRAC_START2_MODE0`
- `DIV_FRAC_START3_MODE0`
- `LOCK_CMP1_MODE0`
- `CORECLK_DIV_MODE0`
- `VCO_TUNE1_MODE0`
- `VCO_TUNE2_MODE0`
- `BIN_VCOCAL_CMP_CODE1_MODE0`
- `BIN_VCOCAL_CMP_CODE2_MODE0`
- `SSC_STEP_SIZE1_MODE0`

(`DIV_FRAC_START1_MODE0`, `LOCK_CMP2_MODE0` and `SSC_STEP_SIZE2_MODE0` were
checked in the same pass and matched.) The exact driver-vs-firmware byte
values are not yet re-recorded in this file; they were computed inline
against the live `pll firmware +XXX:` log lines and the driver's header
constants and were not saved to a file at the time. Re-deriving them needs
either that boot's journal (if still retained: `journalctl -k -b -N`
counting back to boot ID for `lab-20260928T124446`) or a fresh lab run —
the instrumented driver's probe-time dump captures the same firmware values
every time, since it reads them before Linux ever reprograms the PHY.

This does not prove the PLL mismatch is *the* cause of `-110` (the register
table also encodes VCO tuning search ranges and calibration comparators that
the SoC's internal calibration state machine is supposed to walk through
regardless of the seed values), but it is the only concrete difference found
between what firmware runs successfully and what the driver programs for the
same rate, and it sits directly upstream of the failing wait.

## What was built to test it (not yet run)

`scripts/linux/glymur-lab/make-phy-edp-lab.py` gained a `lab_fw_pll` module
parameter: when set, right after `qcom_edp_configure_pll()` runs, it
overwrites those same rate-dependent registers with the firmware's captured
values and logs each overwrite. It also gained failure-path diagnostics at
all three `readl_poll_timeout()` sites in the power-on sequence
(`com_power_on`, `com_resetsm_cntrl`, the final `DP_PHY_STATUS` poll), each
naming which wait failed and dumping full PHY register state.

`scripts/linux/glymur-lab/glymur-lab-run.sh` gained four new phase-5
variants that flip only this parameter (plus firmware TX values, plus SSC)
and retrain by blanking/unblanking `fb0` rather than unbinding `msm-mdss`
(unbinding is now suspected, not confirmed, as a cause of the run-2 hang, so
it is gated behind `GLYMUR_LAB_REBIND=1` for the old V1-V9 variants):

- **W1**: firmware PLL coefficients only.
- **W2**: firmware PLL plus firmware TX drive/emphasis/LDO/polarity/offsets/band.
- **W3**: firmware PLL, SSC forced off.
- **W4**: firmware PLL, SSC forced on.

Both scripts were validated locally (the generator runs cleanly against the
pinned kernel source with every edit anchor matching exactly once; the run
script passes `bash -n`) but **nothing was built**, per the standing
instruction not to build on this machine. `phy-qcom-edp-lab.ko` and
`glymur_lab.ko` need a WSL rebuild and the kit needs re-staging
(`stage-kit.sh`) before a fourth lab run can test W1-W4.

## Next

- Copy `/var/log/glymur/lab-20260928T124446/` into `.work/lab-run3-2026-09-28/`
  (pending Bash access in the diagnosing session).
- Rebuild the lab kit in WSL with the `lab_fw_pll`/W1-W4 changes.
- Re-stage and run a fourth lab session; W1 alone isolates whether the PLL
  substitution fixes `-110` by itself.
- Independently, a boot-time test that limits the full DT to the firmware's
  2 lanes at 2.7 Gb/s is staged (`docs/edp-2lane-test-2026-09-29.md`). If
  that test also goes dark with the same `-110` PHY failure, it would
  confirm the cause is below the DT's lane/rate declaration — in the PHY
  driver's own PLL programming — and not something a DTS-only change can
  fix.
