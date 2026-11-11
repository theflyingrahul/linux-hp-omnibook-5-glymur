# Patches

Kernel changes are split by who benefits:

| Directory | Contents | Upstream? |
|---|---|---|
| `kernel/upstream/qcom-next-acpi/` | Generic ACPI mechanisms for Snapdragon X2 (Glymur) laptops, as a `git format-patch` series against Qualcomm `qcom-next` (written on `a47c4c5aa`, applied since kernel `-5` on `e428097a36d`) | Yes, candidates |
| `kernel/upstream/qcom-next/` | Generic fixes against `qcom-next`, not ACPI-specific (since kernel `-6`) | Yes, candidates |
| `kernel/upstream/mainline/` | The generic fixes in their mainline form, as sent upstream on 2026-09-30 | Sent |
| `kernel/backports/` | Fixes by others, posted or already in mainline, carried on our qcom-next base until qcom-next picks them up | Already posted or merged |
| `kernel/glymur-bringup/` | Interim Glymur code, applied on top of the upstream series | No; replaced later |
| `kernel/drafts/` | Upstream-form drafts not yet used in a build | Future |
| `kernel/archive/` | Superseded diagnostics, kept for the record | No |
| `util-linux/` | Userspace (`lscpu` part ID) | Yes, candidate |

Board-specific values (pin lists, controller lists, the DSDT override,
Wi-Fi board data, firmware) are not kernel code. They live in
`boards/hp-omnibook-5-16-bf1xxx/`.

## Boot series (built by `scripts/linux/build-qcom-next-glymur.sh`)

Apply to qcom-next `17bbb4b37bbc` (tag `qcom-next-7.3-20261031`, 7.3, from
kernel `-19`; it was `c7896917e523` (`qcom-next-7.3-rc6-20261023`) for
`-18`, `1a0586064ee1` (`qcom-next-7.3-rc4-20261014`) for `-13`
to `-17`, `6b4daa845239` for
`-8` to `-12`, `e428097a36d` for `-5` to `-7` and `a47c4c5aa` up to `-4`)
in order:
`upstream/qcom-next-acpi/0001–0003`, `upstream/qcom-next/0001–0006`,
`0009` and `0010`, `glymur-bringup/0001–0006`, then `backports/` (`0001–0002`,
`0023–0026`, `0030–0037`, `0040–0043`, `0047–0088`) (`scripts/linux/prepare-qcom-next-glymur.sh`). Kernel `-4` carried
backports 0001–0002; `-5` carries all twelve; `-6` adds
`upstream/qcom-next/0001`; `-7` adds `upstream/qcom-next/0002`; `-8` moves
to the new base and adds `upstream/qcom-next/0003`; `-9` adds `0004`–`0005`
(the HP EC; qcom-next was still `6b4daa845239` when fetched before it);
`-10` reworks `0005` (backlight timeout instead of a level LED, EC events
and hotkeys; qcom-next unchanged again); `-11` adds the read-only
backlight level to `0005` and `backports/0013–0014`, the Mahua GPU;
`-12` adds `backports/0015–0016`, the dwc3-qcom software-node fix (qcom-next
still `6b4daa845239` when fetched before it)
(qcom-next and mainline fetched again before it, on 2026-09-30: qcom-next
still `6b4daa845239`; mainline's only new commit in our drivers is
`cb97bf3d4f`, still not taken, see below). A fresh `prepare`
reproduces the build tree's source exactly.

Base move for `-13` (2026-10-17): qcom-next was rebuilt on 7.3-rc4
(1802 commits since `6b4daa845239`). It now carries `backports/0003–0012`
(mainline rc3..rc4) and the dwc3-qcom revert and replacement that
`backports/0015–0016` carried (`41c91eb285c4`, `6f2460005b7a`), so those
twelve files are dropped. Everything else applies unchanged, without
three-way merges, and a fresh `prepare` reproduces the tested tree
(`ef714db1…`). Mainline (`v7.3-rc7-164-g70dd4ee72e`, 2026-10-16) has five
fixes in drivers we use that qcom-next lacks (`backports/0017–0021`), and
four laptop fixes come from the Linux MSM laptops kernel
(`backports/0023–0026`); both below. New in qcom-next and relevant here:
`92757057bb4a` (FROMLIST) "phy-qcom-eusb2-repeater: Fix SMB Power leakage
issue", for the SMB2370 repeaters on the USB-C ports. Its `glymur.dtsi`
now enables the APSS CoreSight trace path (`e69025f64fe7`, FROMLIST: 12 ETMs,
funnels, replicators, two TMCs); the board `.dtsi` disables those 31 nodes.
With that, the `-13` daily DTB enables exactly the nodes `-12` did, apart
from the CDSP FastRPC context banks renumbered by `797f471a15c3`.

Kernel `-14` (2026-10-17) adds `upstream/qcom-next/0006`, "ASoC: qcom:
audioreach: send static calibration for every module". Commit
`c7ed4c2debfd` ("add support for static calibration", Srinivas
Kandagatla, 6.18) lets a topology carry a module's calibration as a list of
parameter records, meant for echo and noise cancellation and speaker
protection, but `audioreach_set_media_format()` sends it only for
`MODULE_ID_SMECNS_V2` (still so in linux-next of 2026-10-17). `0006`
sends it for every module that has it, before the media format and the
driver's own parameters, so those keep precedence; SMECNS and topologies
without calibration behave as before. It is how HP's ACDB tuning reaches
the DSP (`docs/audio-tuning-2026-10-17.md`). Fetched before it: qcom-next
still `1a0586064ee1`; mainline `v7.3-rc7-244-g58161ead29` has no new commit
in our drivers since `-13`'s check. A fresh `prepare` reproduces the build
tree.

Kernel `-15` (2026-10-20) adds `upstream/qcom-next/0007`, "ASoC: codecs:
wsa884x: disable runtime PM when the driver is unbound": the driver left
runtime PM enabled after unbind, and the pending autosuspend then
dereferenced a released regmap (the `-14` crash); it uses
`devm_pm_runtime_enable()`. Mainline and linux-next have the same code. It
also reworks `0005`: the EC LEDs get the `audio-mute`/`audio-micmute`
default triggers, as the ThinkPad T14s EC driver does
(`docs/audio-mute-leds-2026-10-20.md`), and registers its thermistors as
thermal sensors through `HWMON_C_REGISTER_TZ`, with `0004`'s binding
allowing `#thermal-sensor-cells`, for HP's skin zones in the test device
tree (`docs/thermal-skin-2026-10-20.md`). Fetched before it: qcom-next still
`1a0586064ee1`. Mainline `v7.3-341-gf47d223627` has one new commit in our
drivers, `8cb5c17be3` "i2c: qcom-geni: Restore the source-clock selection
policy"; it fixes `cb97bf3d4f`, which qcom-next never took, and qcom-next
already uses the policy it restores, so neither is needed. A fresh
`prepare` reproduces the build tree.

