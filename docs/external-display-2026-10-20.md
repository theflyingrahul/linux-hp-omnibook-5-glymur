# External Displays over USB-C, October 20, 2026

Issue #7. The laptop has no HDMI port; external displays use DisplayPort
alternate mode on the two USB-C ports. Windows has driven one: its device
history holds an "ACX External Display Audio Device" for an external
monitor and USB-C adapters with a Billboard interface (DP alt-mode
adapters).

## Upstream

`glymur.dtsi` (qcom-next `1a0586064ee1`) already links DP0 to the DP input
of `usb_0_qmpphy` (labelled `usb_dp_qmpphy_dp_in`) and DP1 to
`usb_1_qmpphy`, and leaves `mdss_dp0`/`mdss_dp1` disabled. Our device trees
already describe the USB-C connectors on pmic_glink with those PHYs, and
`pmic_glink_altmode` (with `upstream/qcom-next/0001`) carries the alt-mode
and hot-plug notifications. Two boards in the Linux MSM laptops kernel add
exactly four blocks: `mdss_dp0`/`mdss_dp1` enabled and their output
endpoints given `link-frequencies` up to 8.1 Gb/s. They are HP's EliteBook
X G2q (Glymur) and the Lenovo ThinkPad T14s Gen 7 (Mahua, this die).
`mahua.dtsi` does not touch these nodes. The Glymur CRD in qcom-next enables
only its eDP controller.

HP's ACPI does not say which connector supports which alternate mode
(`UCSI` and its `UCN0`–`UCN2` only carry `_UPC`/`_PLD`), so both ports
are enabled, as on both reference laptops.

## The test (kernel -15, test device tree)

The same four blocks. `check-display.sh` lists the DRM connectors, the
USB-C ports' alternate modes and the kernel log; run it with nothing
plugged in, then with a monitor or adapter on each port.

If a DP controller failed to probe, the display driver could not finish
binding and the test boot could stay dark; the daily device tree is
unaffected and remains the way back.

Not yet: DisplayPort audio (the topology's `DISPLAY_PORT_RX_0/1` sinks,
as in `MAHUA-LENOVO-ThinkPad-T14s-Gen7.m4`, sound card links and UCM
devices). That follows once video works.
