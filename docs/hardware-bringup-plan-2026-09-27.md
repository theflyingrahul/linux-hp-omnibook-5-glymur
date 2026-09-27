# Hardware Bring-Up Plan: GPU, USB-C, Audio, Battery, Bluetooth, Keyboard Backlight

Written from the SSD install (qcom-next boot kernel, first boot — see
`docs/qcom-next-first-boot-2026-09-27.md`). This is a planning document, not
an implementation: every proposed patch below needs the qcom-next kernel
source tree (`~/glymur-build/.work/linux-qcom-next` in WSL, only reachable
from the Windows-side session) for actual authorship, plus a WSL build
validation pass before anything is staged to boot on this laptop. Nothing
here has been coded or tested yet.

**Framing:** none of these are "write a driver from scratch." Per
`docs/upstream-status.md`, GPU/GMU and Audio (LPASS) for this SoC generation
are already merged in mainline (validated on the EliteBook X G2q and
OmniBook Ultra reference boards), and the running kernel's `.config` already
carries `CONFIG_DRM_MSM=m`, `CONFIG_SND_SOC_QCOM=m`, `CONFIG_TYPEC_UCSI=m`,
and `CONFIG_QCOM_PMIC_GLINK=m`. The gap for each subsystem below is
ACPI/board wiring with this HP's specific values — the same shape of work
already done successfully for GENI I²C and the TLMM/PDC GPIO driver
(`patches/kernel/upstream/qcom-next-acpi/`).

**Risk framing (per the owner's ask to prioritize what could damage
hardware):** live `_STA` shows GPU, and both Bluetooth ACPI devices as
firmware-enabled and functioning already (`_STA` 15); firmware is already
sequencing their power rails correctly, so Linux binding a driver to them is
a functionality risk (hangs, blank screen, no radio), not a damage risk. The
one place that deserves real caution is battery/charging, because it is the
only path where a Linux-side driver actually issues commands that could
influence charge behavior, even though those commands go through
Qualcomm's ADSP-mediated `pmic_glink`/`battmgr` protocol rather than direct
register pokes. That work should be last, and should reuse the upstream
Qualcomm driver as-is rather than anything bespoke.

## 1. Keyboard backlight (lowest effort, no hardware risk)

- **Evidence:** `docs/status.md` already establishes the EC (IC10,
  already working over `geni_i2c`) serves HP WMI, which is how keyboard
  backlight is controlled. Live check this session: `CONFIG_ACPI_WMI` and
  `CONFIG_HP_WMI` are **not set** in the running kernel's `.config`
  (`/boot/config-7.3.0-rc2-glymur`), `/sys/bus/wmi/` doesn't exist, and
  `hp_wmi` isn't a buildable module (`modinfo hp_wmi` fails). The DSDT does
  have three `PNP0C14` (ACPI-WMI mapper) devices present.
- **Proposed fix:** enable `CONFIG_ACPI_WMI=m` and `CONFIG_HP_WMI=m` in the
  qcom-next kernel config and rebuild. No ACPI-ID patch or DT work needed —
  this rides entirely on the EC transport that already works. Genuinely a
  kernel-config change, not new code.
- **Risk:** none identified; WMI method calls are the same mechanism
  Windows already uses for this exact feature.
- **Next:** flip the config in `~/glymur-build/.work/linux-qcom-next-glymur`
  (WSL), rebuild with `build-qcom-next-glymur.sh`, confirm `hp-wmi` binds
  and a `leds` class device (or `hp::kbd_backlight`) appears, stage for a
  boot.

## 2. Bluetooth (`QCOM0F6B`, `QCOM0FEA`)

- **Evidence:** both ACPI devices read `_STA=15` (present, enabled,
  functioning) live on this boot — firmware already has the radio powered.
  `CONFIG_BT_QCOMSMD=m` and `CONFIG_BT_HCIUART_QCA=y` are present in the
  kernel config. `docs/hardware.md` documents the combo chip as Qualcomm
  FastConnect C7700 (Wi-Fi 7 + BT 6.0), the same silicon already providing
  working Wi-Fi via `ath12k_wifi7_pci`.
- **Proposed fix:** the same pattern as `glymur_acpi_gpio`/`geni_i2c` —
  write a small ACPI-ID-matching shim (or extend an existing Qualcomm BT
  transport driver's ACPI match table) so `QCOM0F6B`/`QCOM0FEA` bind to the
  existing HCI transport code. Needs the qcom-next source tree to identify
  exactly which driver (`btqcomsmd` vs. a PCI/USB HCI transport riding the
  same die as `ath12k_wifi7_pci`) is the right attach point — not yet
  determined from ACPI evidence alone.
- **Risk:** RF-only; no plausible damage path.
- **Next:** in WSL, `grep` the qcom-next tree for how BT is instantiated on
  the closest reference board (EliteBook X G2q / OmniBook Ultra, which are
  DT-based) to find the right driver, then write the ACPI-match patch.

## 3. GPU (`QCOM0FF5`, Adreno)

- **Evidence:** `_STA=15` live — firmware has it powered.
  `docs/upstream-status.md` confirms GPU/GMU are merged in mainline for this
  SoC. `card0` today is still `simple-framebuffer`
  (`docs/qcom-next-first-boot-2026-09-27.md`); no render node exists.
- **Proposed fix:** the Adreno driver matches through DT
  only — this is the one item on this list that genuinely needs DT
  authorship (regulators, GMU firmware path, interconnect), not just an
  ACPI-ID shim, since `DRM_MSM`/GMU bring-up needs structured resources ACPI
  doesn't carry cleanly. Reference the EliteBook/OmniBook Ultra board DTs
  (already fetched per their manifests) for the shape of the needed nodes,
  then substitute HP OmniBook 5-specific values sourced from this machine's
  ACPI (MMIO ranges, IRQs already visible under `QCOM0FF5:00`).
- **Risk:** low for damage; real risk is a black-screen/hang during bring-up
  since this replaces the display pipeline in use. Test via SSH/serial
  console, not the local display, until confidence is high.
- **Next:** dump `QCOM0FF5:00`'s `_CRS` (MMIO/IRQ) from this boot (not done
  yet this session) and compare against the reference DTs' `gpu`/`gmu`
  nodes in WSL.

