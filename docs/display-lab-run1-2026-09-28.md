# Display Lab, First Run: September 28, 2026

The lab (`docs/display-lab-2026-09-28.md`) ran once from the staged SSD copy
of the kit (`~/glymur-lab-kit`) on the display-lab device tree, kernel
`7.3.0-rc2-glymur-3`. It completed phases 1 to 3 and then the laptop went
down during phase 4, so **the display experiments (phase 5) never ran**.
Private logs: `.work/lab-run-2026-09-28/` (results directory
`lab-20260928T065917`, both boots' journals, boot reports).

## What the run produced

### The firmware's working eDP link (phase 2)

The firmware's picture was still on screen, so its registers show the
working configuration. Decoded (`analyze-fw-snapshot.py`, checked against
`dp_reg.h` in the pinned tree):

| Item | Firmware value | Our full DT |
|---|---|---|
| Lane count (`CONFIGURATION_CTRL` 0x00084557, bits 5:4) | **2 lanes** | `data-lanes = <0 1 2 3>` (4) |
| Lane map (`LOGICAL2PHYSICAL` 0xe4) | identity, lanes 0 and 1 | identity |
| Link rate (Mvid 0x4100, Nvid 0x7530) | **2.7 Gb/s per lane (HBR)** | up to 8.1 Gb/s offered |
| Enhanced framing, ASSR | on, on | msm decides from DPCD |
| Timing (`TOTAL_HOR_VER` 0x04e007d0, active 0x04b00780) | 2000 x 1248 total, 1920 x 1200 active, 149.76 MHz pixel clock | same panel |
| Bits per component | 8 | 8 |
| `tcsr_edp_clkref_en`, MDSS GDSC, DP3 clocks | all on | |
| GPIO 18, 70 | driven high (`ctl 0x3c3`) | as in the DTS |
| GPIO 119 | function 1 (`edp0_hot`) | as in the DTS |
| PHY TX0/TX1 drive | 0x09 on all four bytes, emphasis 0, ldo 0xd0, band 0x04 | driver's fixed values |

**The firmware runs this panel on two lanes at HBR; the device tree
declares four.** 1920 x 1200 at 60 Hz, 24 bpp needs about 3.6 Gb/s of
payload, which two lanes at 2.7 Gb/s carry (5.4 Gb/s raw, 4.3 Gb/s after
8b/10b), so there is no reason for HP to have wired four. If the panel's
DPCD advertises four lanes, msm will train all four, and clock recovery
cannot succeed on lanes that are not connected. That fits the observed
failure (the panel never finished clock recovery, `max v_level reached`).

This is the leading candidate, not a confirmed cause: the DPCD was never
dumped (that happens in phase 5), so I do not know what lane count the
panel advertises. If it advertises two, msm already used two and the cause
is elsewhere (PHY TX values, SSC or the lane-rate ladder). Lab variants V6
(2 lanes) and V9 (the firmware's lanes, rate and TX values) test exactly
this.

### Bluetooth (phase 3): HP's firmware pair works and is kept

HP's `clnbtfw10.tlv` and `clnbtnv10.*` installed as `ornbtfw11.tlv` and
`ornnv11.*` load and bring the controller up:

| | linux-firmware | HP's pair |
|---|---|---|
| Firmware build | `BTFW.ORNE.1.1.0-00202-PATCH-2_DEF` | `BTFW.ORNE.1.1.0-00206-PATCHZ-1_DEF` (newer) |
| NVM loaded | `ornnv11.b17` fails, falls back to `.bin` | `ornnv11.b17` (HP's board-0x17 NVM) |
| Result | up | up, AOSP extensions v1.05, scan sees devices |

The HP pair logs `unexpected event for opcode 0xfc48` once during the
download, harmlessly. `ornbcscal11.b17/.bin` (calibration) is still
requested and missing with either pair; HP's driver pack has no file by
that name. The lab kept HP's pair, so the corrected `install-firmware.sh`
output is now in `/usr/lib/firmware/updates/qca/` (`ornbtfw11.tlv`,
`ornnv11.*`; the stale ROM-10 copies are still there and unused).

### Baseline (phase 1)

`10-baseline.txt` (198 KB) is the full subsystem baseline for this device
tree; nothing in it changes the catalogue in `docs/status.md` /
`docs/lab-boot-state-2026-09-28.md`.

## What went wrong

1. **The laptop hung in phase 4.** The last journal line of the lab boot is
   `scmi-cpufreq scmi_dev.5: probe with driver scmi-cpufreq failed with
   error -110`, after two `arm-scmi arm-scmi.0.auto: timed out in resp`
   errors ("Failed to query supported version for protocol 0x13"). The
   journal stops there: no oops, no panic, the next entry is the owner's
   next boot. `40-power.txt` is 0 bytes and `lab.log` ends in NULs, the
   signature of a hard hang or reset before the filesystem synced. The
   trigger is the lab's own `modprobe qcom-cpucp-mbox; modprobe
   scmi-cpufreq`, so **do not load `scmi-cpufreq` on this kernel**: the SCMI
   performance protocol on this firmware does not answer, and probing it
   takes the machine down. (The SCMI perf channel is what cpufreq would use,
   so CPU frequency scaling needs a different route than the stock driver.)
2. **`/run/modprobe.d` does not exist**, so `glymur-lab-run.sh` line 47
   failed and the drop-in that keeps the stock eDP PHY driver out and turns
   on `dyndbg` for msm and the panel was never written. The instrumented PHY
   module was still inserted directly.
3. **PMIC GLink/battery detail from phase 4 was lost** with the crash. The
   live readings (battery 50%, 59.9 Wh, AC offline, UCSI supplies) are
   already in the lab-boot doc.

## Fixes made to the kit

- `glymur-lab-run.sh`: `mkdir -p /run/modprobe.d`; `sync` after each phase
  so a crash cannot eat the log; `scmi-cpufreq`/`qcom-cpucp-mbox` are skipped
  unless `GLYMUR_LAB_CPUFREQ=1`; the Bluetooth A/B is skipped when HP's pair
  is already installed.
- The kit at `~/glymur-lab-kit` has the fixed scripts and a regenerated
  `SHA256SUMS`. The USB copy is stale (only its scripts differ).

## Next

- Re-run the lab on the display-lab boot: `sudo bash
  ~/glymur-lab-kit/start-lab.sh`. This time phase 5 should run: DPCD dump
  and ten variants. Expect the screen to go dark for the display phase.
- Whatever the DPCD says, try `data-lanes = <0 1>` in the full DT: it is
  what the firmware runs. If V6 or V9 trains the panel, that is a
  one-line DTS fix (plus `link-frequencies` limited to what the panel
  needs).
- CPU frequency scaling needs another approach; SCMI perf via
  `scmi-cpufreq` hangs the machine.
