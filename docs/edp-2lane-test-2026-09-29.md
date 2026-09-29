# eDP 2-Lane Test and GRUB Menu Clean-up, September 29, 2026

The display lab's two runs (`docs/display-lab-run1-2026-09-28.md`,
`docs/display-lab-run2-2026-09-28.md`) captured the firmware's working eDP
link but hung the laptop before any display variant ran. This replaces the
lab's display phase with one boot-time test of the firmware's link
configuration, using the stock drivers.

## Evidence

- **The firmware's link, from its DP3 controller registers:**
    - `CONFIGURATION_CTRL` = 0x00084557 decodes, with the bit layout in
      msm's `dp_reg.h`, to lanes field 1 (2 lanes), 8 bpc, enhanced
      framing, ASSR and LSCLK divider 2. That is a normal, self-consistent
      configuration.
    - Mvid/Nvid = 0x4100/0x7530. The MSA ratio must equal pixel clock over
      link symbol clock, or the sink could not regenerate the stream:
      149.76 MHz × 30000 / 16640 = 270 MHz, which is 2.7 Gb/s per lane.
- **2 lanes is the most the firmware can use.** With 4 lanes available,
  a "minimum rate" policy would pick 4 × 1.62 Gb/s, and a "maximum" policy
  4 lanes at the top rate. Both carry 1920×1200 at 60 Hz. 2 × 2.7 Gb/s means
  the lane limit is 2: either the panel's DPCD or HP's board wiring.
- **What our full DT makes msm do** (qcom-next `a47c4c5aa`):
    - msm trains at min(DPCD lanes, `data-lanes`) lanes and the highest
      rate not above the last `link-frequencies` entry. That includes the
      eDP 1.4 `SUPPORTED_LINK_RATES` table (`dp_panel.c`).
    - `msm_dp_ctrl_on_link` makes 4 attempts. After a clock-recovery
      failure it only steps the rate down, one table entry or standard
      rate at a time. It halves the lanes only after the lowest rate has
      failed and only if the lower half of the lanes locked (`dp_ctrl.c`).
- **Two readings, one test.**
    - If the panel advertises 4 lanes but only 2 are wired, clock recovery
      can never pass on lanes 2 and 3. The panel keeps asking for more
      swing ("max v_level reached"), and 4 attempts are spent on rates
      before any 2-lane attempt.
    - If the panel advertises 2 lanes, msm already used 2, but it started
      above 2.7 Gb/s. With a rate table, 4 single steps may never reach
      2.7 Gb/s.
    - `data-lanes = <0 1>` with `link-frequencies` up to 2.7 Gb/s starts
      msm at exactly the firmware's configuration in both cases.
- **Precedent does not settle it.** The Glymur CRD and the Zenbook A16 run
  Samsung ATNA panels on 4 lanes up to 8.1 Gb/s. Our 4-lane endpoint was
  copied from them; nothing from this machine supported it.

## Why boot time, not the lab

The first full-DT boot probed dispcc, msm and the stock eDP PHY driver at
boot and did not hang. The lab's display phase hung right after stopping
the desktop, where it applies the display overlay at runtime.

- My earlier guess, that Linux dropped the display power domain, does not
  fit. The firmware picture stayed lit through lab phases 1 to 4, after
  Linux had released its boot-time votes, so another voter holds it.
- A candidate that only the lab has: the instrumented PHY driver
  (`make-phy-edp-lab.py`) enables its clocks and reads the PHY registers at
  probe, right after the display clock controller has probed at runtime.
  The stock driver does not touch the PHY at probe.
- journald does not sync ordinary messages, so "the last line on disk"
  never located the hang.

The cause of the hang is unknown. The test below avoids everything the lab
added.

## What is staged

- `dts/qcom/mahua-hp-omnibook-5-bf1xxx-edp-2lane.dts`: the full device
  tree plus
  ```
  &mdss_dp3_out {
      data-lanes = <0 1>;
      link-frequencies = /bits/ 64 <1620000000 2700000000>;
  };
  ```
  and the model "(eDP 2-lane test)".
- Built by `scripts/linux/glymur-lab/build-test-dtb.sh` against the
  `7.3.0-rc2-glymur-3` build. It passes the GPIO allow-list check (24 pins
  used, 227 reserved). The decompiled DTB differs from the `-3` package's
  full DTB only in the model and these two properties; the full DTB rebuilt
  from the current tree is byte-identical to the one in the package.
  SHA-256 `9afcd84c…07311`.
- On the USB: `glymur-tools/edp-test/` (the DTB and `SHA256SUMS`) and the
  GRUB entry "Ubuntu on SSD: eDP test, 2 lanes (device tree)". It boots the
  SSD's `vmlinuz-7.3.0-rc2-glymur-3` with this DTB and adds
  `drm.debug=0x102 log_buf_len=16M`. DRM driver and DP messages include the
  panel's DPCD capabilities, the chosen rate and lanes, and every training
  step.
- The full DTS is unchanged until the test boots.

## Running it

1. Boot "Ubuntu on SSD: eDP test, 2 lanes (device tree)".
2. If the panel lights, log in and run
   `journalctl -k -b | grep -iE 'dp|edp|link|lane'`.
   The fix is then to move the two properties into the full DTS.
3. If it stays dark, wait at least three minutes (the boot report runs at
   60 s, and the page cache needs time to reach the disk), then hold the
   power button. On the next boot (minimal DT or ACPI), read
   `journalctl -k -b -1` and `/var/log/glymur/boot-*.txt`.

| Result | Meaning |
|---|---|
| Panel lights | The lane or rate limit was the cause. Merge it into the full DTS. |
| Dark, log shows 2 lanes at 2.7 Gb/s failing clock recovery | The link parameters are ruled out. The remaining differences are electrical: PHY drive/LDO values, SSC. Test those next, at boot time. |
| Dark, log shows something else | Read the DPCD and the training steps before changing anything. |

## GRUB menu clean-up

The USB menu had 15 entries, several of them retired tools. It now has 9,
in this order:

1. "Try or Install Ubuntu", "Boot from next volume" and "UEFI Firmware
   Settings": stock, unchanged, "Try or Install Ubuntu" still first.
2. "Ubuntu on SSD: eDP test, 2 lanes (device tree)": new, one-off.
3. "Ubuntu on SSD: device tree (minimal)" and "(full)".
4. "Ubuntu on SSD: ACPI, newest glymur kernel" and "ACPI, previous glymur
   kernel". These are the old "newest/previous glymur kernel" entries,
   renamed so the menu says which firmware path each boots. They are the
   boots with a working USB port.
5. "Glymur workstation: persistent desktop, input, Wi-Fi, repo". The two
   workstation entries are merged: the plain one and the "+ _OSC fix" one
   had the same kernel command line, so the kept entry is the BIOS-gated
   one under the plain name.

Removed:

- "Glymur whole-system inventory", "Glymur ACPI keyboard/touchpad test"
  and "Glymur live desktop" (RAM live). These are retired collectors; their
  templates stay in `scripts/linux/`.
- "Ubuntu on SSD: qcom-next 7.3.0-rc2-glymur" and its "(no DSDT override)"
  twin. They booted the first SSD kernel; the ACPI entries above fall back
  to it.
- "Ubuntu on SSD: display lab (device tree)". The lab kit stays on the USB
  and the SSD; `stage-kit.sh` says how to restore the entry.

Every kept entry's body is byte-identical to its previous version.
`grub-script-check` passes. The file on the USB matches the rendered copy by
hash, and `chkdsk` is clean. `scripts/linux/glymur-ssd/grub-entry.cfg` is the
template for these SSD entries.