## 4. USB-C / PMIC GLink (`USBC000`, `QCOM0F84`, `QCOM0F8E`, `QCOM0F9D`)

- **Evidence:** `USBC000` is `_STA=0` (disabled) live, gated behind
  `PMGK.LKUP`/`LKST` as already documented. `QCOM0F8E` is `_STA=11`
  (enabled and functioning, just hidden from UI) — this is likely the PMIC
  GLink core itself, separate from the USB-C port controller nodes that
  stay gated. `QCOM0F84`/`QCOM0F9D` report no status this boot (empty),
  consistent with being gated the same way as `USBC000`.
- **Proposed fix:** this is a precondition for USB-C, and shares the PMIC
  GLink transport with battery/AC (item 5). `CONFIG_QCOM_PMIC_GLINK=m` and
  `CONFIG_TYPEC_UCSI=m` already exist. Needs the DT-based `pmic_glink`
  node plus a UCSI child node; ACPI alone may not be enough since qcom-next
  matches these DT-only per the existing findings — confirm this in
  the qcom-next tree before assuming it needs DT vs. an ACPI shim.
- **Risk:** low-to-moderate — USB-C PD negotiation is a well-defined
  protocol (UCSI) with its own safety semantics, but getting it wrong could
  mean a port that doesn't negotiate power correctly. Worth validating
  charge behavior carefully once it comes up (do not leave it charging
  unattended on the first few tests).
- **Next:** work out, from the qcom-next source, whether `PMGK.LKUP` even
  needs to be true for Linux to see these devices (it may be a
  Windows-firmware-side gate we can't unlock without DT bringing up the
  same GLink channel qcom-next's DT boards use).

## 5. Battery / AC / RTC (PMIC GLink, `\_SB.PMGK`) — do this last, carefully

- **Evidence:** unchanged from prior findings — `_BST`/`_PSR` route through
  `\_SB.PMGK` over a `GenericSerialBus` region with no Linux handler; the
  RTC (`\_SB.PRTC`) shares the same gap (see the chrony error-storm finding
  in `docs/qcom-next-first-boot-2026-09-27.md`).
- **Proposed fix:** reuse Qualcomm's upstream `pmic_glink`/battery-manager
  driver stack exactly as the reference boards do — this is mediated
  through the ADSP firmware's own charge-management logic, not a
  from-scratch charging-IC driver, which is why this is judged lower actual
  damage risk than it might first appear, but still deserves the most
  scrutiny before trusting it unattended.
- **Risk:** the only item on this list where a wiring mistake could
  plausibly affect charge behavior (even if bounded by ADSP-side limits).
  Validate readings extensively (voltage, current, charge state) against
  Windows' own reported values before trusting any write path (e.g. charge
  limits), and don't leave the laptop charging unattended during early
  tests.
- **Next:** lowest priority to start, but once started, do it slowly and
  cross-check every reading against the Windows-side battery report.

## 6. Audio (speakers, mic)

- **Evidence, newly found this session:** `reference/hp-software/hardware-id-candidates.tsv`
  has real leads — `ACPI\QCOM1044` (matched to
  `qc_cpu_audio_processing_ext_ep8480.inf`) and several **SoundWire**
  (SDCA) function IDs under manufacturer `MAN_0217` (Qualcomm):
  `FUNC_0711`/`ADR_01` (type 04, likely a speaker amp), `FUNC_0714`/`ADR_02`
  (type 02), `FUNC_1316`/`ADR_04` (type 01) — consistent with
  `CONFIG_SND_SOC_QCOM_SDW=m` already in the kernel config. **Caveat:**
  this file is HP's *candidate* driver-to-ID matches from parsing SoftPaqs,
  not a confirmed live Windows PnP enumeration on this exact unit — `QCOM1044`
  does **not** appear in this boot's live `/sys/bus/acpi/devices/` listing,
  so treat it as a strong lead, not a confirmed ACPI ID, until checked
  against live Windows PnP data (`docs/hardware.md`'s existing methodology).
- **Proposed fix:** confirm the SoundWire topology on the Windows side
  first (PnP device tree, `MAN_0217`/`FUNC_*` entries), then match against
  qcom-next's SDCA/SoundWire audio machine driver for the closest reference
  board.
- **Risk:** low for damage (amp drivers default to muted/low gain); the
  main hazard is a loud pop or DC offset on first bring-up — test at
  minimum volume.
- **Next:** this needs a Windows-side PnP confirmation pass before kernel
  work starts, since the ACPI ID isn't confirmed live yet.

## Summary priority order

1. Keyboard backlight (config-only, no risk) — cheapest win.
2. Bluetooth (ACPI-match shim, firmware already enabled, no damage risk).
3. GPU (needs DT authorship, no damage risk, but real hang/black-screen
   risk during testing).
4. Audio (needs a Windows-side confirmation pass first).
5. USB-C / PMIC GLink core (precondition for both USB-C and battery).
6. Battery/AC/RTC (do last, most scrutiny, ADSP-mediated so bounded risk
   but still the one place a wiring mistake could matter).

All of 1–5 need the qcom-next source tree (WSL) for actual patch
authorship; audio also needs a Windows-side PnP check first. None of this
has been implemented yet.