Kernel `-16` (2026-10-21) adds `upstream/qcom-next/0008`, "media: iris:
add a one-core variant for Mahua": `qcom,mahua-iris` (fallback
`qcom,glymur-iris`, as for Nord) with the Glymur platform data and
`num_cores = 1`. On the HP OmniBook 5 the Glymur data powers a second
video core whose GDSC (`video_cc_mvs1_gdsc`) never comes on, and Mahua's
device tree drops the second video thermal zone; whether Mahua really has
one core is not confirmed, so it is not for upstream yet
(`docs/kernel-16-plan-2026-10-21.md`). Fetched before it: qcom-next still
`1a0586064ee1`; mainline `v7.3-1703-ga804c5742b` has no new commit in our
drivers (the `drm/msm/dp` fixes `e249a6e2a1` and `707ce10252` are in the
base and `backports/0020`; `58995b11df` fixes mode validation under wide
bus and does not touch our failure). Looked at and not taken: the Linux
MSM laptops tree's Glymur DP PHY series (11 patches, v5, `1d2d3337824a` to
`d11873c94ea1`). qcom-next carries older revisions of the first three and
parts of the rest, and the two do not merge (20 conflicts in
`phy-qcom-qmp-combo.c` that are not mechanical); the same PHY carries
USB-C SuperSpeed, which works. The DTS changes of `-16` (EC zone names,
amplifier supplies, Iris compatible, DisplayPort off) are in the test
device tree only. A fresh `prepare` reproduces the build tree.

After `-16` (2026-10-22, not built yet): `0008` is dropped. HP's video
firmware refused the one-core configuration as it refused two cores, so
the core count was not the fault, and Iris is off again in the test device
tree. `0005` reads the EC's pending event from register `0x00`, where HP's
`IC10.INTR` reads it (field `CMD5`, no offset), instead of `0x05`; the old
value left a fan notice unacknowledged and the event line firing about nine
times a second (`docs/audit-2026-10-22.md`).

Kernel `-23` (2026-11-11, `docs/linux-runbook-23-2026-11-11.md`), same
base (package sha256 `7b951b11…`); it replaces `-22`, which was never booted. qcom-next fetched again
before it: still `17bbb4b37bbc`. One change, for the USB-A port's
SuperSpeed failures (`docs/usb-a-superspeed-2026-11-11.md`):

- `glymur-bringup/0006`, new, not for upstream: an optional
  `qcom,usb3-lane-a-overrides` property on the QMP combo PHY. It takes
  `<offset value>` pairs in lane A, written after the lane tables on every
  power-on, with a read-back logged once. HP's ACPI `\_SB.USB2.PHYC`
  gives two such writes for the USB-A port: `RX_MODE_RATE_0_1_B1` = `0xa0`
  and `RX_MODE_RATE2_B1` = `0x90`, where Linux writes `0xa2` and `0x93`.
  Only the test device tree sets them, so the test and daily entries form an
  A/B pair on one kernel. Upstream, the values would go into the PHY's
  tables or a described tuning property; there is no such property for QMP
  PHYs yet. The nearest precedent is `qcom,hs-drv-slope` on the HS PHY (June
  2026).

Kernel `-22` (2026-11-11), same base. Upstream on November 11: qcom-next
still `17bbb4b37bbc` (no 7.4 line yet), the laptops trees unchanged
(`topic/glymur-laptops` `8c9d1255de`, `qcom-laptops` `98172d02f4`, both read
for `-20`), mainline at `v7.4-rc2`, linux-next at `next-20261110` (229 commits
since `next-20261105` in the drivers and device trees this laptop uses), and
Patchwork (linux-arm-msm, alsa-devel) since November 1. Taken:

- `backports/0087`, Peter Chen's "arm64: dts: qcom: glymur: Set
  snps,resume-hs-terminations for USB controllers" (linux-next
  `45cf7caf54`): with the M31 eUSB2 PHY, Qualcomm's hardware guide requires
  `GUCTL1[10]` for USB2 resume, or a device cannot be reset after it
  resumes. For USB after suspend and the full/low-speed problem (#6).
- `backports/0088`, Qiang Yu's "clk: qcom: gcc: Set
  FORCE_MEM_CORE_ON/FORCE_PERIPH_CORE_ON for PCIe pipe clocks" (linux-next
  `fbfe0c4bee`), the Glymur part only: without it the PCIe endpoint can fail
  to reach host memory (completion timeouts); here the NVMe and Wi-Fi are on
  PCIe 5 and 4.
- The config leaves out `CONFIG_NVME_SPEED_SWITCH` (below, under `-21`).

Read and not taken: the AV1 encoder clock controller with its "XO clocks
critical" change (`0a253c32a2`; a critical XO branch keeps the crystal
vote, which deep sleep needs released, and nothing here uses AV1 encoding);
the Glymur CRD regulator consolidation (CRD only; its L8B0 fix to 3.304 V
confirms our HP value for the eUSB2 repeaters' rail, and Abel Vesa's
ACPI-derived Mahua T14s fix sets L7B to 3.072 V, our value); "glymur: Drop
L4F0" (we never declare it); the REFGEN supplies for the PCIe PHYs (needs
LDOs we only declare from HP's votes); the Glymur eDP lane drive levels
(HBR2 only; we run HBR); battmgr's USB connector temperature and input
current limit (features). Candidates for a later kernel, each with a test:
the two qmp-combo DisplayPort fixes ("delay Type-C mux switch while DP PHY
is initializing", v2 of 2026-11-11; "Leave the USB PCS alone in DP-only
mode", v3) for the external display step, and Vishnu Reddy's Iris power-off
and runtime-PM fixes (v2, 2026-11-10/11) for the Mahua video trials. Not
posted yet: Akhil P Oommen's GMU series v3 (the clock controllers'
`sync_state`), anything new for the WCD9378 or the PMIC GLink RTC.

Kernel `-21` (2026-11-10, `docs/linux-runbook-21-2026-11-10.md`), same
base: qcom-next is still `17bbb4b37bbc` (fetched 2026-11-10), linux-next
moved to `next-20261109` with nothing new for the drivers changed here.
Fixes from `-20`'s boots (`docs/runbook-results-20-2026-11-10.md`):

