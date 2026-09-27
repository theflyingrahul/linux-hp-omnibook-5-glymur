# Device Tree: First Boots, September 28, 2026

Three boots today, after `4781096` (the reviewed DT, kernel
`7.3.0-rc2-glymur-3`): a sanity check on the old ACPI-only kernel, the full
DT (blank screen), and the minimal DT (current, working). This is the first
real evidence from booting the reviewed DT, not just the compile-time checks
in `docs/device-tree-review-2026-09-28.md`.

## Minimal DT: working baseline

Boot ID `aa9505e8` (current). `model = "HP OmniBook 5 Laptop 16-bf1xxx
(minimal)"`. Matches the review's predictions:

- CPUs, NVMe, ext4 root, TLMM/pinctrl, interconnects, RPMh — all as
  expected from `glymur.dtsi`'s default-enabled nodes.
- Input over native DT I²C (`hid-over-i2c`, not the ACPI shim modules from
  the earlier ACPI-only boots): keyboard, touchpad, touchscreen all
  enumerate.
- Thermal zones are now DT-native (`cpu-0-0-0-thermal`, `aoss-0-thermal`,
  etc.), not the four ACPI `acpitz` zones from the ACPI-only boot.
- `cpuidle` has DT-native states (`WFI`, `cpu-sleep-0`), replacing the
  ACPI `LPI-0`/`LPI-1` names from the ACPI-only boot; same mechanism,
  different naming.
- Wi-Fi (`wlo1`) came up.
- Display is the firmware framebuffer only (`&dispcc` disabled, as
  designed) — no GPU, no native display driver.

## Full DT: blank screen, root cause found

Boot ID `128f9daa` (19:47 UTC), `model = "HP OmniBook 5 Laptop
16-bf1xxx"` (no "(minimal)"). The boot report
(`/var/log/glymur/boot-20260927T194741-128f9daa.txt`, private) shows the
system fully reached userspace — network, input, thermal, cpuidle all
came up exactly as on the minimal DT — but the screen stayed dark. The
owner confirmed the keyboard worked; this matches: input has nothing to
do with display.

**This was not the GPU/display-component issue the 09-28 review
predicted (finding #4).** That fix held: `&gpu`/`&gmu` are disabled in
this DTS, and the kernel log shows `msm_dpu ae01000.display-controller:
no GPU device was found` as an expected, benign message, not a failure.
The DPU and DP controller bound fine, and a `card1-eDP-1` connector was
registered.

**The actual failure is eDP link training:**

```
[drm:msm_dp_ctrl_link_train_1_2 [msm]] *ERROR* link training #1 on phy 0 failed. ret=-11
[drm:msm_dp_ctrl_link_train_1_2 [msm]] *ERROR* max v_level reached
[drm:msm_dp_ctrl_setup_main_link [msm]] *ERROR* link training on sink failed. ret=-11
[drm:msm_dp_display_atomic_pre_enable [msm]] *ERROR* DP display prepare failed, rc=-104
[drm:msm_dp_display_prepare_link [msm]] *ERROR* Failed link training (rc=-104)
```

`ret=-11` (`EAGAIN`) after "max v_level reached" means the controller
swept through its available voltage-swing/pre-emphasis levels and the
panel never acknowledged clock recovery — the AUX channel itself came up
enough to attempt training (this isn't a total AUX failure), but the
main link never locked.

**One concrete lead, not yet confirmed as the cause:** immediately before
this, the PHY probed with both supplies on dummy regulators:

```
qcom-edp-phy faac00.phy: supply vdda-phy not found, using dummy regulator
qcom-edp-phy faac00.phy: supply vdda-pll not found, using dummy regulator
```

`dts/qcom/mahua-hp-omnibook-5-bf1xxx.dts` doesn't wire `vdda-phy-supply`/
`vdda-pll-supply` on `&mdss_dp3_phy` at all, so this was expected, not a
regression — but it's the most obvious place to check next, since the DP
PHY's own analog supplies affect signal integrity directly. Whether these
rails are actually fixed-always-on (making the dummy regulator harmless,
as `docs/device-tree-review-2026-09-28.md` already treats `vreg_edp`/PEP
GPIO 70/18/119 as boot-on) or genuinely need a `regulator-fixed`/RPMh
node is not yet evidenced either way.

Other candidates, not yet investigated: lane count/link-rate mismatch
against what the Samsung ATNA OLED panel (EDID SDC 0x4214) actually
supports, AUX/HPD timing relative to `vreg_edp`'s power-up (the
`atna33xc20` panel driver's own sequencing may need a delay this DTS
doesn't provide via `power-supply`/`enable-gpios` framing), or a PHY
lane-mapping/orientation mismatch.

## Remoteproc / PMIC GLink: attached cleanly

Both remoteprocs came up on the full DT boot with HP's signed firmware:

```
remoteproc remoteproc0: attaching to soccp
remoteproc remoteproc0: remote processor soccp is now attached
remoteproc remoteproc1: Booting fw image .../qcadsp8480.mbn, size 21432280
remoteproc remoteproc1: remote processor adsp is now up
remoteproc remoteproc2: Booting fw image .../qccdsp8480.mbn, size 3252504
remoteproc remoteproc2: remote processor cdsp is now up
```

No PMIC GLink/battery data captured yet in this boot's report; that
still needs its own check (`docs/device-tree-review-2026-09-28.md`
already notes battery/AC/UCSI/RTC run over the SoCCP here, not the ADSP).

## Next

- Decide whether `vdda-phy-supply`/`vdda-pll-supply` need real
  `regulator-fixed` nodes on `&mdss_dp3_phy`, by checking the Glymur/Mahua
  CRD reference (`glymur-crd.dtsi`) and the Zenbook A16 for how they wire
  these supplies.
- Compare the panel's negotiated/attempted link rate and lane count
  against the CRD reference and the ATNA panel driver's defaults.
- Check PMIC GLink / battery data on the next full-DT boot's report.
- Keep booting the minimal DT as the working baseline until the eDP link
  training issue is root-caused; it is not the same failure mode the
  09-28 review guarded against, so that review's fixes should stay as-is.
