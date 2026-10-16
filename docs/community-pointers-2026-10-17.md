# Community Pointers, 2026-10-17

Readers of the project's r/snapdragon post pointed at several trees and
patch series. Each pointer was treated as unverified and checked against the
trees and patchwork on 2026-10-17. This note records what each one holds for
this laptop. Nothing here is in a build yet unless it says so.

## The linux-msm laptops kernel

Pointer: `https://github.com/linux-msm/laptops-kernel`, branch
`topic/glymur-laptops`, is the most current Glymur branch and carries the
eDP PHY patches.

Checked: tip `c9f816899dc2` (2026-10-02), linux-next `next-20260930` plus
219 Glymur and Mahua laptop patches: posted series up to a
"from list" marker, then fixups, hacks and unposted fixes. The same
repository's `qcom-laptops` branch (mainline 7.3-rc7 plus 76 mostly X1E
patches, 2026-10-14) is the one Qualcomm's `qcom-deb-images` CI builds and
tests on the Glymur CRD (`db50a02`, `b80a1f4`); the Glymur topic branch is
not in it yet. The topic branch carries Glymur board device trees
for the ASUS Zenbook A14 and A16, the CRD and QCB, the HP EliteBook X G2q,
the HP OmniBook Ultra 14 and the Lenovo Yoga Slim 7x. It also has the first
Mahua laptop, `mahua-lenovo-thinkpad-t14s-gen7-lcd.dts`, posted to the list
on 2026-10-15.

Commits that bear on open problems here:

| Commit | What it does | Relevance here | Upstream state |
|---|---|---|---|
| `e341ce20c59b` power: supply: qcom_battmgr: refresh on Glymur state notifications (Tyler Baker) | Registers pmic_glink owner 32782, where Glymur firmware sends plug and unplug notifications (opcode `0x103`), and signals a change on the battery, AC and USB supplies | Matches the charging finding that battmgr's AC and USB `online` do not track the charger (`docs/usb-c-charging-2026-09-29.md`) | Not on patchwork; author's GitHub |
| `240662d141e2` fixup! phy: qcom: edp: update v8 power-on programming sequence (Abel Vesa) | The last write of `qcom_edp_configure_pcs_v8()` becomes `DP_PHY_CFG_1 = 0x0f` instead of `0x2f` | `backports/0002` still writes `0x2f`. Qualcomm's QMP-combo DP PHY v3 series also ends its init with `0x0f`. One `-110` link-training failure was seen after the backport (2026-09-29) | Fixup to Bjorn Andersson's v1, which is "changes requested"; no v2 found |
| `2c82b3799713` dmaengine: qcom: gpi: order ring memory against register access (Tyler Baker) | `readl`/`writel` for the GPI doorbells and event read pointer | The failure in its message is on `a84000.i2c` (GPI DMA), the same controller as this laptop's EC; heavy EC polling faulted within 40 s | Not on patchwork |
| `99d4f161c3d1` dmaengine: qcom: gpi: Set IEOB on linked I2C GO TRE (Vsevolod Nevorotov) | Retires TX descriptors of GPI I²C reads | Same EC bus; ring exhaustion under sustained reads | Posted 2026-09-09, new |
| `471f81c4087a` arm64: dts: qcom: Fix USB interrupts in Glymur DT (Krishna Kurapati) | Adds the missing `hs_phy_irq` to `usb_0`, `usb_1`, `usb_2`; fixes `usb_hs` DP/DM and `usb_mp` numbers | qcom-next `1a0586064ee1` has `hs_phy_irq` on one USB node only. Wakeup interrupts, not enumeration | Posted 2026-08-03, changes requested |
| `41e7d9239316` drm/msm/dp: keep eDP at its native lane count after an EQ failure; `d795f6bb6df9` make the eDP 1.4 LINK_RATE_SET path reachable (Tyler Baker, Jesse Casco) | A transient EQ failure no longer drops the panel to fewer lanes; LINK_RATE_SET panels train through the rate table | The intermittent eDP `-110` seen once on a back-to-back boot | Not on patchwork |
| `11bd3da32f13` usb: dwc3: qcom: reset the xHCI on resume on Glymur | Resume after s2idle | Only once suspend is unmasked | Not on patchwork |
| `9166f023cff7` glymur: Refrain from overclocking the USB2 controller (Konrad Dybcio) | `usb_hs` master clock 60 MHz at LOW_SVS | `usb_hs` carries the camera | Not on patchwork |

Not applicable: `eccd702d1733` "eusb2_hack" forces `has_eusb2_phy` in
dwc3-qcom; qcom-next's dwc3-qcom has no such field.

## Audio

Pointer: the LPASS patches on linux-arm-msm.

Checked: this laptop's only SoundWire peripheral (`MAN_0217&PART_0110`,
`docs/audio-evidence-2026-09-29.md`) is the Qualcomm WCD9378 "Tambora".
Srinivas Kandagatla's driver `sound/soc/codecs/wcd9378-sdw.c` matches
`SDW_SLAVE_ENTRY(0x0217, 0x0110, 0)`, and was accepted into ASoC on
2026-09-25 (v5). The audio note's "part `0x0110` is not in any Linux driver"
is out of date.

The rest of the path is also posted: the Glymur LPASS and LPASS audio clock
controllers (v3, 2026-10-02), the Glymur LPASS rx/tx macro codecs,
SoundWire multi-master, and the LPASS glue and SoundWire nodes in
`glymur.dtsi`. All of it is collected in the laptops branch, with the
ThinkPad T14s (Mahua) device tree enabling the WCD9378 as a working
example. `qcom-deb-images` now installs the AudioReach userspace
(`857c678`). The speakers still need their own evidence: the Windows
capture shows no SoundWire amplifier.

## TPM and QSEECOM

Pointer: TPM needs an experimental QSEECOM driver and the TPM application
behind it; a prototype is on GitHub but needs extending.

Checked only in part: no prototype URL was given and none was found. What is
established is that QSEECOM access is gated per board by an allowlist in
`drivers/firmware/qcom/qcom_scm.c`. Entries were posted in October for the
HP EliteBook 6 G1q, the Surface Laptop 8th Edition and the Samsung Galaxy
Book4 Edge, and the laptops branch carries one for the HP OmniBook Ultra 14.
This laptop would need its own entry (its compatible) before QSEECOM, and
with it the UEFI variable service, can be tried. The TPM claim stays
unverified.

## NPU

Pointer: Qualcomm said it is developing an NPU driver. Not verifiable from
the trees; the NPU stays "not started".

## qcom-deb-images

Pointer: Qualcomm's image recipes carry drivers not yet posted, such as the
Iris video DKMS. Checked: since the local copy (2026-09-23) it gained Mahua
CRD board support (`a7f9aa1`), the Iris DKMS in the multimedia variant
(`b4f0996`), the AudioReach audio stack (`857c678`), and Glymur boot binaries
00093 (`f83ddf3`, flashing only; not for this laptop).

## Decision

qcom-next, Qualcomm's own kernel, stays the base. The laptops kernel's
`topic/glymur-laptops` was considered as a replacement on 2026-10-17 and
rejected: it is a community staging tree on linux-next with no CI on that
branch, and it carries hacks and unposted patches, while this project
prefers accepted work. Fixes from it are ported one at a time after a
check: kernel `-13` carries the battery-manager notification fix, both GPI
fixes and the eDP `CFG_1` fixup as `backports/0023–0026`
(`patches/README.md`). The USB interrupt fix (changes requested) is left
out; the audio series will be ported when audio bring-up starts.