- `upstream/qcom-next/0005`, the EC series v2 corrected: `fn_lock`
  read-only with the EC's polarity, `kbd_backlight_timeout` notified on
  the backlight events, the standby exit retried on resume.
- `upstream/qcom-next/0010`, new: `sdca_apply_default_control_classifiers()`
  (Qualcomm's PENDING helper in the base) now also gives a control without
  a width the specification's width and type, as `sdca_parse_function()`
  does on ACPI. The WCD9378's DT tables set them for two controls only, so
  the Requested PS controls shifted by 64 (UBSAN) and `GE 35 Detected Mode`
  had a range of 0: no jack detection. A fix to the PENDING code, for
  Qualcomm.
- `backports/0086`, new: reverts qcom-next's FROMLIST `6436ceccf83c`
  ("i2c: i2c-qcom-geni: serve transfers during early resume", v6, which
  the list superseded with v7 in July; neither is in mainline). Its
  `resume_noirq` enables runtime PM itself, so every resume warned
  "Unbalanced pm_runtime_enable!" for four controllers, and it keeps the GPI
  interrupt live through suspend; the EC bus's first transfer after one
  resume failed in GPI DMA. Mainline's `resume_noirq` does neither.
- `glymur-bringup/0005`, new: `qcom_iris.diag_partial_av1_only` (default
  off) attaches the decoder's partial-data buffer to AV1 sessions only;
  Mahua's firmware rejects it on H.264, and every decoder session attaches
  it in mainline too.

For `-22`, the config also leaves out `CONFIG_NVME_SPEED_SWITCH`: qcom-next
carries a FROMLIST adaptive NVMe link-rate switching series (Liao Xuan,
Hygon/Kylin, `565e1c0bc2d6` and two follow-ups; not in mainline) whose
retrain to Gen5 failed every one to two seconds on `-21`, freezing NVMe I/O
each time, and which has no suspend hook (`docs/runbook-results-21-2026-11-10.md`).
On `-21` it is turned off at run time.

A fresh `prepare` applies all of it (74 commits) and gives the same tree as
the incremental work. Built on the 48-core cross-build host with kernel.org
GCC 15.2 and binutils 2.45 (the WSL builds used Ubuntu's GCC 15.2 and
binutils 2.46; the kernel configuration differs only in version fields
and in two userspace samples the kernel-only toolchain cannot link).

Kernel `-20` (2026-11-09, `docs/kernel-20-plan-2026-11-09.md`), same
base. qcom-next is still `17bbb4b37bbc`, linux-next's newest tag still
`next-20261105` and the laptops tree still `8c9d1255de`. Mainline moved to
`v7.4-rc2` (`7475ea8b58`); of its commits in drivers this laptop uses,
`e2df0223ba` is `backports/0057` already and `ef7062864c` ("ASoC: qcom:
q6apm: Guard callbacks until probe data is ready") is in the base as
Qualcomm's FROMLIST `d023cbd2af88`. Also read: Tyler Baker's ASUS Zenbook
A16 (Glymur) branch (`github.com/EmbeddedAndroid/linux` `a16-zenbook`,
`7bf252e17abe`) and Patchwork (linux-arm-msm, linux-phy, linux-usb). Added,
for suspend, USB and the headset:

- `0076` UCSI's connector worker on the freezable workqueue (Abel Vesa,
  posted 2025, laptops tree `d3b9973eb8`): a plug event during suspend
  waits until the devices have resumed.
- `0077–0078` (laptops tree `848e04855f`, `b3d41e63f7`; Abel Vesa's
  "HACK" commits, not posted): QRTR sends HELLO before MHI receive on
  resume, and ath12k keeps its thermal devices across a firmware recovery
  during resume. Both for Wi-Fi after s2idle.
- `0079` xhci-plat reads `xhci-reset-on-resume-quirk` as a device property
  (Faisal Hassan, posted, laptops tree `f5fb8b1b60`), and `0084` Tyler
  Baker's "usb: dwc3: qcom: reset the xHCI on resume on Glymur"
  (`12b940c257d0`, not posted): the Glymur controllers lose their state in
  s2idle, so they stop being wakeup sources and xHCI is reset on resume.
  Ported: our dwc3 has no `xhci_reset_on_resume` software property, so the
  port adds one to `struct dwc3_properties` instead of the original
  tree's dwc3 prerequisite.
- `0080` the M31 eUSB2 PHY's SE0 timeout (Elson Serrao and Peter Chen, v2,
  2026-10-27, reviewed by Konrad Dybcio, Abel Vesa and Krishna Kurapati,
  tested on the Zenbook A16), for the full- and low-speed `-71` (#6).
- `0081` collapse voting for the Glymur PCIe GDSCs (Taniya Das, accepted
  2026-10-28).
- `0082` pmic_glink_altmode work items on unbind (Abel Vesa, accepted
  2026-11-02).
- `0083` Glymur USB 3 PHY settings from the latest hardware reference guide
  (Konrad Dybcio, 2026-11-02, reviewed by Abel Vesa).
- `0085` SoundWire SCP page cache (Srinivas Kandagatla, `eb9ea1a0fa28`, in
  7.4-rc2), so the WCD9378's two-byte volume writes stay atomic.
  Backported: our transfer function takes the device number as an argument,
  which can be the broadcast address, so only device numbers within the
  cache are cached.

Already carried, so not added again: Tyler Baker's battery-manager
notifications and GPI fixes (`0023–0025`) and Oleg Keri's DP training
result (`0031`). Already in the base: the repeater power-leak fix, the GPI
register ordering, Glymur's `rpmh-stats` node, the CDSP FastRPC context
banks with the right numbers, and most of Qualcomm's Glymur DP PHY series
(v6 patches 1–3 as FROMLIST `c202053823b5`, `45b4851e05b7`,
`e154e22d9a0a`, and an earlier revision of its init and configure rework,
`5323704e28fd`). Not taken: the rest of that series (5, 6 and 11 apply,
4 needs a merge, 7–10 overlap the base's rework and apply neither way; two
revisions are not mixed blind in the PHY that carries USB-C SuperSpeed);
Akhil P Oommen's GMU driver v2 (open regression, and patch 3 does not apply
to `msm_drv.c` here); Kamal Wadhwa's RTC v2 (it fixes an unbind
use-after-free and a late-reply timeout, but drops the `allow-set-time`
gate, so the kernel would write Windows' local-time RTC; it waits for
`check-rtc.sh`);
Tyler's gpio-keys lid filter, eDP self-test bit (our 2-lane path already
writes `0x3`), hid-asus and iris changes (other hardware or already
handled). The config is `-19`'s. Every patch applies with no fuzz
(71 commits), and a fresh `prepare` reproduces the build tree.

`-20` also carries the EC series' upstream v2 (2026-11-10) as
`upstream/qcom-next/0004–0005`, so it runs on the laptop before it is sent:
the binding requires the event line; the backlight level is a read-only
`platform::kbd_backlight` LED with `brightness_hw_changed` instead of the
`kbd_backlight_level` attribute; LED states use `HPEC_LED_STATE()`. After a
review against the other arm64 EC drivers and HP's tables
(`docs/ec-review-2026-11-10.md`) v2 also tells the EC about suspend and
resume as HP's modern standby `_DSM` does (OS flags `0x81`/`0x82`, register
`0x23` as on Qualcomm's reference EC), adds an `fn_lock` attribute (read
with `0xbd/0x01`, notified on event `0x88`) and logs every EC event at
debug level. After `-20`'s boot A (`docs/runbook-results-20-2026-11-10.md`)
`fn_lock` became read-only with the reading inverted (the EC replies 1 in
action-keys mode, and a write through the action-keys flag put its reported
state out of step), the backlight events also notify
`kbd_backlight_timeout`, and resume retries the standby exit (the EC bus's
first transfer after wake-up failed once); that version is in the repo's
`0005` but not in the `-20` package, which carries the first. Only the three EC files
differ from the v1 tree, so the build tree was moved to the v2 commits and
rebuilt incrementally.

Base move for `-19` (2026-11-05). qcom-next was rebuilt on 7.3
(`17bbb4b37bbc`, tags `qcom-next-7.3-20261031` and `qcom-7.3-20261102`;
1326 commits not in `c7896917e523`, 452 of its commits rewritten). Mainline
is at `v7.4-rc1-132-g05441d697f`, linux-next at `next-20261105`, and the
laptops tree was rewritten (now `8c9d1255de`). Dropped:

- `backports/0014`, `0017`, `0020`, `0027`, `0029` and `0046` are in the new
  base unchanged (they reverse-apply). `0013` (Mahua GPU) and `0028` (secondary
  rail vote) are there as Qualcomm's own FROMLIST commits (`2b119b01c9f7`,
  `d702f99c3135`; same 15.75 MB GMEM). The base also brings the rest of
  that A8x vote series (BX rail, MX clamp), which `-17` left out as
  Hawi-only. The CLX change is not in the base, so no revert is needed.
- `upstream/qcom-next/0007` and `0008` are fixed in 7.4-rc1 by Qualcomm the
  same way (`54c121eaee`, Srinivas Kandagatla: `devm_pm_runtime_enable()`
  in wsa884x; `e21fb64a8c`, Ravi Hothi: the module configuration blob sized
  in words and bounded by the private data). They are carried in their
  mainline form as `backports/0047–0048`, so neither needs sending.

`upstream/qcom-next/0002` (GMEM) is in 7.4-rc1 (`efbda69d92`), but not in
qcom-next yet, so it stays. Taken from 7.4-rc1 (`M`) and linux-next (`N`),
all accepted, all with `Fixes:` tags, in drivers this laptop runs:

- Audio, `0049–0057`: wsa884x VI-sense channel count (`a6093f98cb`) and
  temperature trim range (`00535515e3`); lpass-wsa-macro's v2.5+
  Compander1 addresses (`233d36a960`; it matters only if this LPASS
reports v2.5 or later, which the logs do not show yet);
  three q6apm buffer-unmap fixes (`4b832a2af5`, `43c6960427`,
  `a51c5dd7f7`); GPR service clean-up on a failed registration
  (`7dc14f37ca`); SoundWire's interrupt disabled before its clock is gated
  (`6c06767719`, N); an lpass-rx-macro runtime-PM reference leak
  (`e2df0223ba`, N). The q6apm position changes dropped from `-18` as a bisect
  step (`0ea3e0b196`, `0337b8129c`) stay out.
- Display, `0058–0059`: DPU bandwidth from the state being checked
  (`480ba24aa3`); DP debugfs connector pointer (`c2f772ec52`).
- Clocks, `0060–0062`: rcg2 force-enable handling (`d4e8c6b9ae`,
  `8c0f93e10f`); Lucid Ole PLL status checked before configuring
  (`eb34e2804c`; Glymur's GCC and video clock controllers use it).
- `0063` PCIe: `-ENODEV` ignored after a Root Port reset (`bea2ff3b9d`).
- USB-C, `0064–0065`: UCSI skips the CAM query when a partner has no alt modes
  (`7c590f0716`), and sets `ucsi->connector` before notifications are
  enabled (`5b4b83c2ff`, N).
- SPMI, `0066–0067`: pmic-arb's multi-bus registration returns 0
  (`82f4c1948a`), and the `of_node` reference is held (`f7aa9de4f2`).
- Wi-Fi, `0068–0070`: ath12k TX DMA address truncation, stale skb pointers,
  DMA unwind (`979ecb88ed`, `6c40719489`, `4de5a8a0ed`).
- `0071` cpufreq stats out-of-bounds access (`8a70298967`).

Not taken: interconnect `e0667aa9c6` and UCSI `b8320a8b56`, which need earlier
changes the base lacks; Iris fixes (Iris is off); fixes for other SoCs.

From the laptops tree (posted by Qualcomm, not yet accepted), `0072–0075`,
Glymur SoC device-tree fixes: the USB controllers' missing `hs_phy_irq` and
the HS-only controller's swapped DP/DM interrupts (`eab4913e40`, Krishna
Kurapati); the HS-only controller (the camera's) clocked at its 60 MHz
LOW_SVS point instead of 200 MHz (`29a70f3d23`, Konrad Dybcio); the PCIe root
ports' `t-power-on-us` for L1.2 exit (`77e3c2981a`, Krishna Chaitanya
Chundru); names for the domain idle states (`0dde75ce87`, Maulik Shah). Not
taken from there: the `HACK: eusb2_hack` commit (it forces the eUSB2 path in
dwc3-qcom; no evidence it bears on the USB-C full/low-speed `-71`), the
Glymur DP PHY series (USB-C SuperSpeed shares that PHY; it needs a test of
its own) and the videocc sleep clock (no functional change).

`glymur-bringup/0004` (new for `-19`, not for upstream) extends `0003`'s
Iris diagnostics with `diag_hw_core` and `diag_pwr_ctl` for the Mahua video
trials (`docs/video-iris-windows-2026-11-06.md`).

Every patch applies with no fuzz on the new base (61 commits). The headset
codec of `-19`'s test device tree needs nothing beyond the base: qcom-next
now carries the WCD9378 SDCA driver, the Glymur LPASS clock controllers,
SoundWire multi-lane support and the RX/TX macro and `swr1`/`swr2` nodes
(`docs/kernel-19-plan-2026-11-05.md`).

Upstream check of 2026-10-23 (no build yet). qcom-next is still
`1a0586064ee1` and mainline still `v7.3-1703-ga804c5742b`, so the base
stays. linux-next `next-20261020` (`8f7df005a756`) now carries
`backports/0013` and `0017–0021` as accepted commits, identical to the files
here (`26f6187879d9`, `8f3f88309fa4`, `6c51f09c6db5`, `63b269ec537d`,
`707ce1025214`, `9db31edf92dd`); they stay until qcom-next has them. Of its
other commits in drivers this laptop uses, these fixes are taken as
`backports/0027–0040`, in linux-next order:

- `0027–0029` drm/msm/a6xx: the A8x bandwidth vote honours `perfmode_bw`
  (`db6a2e4a7ebd`), the secondary rail is voted from the chosen primary
  corner (`128a0edde507`), and the GMU dependency votes are resolved against
  the GPU's OPP table (`eab0aff8965e`). Akhil P Oommen, through msm-next;
  they apply to every A8x GPU, the X2-85 included. The rest of that series
  (BX rail, MX clamp) is for Hawi and not taken.
- `0030` drm/msm: vm_bo use-after-free in `with_vm_locks()`
  (`81878aa1a2f5`, Cc stable).
- `0031` drm/msm/dp: no link-training success after a reinit
  (`a47987366e7f`): when every attempt fails, the stream was enabled on an
  untrained link, the failure mode of `-15`'s DisplayPort crash. DisplayPort
  stays off; this is for when it comes back.
- `0032` qcom_battmgr: announce charger online changes found in the status
  response (`87fd20da8ca8`, Cc stable). The X1E80100 variant, which Glymur
  uses, gets no firmware notification for the AC and USB supplies, so UPower
  kept the state it read at boot. `0023` stays: it listens for a
  notification that never came in its one test here, and the two do not
  overlap.
- `0033–0034` pmic_glink: the altmode worker no longer runs while devices
  are suspended (`c7c56b6ec077`, Cc stable), and an early rpmsg probe is no
  longer lost (`0c79a829af36`), which left USB-C and the battery without
  pmic_glink clients.
- `0035–0036` qcom_scm: an empty PAS resource table and the retry size
  (`324103eb65ba`, `57e43df2e426`; ADSP and CDSP boot through it).
- `0037–0039` AudioReach: `g_apm` cleared on removal (`be2172758f2b`), and
  the q6apm-dai position wraps to 0 for a full ring and resets with the
  fragment queue on prepare (`0ea3e0b196f9`, `0337b8129cf6`, both Cc
  stable). The speakers and microphones run through q6apm-dai.
- `0040` qcom_battmgr: a full battery on external power reports `Full`
  instead of `Not charging` (`6c8098e04ee4`, Bjorn Andersson). Ported: the
  declaration hunk needed one line less context, because qcom-next's
  multi-port USB-C patch declares `property` beside it; code unchanged.

The ported files compile with `W=1` and no warnings against the `-16`
configuration, and a fresh `prepare` reproduces the tested tree
(`ab8ab104`). Not taken:

- `93b6c8d10fad` "drm/msm/a8xx: Enable CLX feature on Adreno X2-85", in
  linux-next. The laptops tree reverts it (`c9f622e03e71`, Abel Vesa): with
  the CLX tables sent, the GMU stops answering on the Glymur CRD, the
  Zenbook A14 and the Yoga Slim 7x. When qcom-next takes it, carry that
  revert.
- The Qualcomm TPM driver (`tpm: Introduce Qualcomm TPM driver` and the
  `qcom.tz.tpm` TEE service, v4, reviewed by Jarkko Sakkinen; laptops tree,
  not in linux-next). It is the TPM Windows uses for BitLocker, so it waits
  for the owner's decision.
- The TEE-based EFI variable driver (laptops tree): UEFI writes wait for a
  stable system.
- dwc3-qcom suspend and VBUS changes (Faisal Hassan, laptops tree, not in
  linux-next): suspend is masked.
- `f7c62ebfd912` (X1E80100 capacity): qcom-next already lists it.
  `a49f86cd1333` (USB type) is for the SM8350 variant only. The a6xx GMU
  wrapper fixes (`8128ae7af6b4`, `e2f57c576f14`) are for GPUs without a
  GMU. The Iris changes wait for Iris to be enabled again.
- The PMIC BCL hwmon driver, the LPASS reset and video clock binding fixes,
  and the laptops tree's `HACK:` commits.

The eDP backports (`0001–0002`, `0026`) match the laptops tree's (the same
revisions, rebased); `0014`, `0024` and `0025` are identical to it.

Before building `-17` (2026-10-23): qcom-next still `1a0586064ee1`;
mainline moved to `v7.3-4514-g2a08195e4d` (the 7.4 merge window). It
merged four of `0027–0040` (`0033–0036`) and adds three fixes taken as
`backports/0041–0043`: Glymur's USB controllers marked `dma-coherent`
(`e62df36f34`), the USB controllers' missing clock rates, performance
level and interconnect votes (`0f8d35f04a`; both Greg Ociepka, `Fixes:` the
Glymur USB nodes), and the PMIC temperature alarm's `temp_map` indexing
(`51c262cf2a`, Georgi Djakov). Not taken: `eca1247443` (TSENS limits
widened to the hardware range; no fix), the Glymur SD-card and PCIe3
nodes (not on this laptop), and SCMI's ACPI transport.

Base move for `-18` (2026-10-23, `docs/kernel-18-plan-2026-10-23.md`):
qcom-next was rebuilt on 7.3-rc6 (1869 commits since `1a0586064ee1`). It
carries `backports/0018`, `0019` and `0021`, so they are dropped, and
Qualcomm's GPR probe-race fix (FROMLIST, "soc: qcom: apr: Publish GPR
callback before client probe"), which explains the `[1001021]` timeout at
boot. It also carries `cb97bf3d4f` without mainline's follow-up
`8cb5c17be3` ("i2c: qcom-geni: Restore the source-clock selection policy",
Abel Vesa; it fixes I2C HID failures `cb97bf3d4f` caused on the X1E80100
CRD), taken as `backports/0046`. `upstream/qcom-next-acpi/0003` and
`glymur-bringup/0002` are refreshed for the new context (two `#define`s
next to their comment); ACPI controllers still take their timing from the
`CLKD` table and fall back to the clock lookup only without a row.
`backports/0038–0039` are dropped as a bisect step: the audio DSP stall of
`-17` is new, and they are the q6apm stream changes it could involve. Every
other patch applies unchanged, and a fresh `prepare` reproduces the tested
tree (`7a96eb38`).

Also for `-17` (the owner allowed UEFI variables on 2026-10-23):
`upstream/qcom-next/0009`, "firmware: qcom: scm: Allow QSEECOM on HP
OmniBook 5 16", the one-line allowlist entry every Snapdragon X laptop gets
upstream (HP's EliteBook X G2q as `665d237915`), and
`CONFIG_EFI_VARS_PSTORE_DEFAULT_DISABLE=y` in the build, so the EFI pstore
backend never writes crash logs into the variable store. Reads only for now
(`docs/uefi-variables-2026-10-23.md`). An upstream candidate.

Also for `-17`: `upstream/qcom-next/0008`, "ASoC: qcom: topology: size a
module's configuration in bytes". Topology module configuration carries its
length in bytes and is sent as such, but the parser allocated and copied
that many `__le32` elements, reading three times the length past the
configuration. The fix sizes it in bytes, refuses a configuration that runs
past the widget's private data and has the caller check the error
(`Fixes: c7ed4c2debfd`). linux-next of 2026-10-20 has the same code, so it
is an upstream candidate; the speaker filter topology
(`docs/audio-speaker-eq-2026-10-23.md`) is its first user here.

Also for `-17`: `glymur-bringup/0003`, "media: iris: bring-up diagnostics
for Mahua's core and pipe check". HP's video firmware refuses Glymur's
core and pipe settings against its fuse word
(`docs/video-iris-fuse-2026-10-23.md`). Three module parameters, all off by
default, try the alternatives on one boot: `qcom_iris.diag_cores` (cores
to power, load time only), `diag_pipes` and `diag_core_id` (per session),
and the efuse word and core power status are logged once the firmware
boots. `check-video.sh --diag` runs the trials. Not for upstream: the
result becomes Mahua platform data.

qcom-next stays the base. The Linux MSM laptops kernel
(`https://github.com/linux-msm/laptops-kernel`, `topic/glymur-laptops`) was
evaluated on 2026-10-17 as an alternative and not taken: it is a
community staging tree on linux-next, its Glymur branch has no CI, and it
carries hacks and unposted patches. Fixes from it are ported one at a time,
each checked first (`docs/community-pointers-2026-10-17.md`).

Base move for `-8` (2026-09-30): the 52 new qcom-next commits are all
Nord (Ethernet, display, eDP PHY, an ADSP remoteproc flag). The ones in
drivers we use (`dp_display.c`, `qcom_q6v5_pas.c`, the QMP v8 header) only
add or rename Nord entries, and no Glymur/Mahua device tree changed. The
one collision is `phy-qcom-edp.c`: the Nord eDP PHY series replaced the `is_nord` branches with
optional `phy_ver_ops` hooks (`phy_tx_lane_cfg`, `phy_tx_res_cfg`) and
`phy_status_reg`/`bias1_en_2lane` config fields, so `backports/0001–0002`
were re-ported: a three-way merge of our `-7` file with the new base, the
same three conflicts resolved in both patches, and the v46 callbacks now
use those hooks. The v8 (Glymur) code is unchanged: the new `0002` delta
is byte-identical to the `-7` one. Every other patch applies unchanged.
After `-8` was built, the comments in `upstream/qcom-next/0002` and `0003`
were shortened (no code change); `-8`'s source differs from a fresh
`prepare` only in those two comments.

`upstream/mainline/0001`–`0005` were sent upstream on 2026-09-30; `0004` and
`0005` are the mainline forms of `upstream/qcom-next/0001` and `0002`. qcom-next was
fetched again before `-6` (2026-09-29) and before `-7` (2026-09-30): its
tip is still `e428097a36d`. Mainline (v7.3-rc5+37 on 2026-09-30) and
msm-next (`d33622598496`, 2026-09-26) have nothing new for these drivers,
and neither changes how msm reports GMEM.

1. `ACPI: GED: Support GpioInt event resources`: lets GED devices use
   `GpioInt` resources, which is what lid and EC event interrupts use on
   these laptops. Applies to mainline too.
2. `dmaengine: qcom: gpi: add ACPI support for the Glymur GPI engine`:
   `QCOM0F88` match data plus `gpi_acpi_request_chan()` for `_DEP` clients.
3. `i2c: qcom-geni: support firmware-owned ACPI controllers (QCOM0F10)`:
   - `CLKD` timing;
   - ACPI child bus speed;
   - a firmware-state gate;
   - wrapper-free FIFO depth;
   - GSI transfers through the `_DEP` GPI engine.
4. `gpio: add an interim Glymur ACPI TLMM driver (bring-up)`: a standalone
   OpenBSD-style driver with PDC translation. It is default-off and touches
   only pins named on the command line. The upstream route is
   `drafts/0002` (pinctrl-glymur ACPI match) plus `drafts/0003` (PDC
   translation in the GPIO ACPI core).
5. `i2c: qcom-geni: bring-up allow-list for firmware-owned controllers`:
   binds only the MMIO bases listed in `i2c_qcom_geni.acpi_buses`; the
   default binds none.

`upstream/qcom-next/`:

- `soc: qcom: pmic_glink_altmode: acknowledge notifications on undescribed
  ports`. The driver enables the firmware's USB-C port notifications but
  acknowledged only those for ports with a connector node. On this laptop
  an unacknowledged one left the firmware reporting no connection on
  either port (`docs/usb-c-ports-2026-09-29.md`). Notifications for other
  ports are now acknowledged from a work item. Not ACPI- or board-specific.
- `drm/msm/a8xx: report the GMEM size of the active slices`. msm reports
  the catalog GMEM size for all slices even when some are fused off;
  Qualcomm's KGSL reports `gmem_size / slices × active slices`, and msm now
  does the same when it reads the slice mask. Not board-specific. On `-7`
  it cleared the corruption here (`docs/gpu-corruption-2026-09-30.md`,
  `glmark2` 11570), but only because this Mahua X2-85 ran with Glymur's
  X2-90 entry (21 MB, 4 slices); the real fix for this chip is
  `backports/0013–0014`, which make this patch a no-op here
  (`docs/mahua-gpu-2026-09-30.md`).
- `phy: qcom: eusb2-repeater: check the parent PMIC before using it`. For
  the SMB2370, the repeater driver checks that its parent PMIC reports the
  SMB2370 subtype before registering the PHY, and logs what it found. A
  board device tree places repeaters by SPMI slave ID; this makes a wrong
  placement refuse instead of writing to another PMIC. It lets the USB
  test DT declare the reference design's repeaters
  (`docs/eusb2-repeater-2026-09-30.md`). Generic.
- `dt-bindings: embedded-controller: add HP OmniBook 5 16 EC` and
  `platform: arm64: add HP OmniBook 5 16 embedded controller driver`
  (from `-9`). Board-specific, but upstreamable like the other
  `drivers/platform/arm64` EC drivers: hwmon for the fan speed and four
  thermistors, the mute LEDs, the keyboard backlight timeout and the F9/F11
  hotkeys, over HP's EC mailbox and event line
  (`docs/ec-2026-09-30.md`). Unproven until `-9` boots.

Backports (`backports/`), from Bjorn Andersson's "phy: qcom: edp: Update v8
programming sequence" v1 (linux-arm-msm, 2026-06-22,
`20260622-glymur-edp-phy-v1-0-814b45089ac9@oss.qualcomm.com`; reviewed by
Konrad Dybcio, not merged as of qcom-next `a47c4c5aa`):

- `phy: qcom: edp: split power-on sequencing by PHY version`;
- `phy: qcom: edp: update v8 power-on programming sequence`.

The series says the v8 PHY's PLL does not lock at 1.62 or 2.7 Gb/s
without it. This panel's maximum is 2.7 Gb/s, and its power-on fails with
`-110` at both rates, consistent with that. The series has not yet been
shown to train a link at 2-lane 2.7 Gb/s. The series is written against mainline. The backport resolves it
against qcom-next's Nord PHY support: Nord keeps its existing sequence
through the `_v46` callbacks, and Glymur's v8 code is exactly the posted
code. See `docs/edp-phy-backport-2026-09-29.md`.

`backports/0003`: "drm/msm/dp: skip PUSH_IDLE when the link was never
enabled" (Jesse Casco; mainline `e249a6e2a1`, 7.3-rc4). On X2 Elite a
PUSH_IDLE write into a DP controller whose link never came up makes
TrustZone force-stop the SoCCP/ADSP and silently reset the SoC. qcom-next's
MST rework moved that write into `msm_dp_ctrl_push_vcpf()`, so the guard is
ported onto `->link_ready` (see the patch's backport note).

`backports/0004–0012`, mainline 7.3-rc3..rc5 fixes that qcom-next
`e428097a36d` lacks, cherry-picked unmodified:

- drm/msm: `ea9dadeac7` fbdev framebuffer as system memory; `6fbbf1e152`
  Adreno autosuspend cleanup; `58995b11df` DP link bandwidth with wide bus;
  `a5b5cc9099` DPU pending peripheral flush; `ba970587a0` longer GMU
  firmware init timeout; `01c8d1f385` RCU-free ring and VM objects;
  `b7c0f8436f` check PAS only when a zap shader is present (the Glymur
  GPU has none).
- `4e93c65f87` Bluetooth: hci_qca: no serial writes after close.
- `268aacb2e2` i2c: qcom-geni: release DMA channels on probe error.

`backports/0013–0014`, from Qualcomm's "drm/msm: Mahua GPU support" v1
(Jie Zhang, posted by Akhil P Oommen, 2026-09-25,
`20260925-mahua-gpu-v1-0-0fa0bfd8d315@oss.qualcomm.com`; reviewed by Konrad
Dybcio and Abel Vesa; not in qcom-next, msm-next or linux-next as of
2026-09-30), patches 3 and 5 with the reviews collected:

- `drm/msm/a8xx: Add Mahua GPU support`: the Adreno X2-85 catalog entry
  (chip `0x44060000`, 3 slices, 15.75 MB GMEM, its own GMU chip ID). One
  context line differs in qcom-next (the A830 clock-gating check); the
  patch's note records it.
- `arm64: dts: qcom: mahua: Support GPU and GMU`: the Mahua GPU and GMU
  compatibles in `mahua.dtsi`.

Until these, every Mahua board ran its GPU as Glymur's X2-90, whose 21 MB
of GMEM caused the corruption `upstream/qcom-next/0002` worked around
(`docs/mahua-gpu-2026-09-30.md`). Patches 1, 2 and 4 (Glymur's GMU
compatible, bindings) are not needed here. Drop both when qcom-next has the
series. They need Mesa with chip `0x44060030` (main from `d09fa965`), which
`build-mesa-glymur.sh` builds.

`backports/0015–0016` (from `-12`), the dwc3-qcom crash on USB-C role
switches (`docs/usb-dwc3-crash-2026-09-30.md`):

- `Revert "usb: dwc3: qcom: Add support to skip phy management by USB
  core"` (Krishna Kurapati; `usb-next` `bb4f62bfaa`, 2026-09-09), applied as
  the revert of qcom-next's FROMLIST copy `d90fb648965d`. The reverted patch
  added a managed software node on every probe attempt: duplicate
  `software_node` warnings at boot and a use-after-free on role switch.
- `usb: dwc3: qcom: Add support to skip phy management by USB core`, the
  replacement (posted 2026-09-14, acked by Thinh Nguyen, not merged), which
  passes the quirk through the dwc3 core's properties.

Drop both when qcom-next has the revert.

Dropped in `-13`: qcom-next `1a0586064ee1` has both. `backports/0003–0012`
are dropped from `-13` too: qcom-next `1a0586064ee1` has all ten.

`backports/0017–0021` (from `-13`), mainline fixes after 7.3-rc4 that
qcom-next `1a0586064ee1` lacks, cherry-picked unmodified:

- `8f3f88309f` clk: qcom: gpucc-glymur: the GPU CX GDSC is votable (no
  power-off polling; status from the GDS hardware control register).
- `6c51f09c6d` usb: typec: ucsi: map connectors to DT nodes by `reg`, not
  by child order.
- `63b269ec53` usb: typec: ucsi: glink: use-after-free of ucsi on remove.
- `707ce10252` drm/dp: don't mark the AUX backlight enabled when enabling
  failed (the eDP panel's backlight is DP AUX).
- `9db31edf92` remoteproc: qcom_q6v5_pas: error masking in
  `qcom_pas_stop()` (ADSP/CDSP).

`backports/0023–0026` (from `-13`), from the Linux MSM laptops kernel
`topic/glymur-laptops` (`c9f816899dc2`). None is accepted upstream; each was
checked against its source and this laptop's evidence first:

- `0023` power: supply: qcom_battmgr: refresh on Glymur state
  notifications (Tyler Baker, laptops `e341ce20c59b`; not posted, from the
  ASUS Zenbook A16). Glymur firmware reports plug and unplug as a
  notification from pmic_glink owner 32782, which no client registers; the
  patch registers it and signals a change on the supplies. Ported: one hunk
  moved past qcom-next's `qcom_battmgr_battery[]`; code unchanged. It only
  adds change events: in the `-6` charging run the battery tracked every
  plug while `qcom-battmgr-ac`/`-usb` stayed `ONLINE=0`, and that value is
  not something this patch changes. To verify: the function tracer on
  `qcom_battmgr_state_callback` during plug and unplug.
- `0024` dmaengine: qcom: gpi: order ring memory against register access
  (Tyler Baker, laptops `2c82b3799713`; not posted). Doorbell and event
  read-pointer accesses become ordered `readl`/`writel`. Its failure was on
  `a84000.i2c`, the controller of this laptop's EC.
- `0025` dmaengine: qcom: gpi: Set IEOB on linked I2C GO TRE to retire TX
  descriptor (Vsevolod Nevorotov; posted 2026-09-09). Fixes TX ring
  exhaustion after `656147fb1d4c`, which qcom-next has. The EC driver's
  register reads (`i2c_smbus_read_byte_data`, about six a second while the
  EC interrupt fires) take that path.
- `0026` fixup! phy: qcom: edp: update v8 power-on programming sequence
  (Abel Vesa, laptops `240662d141e2`). Ends the v8 PCS setup with
  `DP_PHY_CFG_1 = 0x0f` instead of `0x2f`, as Konrad Dybcio asked in his
  review of Bjorn Andersson's v1 ("bit(5) is for built-in selftest only");
  Qualcomm's QMP-combo DP PHY v8 series also writes `0x0f`. Applies on top
  of `backports/0002`; drop both when the eDP series lands in qcom-next.

Still not taken: `cb97bf3d4f` "i2c: qcom-geni: Fix hardcoded clock index in
SE_GENI_CLK_SEL" (7.3-rc5, Cc stable, so qcom-next will pick it up). Its
conflict with `qcom-next-acpi/0003` is context only and is resolved in a
port kept in `.work/`; ACPI controllers with a `CLKD` row keep index 0 as
before. The open question is the device-tree path: the Glymur QUP clocks
are DFS, so the rate table the fix searches for an exact 32 or 19.2 MHz
level comes from the hardware, not from the `F()` list in `gcc-glymur.c`
(which has both). Without one, probe fails for every DT I²C controller,
keyboard and EC included. `glymur-boot-report.sh` now records each active
QUP clock's rate, which shows the level that index 0 selects today.

The series was verified to reproduce the build tree exactly, except for
those two board defaults, which moved to the board's command line.

## Mainline series (`upstream/mainline/`)

These apply to mainline `fd179f8a05` (7.3-rc5 era) and compile cleanly with
`W=1`; `0005` applies to msm-next. All five were sent upstream on 2026-09-30.

1. `ACPI: GED: Support GpioInt event resources`: the same code as
   `qcom-next-acpi/0001`. Withdrawn on 2026-10-01: ACPI 6.6 section 5.6.9.2
   allows only Interrupt resources in a Generic Event Device, and mainline
   has no ACPI driver for this laptop's GPIO controller (`QCOM0F0C`), so the
   patch has no upstream user. The device tree handles the lid with
   `gpio-keys`.
2. `soc: qcom: geni-se: don't fail ACPI probe on a missing SE clock`: a
   regression fix; `Fixes: 5b8a39dcf909`. Compile-tested only.
3. `i2c: qcom-geni: release runtime PM reference when set_rate fails`: a
   leak fix; `Fixes: 10e74f4c5046`. Compile-tested only. In mainline as
   `ae8364085574` (v7.3-rc7, through `i2c-fixes`).
4. `soc: qcom: pmic_glink_altmode: acknowledge notifications on undescribed
   ports`: the mainline form of `upstream/qcom-next/0001`, tested here.
5. `drm/msm/a8xx: report the GMEM size of the active slices`: the first
   version. The second, with the expression parenthesized on one line and
   the text reworded without this laptop, is the form carried as
   `upstream/qcom-next/0002`. The second version is in msm-next as
   `efbda69d92e6` (2026-10-10), on its way to the next merge window.

Sent on 2026-11-09, on `next-20261105`, to the ARM64 platform-driver
maintainers: the HP EC binding and driver (`upstream/qcom-next/0004–0005`),
as "platform: arm64: HP OmniBook 5 16 embedded controller" v1
([Patchwork](https://patchwork.kernel.org/project/platform-driver-x86/patch/20261109104914.1534-2-theflyingrahul@gmail.com/)).
The upstream form adds a MAINTAINERS entry, places the Kconfig and Makefile
lines among linux-next's newer EC drivers, and corrects the commit text (the
driver reads events from register `0x00`). It builds with `W=1` and passes
`checkpatch --strict` and `dt_binding_check`. Held: the board series
(`hp,omnibook-5-16-bf1xxx`, the QSEECOM entry `upstream/qcom-next/0009`, the
board DT), because `dtbs_check` asks for the PCIe, USB and TCSR supplies
that the board DT does not declare yet.

## Drafts and archive

- `drafts/0002`, `drafts/0003`: the pinctrl-msm route to ACPI GPIO with PDC
  translation. They compiled in an isolated worktree but were never booted.
- `archive/0005`: the default-off `QCOM0F10` register inspection path, which
  the out-of-tree modules have superseded.

None of these patches carries a `Signed-off-by`; add it when submitting.

## Old flat numbering (used by dated reports before 2026-09-27)

| Old path under `patches/kernel/` | Now |
|---|---|
| `0001-soc-qcom-geni-se-acpi-missing-se-clock.patch` | `upstream/mainline/0002` |
| `0001-i2c-qcom-geni-reject-missing-se-clock.patch` | Removed on 2026-09-26; see the audit |
| `0002-pinctrl-qcom-glymur-draft-acpi-match.patch` | `drafts/` |
| `0003-gpio-acpi-glymur-pdc-translation-rfc.patch` | `drafts/` |
| `0004-i2c-qcom-geni-balance-pm-on-rate-error.patch` | `upstream/mainline/0003` |
| `0005-i2c-qcom-geni-glymur-acpi-inspect-rfc.patch` | `archive/` |
| `0006-ACPI-GED-Support-GpioInt-event-resources.patch` | `upstream/qcom-next-acpi/0001` |
| `0007-glymur-acpi-gpi-and-geni-i2c-wip.diff` | `upstream/qcom-next-acpi/0002`, `0003`, plus `glymur-bringup/0002` |
| `0008-glymur_acpi_gpio-intree-wip.c` | `glymur-bringup/0001` |
