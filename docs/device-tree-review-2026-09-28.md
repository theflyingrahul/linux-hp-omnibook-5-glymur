# HP OmniBook 5 16-bf1xxx Device Tree: Review, September 28, 2026

This review rechecked every assumption behind the first device tree
(`docs/device-tree-evidence-2026-09-27.md`, commit `addd317`) before its
first boot. Five of them were wrong, and three of those would have hurt the
first DT boot. The DTS is now `dts/qcom/mahua-hp-omnibook-5-bf1xxx{.dtsi,.dts,-minimal.dts}`
and ships in kernel `7.3.0-rc2-glymur-3`. The `-2` package has the old
DTBs and must not be used for a DT boot.

## Findings

| # | Assumption in `addd317` | What the evidence shows | Effect on a DT boot | Fix |
|---|---|---|---|---|
| 1 | The die is Glymur with cluster 2 fused off | **Mahua.** HP's DSDT serves both dies and switches on `\_SB.SDFE`, which is **0xA8** here. For 0xA8 it disables the "CPU Cluster 2" (`TZ2`) and "QMX2" (`TZ5`) thermal zones and the cluster 2 limits policy (`TZ19`), which is exactly what `mahua.dtsi` deletes. It also gives `GPU0` its `MHID`, `QCOM0FF5`; 0xA1 would give `GHID` `QCOM0F36`. Windows binds `ACPI\VEN_QCOM&DEV_0FF5` ("Adreno X2-85"). | Wrong interconnect topology (Mahua has its own NoC compatibles), wrong TLMM wake map, wrong TCSR, and TSENS 6/7, which Mahua lacks | Base the board on `mahua.dtsi`, which includes `glymur.dtsi` and removes cluster 2, TSENS 6/7 and PCIe 3a |
| 2 | Every unused TLMM pin is reserved | The TLMM has **251** pins (`pinctrl-glymur.c`, `ngpios`), not 250. `<155 95>` left GPIO 250 unreserved. | One pin outside the allow-list | `<155 96>` |
| 3 | The enabled pins are only the board's own | `glymur.dtsi` enables `uart21` (debug UART, GPIO 86/87) by default. Both pins were reserved. | `uart21` fails to probe | `&uart21 { status = "disabled"; }` |
| 4 | `&gpu { status = "okay"; }` enables an optional GPU | `glymur.dtsi` already enables the GPU, GMU, `gpucc` and `gxclkctl`, in both DTs. msm adds an available Adreno node as a **component of the display DRM device** (`add_gpu_components`, unless `msm.separate_gpu_kms`), and the GPU clock drivers build only with `CLK_GLYMUR_GPUCC`, which is unset. | **The display device never binds: dark panel** on the full DT | Disable `&gpu` and `&gmu` in this stage |
| 5 | The minimal DT keeps the firmware framebuffer | `dispcc` (enabled by default, a module) reprograms display PLL0/PLL1 at probe. With no MDSS consumer, its genpd `sync_state` powers off the MDSS GDSC, and `pd_ignore_unused` does not stop that path (`of_genpd_sync_state`). | Minimal DT loses the firmware display | `&dispcc { status = "disabled"; }` in the minimal DT |

Other findings:

- **GRUB template.** The DT entries ended in `exit 1` when no DTB was
  installed. GRUB's `exit` leaves GRUB for the next UEFI boot entry
  (Windows). Removed: GRUB now shows an error and returns to the menu.
- **"Generated and checked by script" was not true.** No script was checked
  in. `scripts/linux/check-dt-gpio-allowlist.py` now reads a DTB and
  verifies two things: every pin an enabled node uses is unreserved, and
  every other pin is reserved. `build-qcom-next-glymur.sh` refuses a DTB
  that fails. Run on the `-2` DTBs, it reports GPIO 86/87 and GPIO 250.
- **The earlier Glymur argument.** GPIO 144 (`pcie3a_clk`) being driven by
  PEP, and the 18-entry MADT, come from firmware tables shared by both dies,
  so they do not identify the die. GIO0's static wake table (`CIPR`) also
  matches Glymur rather than Mahua (PDC pin 159: GPIO 143 against 155), but
  that table is equally static and shared. `SDFE` is the value the
  firmware's own code branches on, and Windows follows it.

## Values now confirmed from HP's firmware

- **PERST#: 146 (PCIe 4) and 152 (PCIe 5).** `\_SB.QPPX` (`QCOM0F96`,
  "PCIe Platform Extension Plugin", bound in Windows) lists one PERST#
  `GpioIo` per root port, PCI0–PCI7 in order: –, –, –, 143, **146**,
  **152**, 149, 155. The pins have no pull.
- **WAKE#: 148 and 154.** `PCI4._CRS` has a wake `GpioInt` on ACPI pin 384
  and `PCI5._CRS` on pin 448: edge, active-low, pull-up, wake-capable. GIO0
  maps PDC slots 6 and 7 to GPIO 148 and 154.
- **Controllers.** ACPI `PCI4` is at `0x78000000` and `PCI5` at `0x7a000000`,
  the DBI bases of DT `pcie4` and `pcie5`.
- **CLKREQ#.** PEP drives 147 and 153 with function 1 (`pcie4_clk_req_n`,
  `pcie5_clk_req_n`) and a pull-up.
- **Qualcomm reference.** The Glymur/Mahua CRD (`glymur-crd.dtsi`, which
  `mahua-crd.dts` uses) routes the same pins, and HP's DSDT carries
  `PSUB` "CRD08480".
- **eDP pins.** PEP `GPU0` drives 70 and 18 as high outputs at 16 mA
  (with a pull-up, which is harmless on a driven output) and 119 on
  function 1, `edp0_hot`.

The PERST#/WAKE# pins no longer need the snapshot module before a DT boot.

## Other checks that passed

- **SoC description.** Both DTBs compile with `W=1`; the only warning is in
  `glymur.dtsi`. They have 12 CPUs: `oryon-2-2` at 0x0–0x500 and `oryon-2-1`
  at 0x10000–0x10500, matching the MADT and MIDRs. The TLMM, TCSR and NoCs
  use the `qcom,mahua-*` compatibles, and PCIe 3a and TSENS 6/7 are absent.
- **Pin functions.** Every function the DTS names exists on that pin in
  `pinctrl-glymur.c`: `pcie4/5_clk_req_n`, `edp0_hot`, the `qup0_se0/4`,
  `qup1_se0/6` groups.
- **Root path, built in.** GCC, TCSR, TLMM, the interconnects, RPMh/rpmhpd,
  `rpmhcc`, cmd-db, PDC, both SMMUs, the GIC ITS, `PCIE_QCOM`, the QMP PCIe
  PHY, NVMe and ext4. `gcc_disp_ahb` and `gcc_disp_hf_axi` are critical
  clocks.
- **GRUB and boot mode.** The USB's `$cmdline` already adds
  `clk_ignore_unused pd_ignore_unused` on Snapdragon, and GRUB lockdown is
  off (our unsigned kernel boots), so `devicetree` is allowed. The kernel
  starts at EL2 (17 logs), which is how `glymur.dtsi` and the ASUS Zenbook A16
  use the remoteprocs.
- **Bluetooth.** With `enable-gpios`, `hci_qca` drives BT_EN itself;
  QCC2072 needs no regulators, and `swctrl` and the clock are optional. It
  loads `qca/ornbtfw<rom>.tlv` and `qca/ornnv<rom>.b<board>`. HP's INF
  installs `clnbtfw10.tlv` and `clnbtnv10.b03/.b07/.b08/.b0a/.b0d/.b17/.bin`
  at 3.2 Mbaud, and `install-firmware.sh` renames them to match.
- **Battery, AC, UCSI, RTC.** On Glymur/Mahua these run over PMIC GLink on
  the **SoCCP**, not the ADSP (`pmic_glink_glymur_data` has no ADSP charger
  domain). The boot firmware starts the SoCCP (`early_boot`), and Linux
  attaches after only reading its interrupt states. HP's driver pack has no
  SoCCP image, consistent with that.
- **eDP.** `qcom,glymur-dp` DP3 at `0xaf6c000`, `qcom,glymur-dp-phy`, DPU and
  MDSS all have drivers. DP0–2 stay disabled. The panel block matches the
  CRD and Zenbook pattern with HP's pins.
- **Other default-enabled blocks.** The ones inherited from `glymur.dtsi` are
  the SoC plumbing the Zenbook A16 (a retail Windows Glymur laptop) also
  runs: clock controllers, NoCs, TSENS, LLCC, SCMI CPU frequency, CoreSight,
  crypto and the watchdog. SPEL writes power limits only when set through
  powercap sysfs. The SPMI buses have no PMIC children.

## Known limits of this stage

- **No USB on a DT boot.** No USB controller is enabled, so the USB-A port,
  USB-C and the UVC camera are absent.
- **No GPU or audio.**
- **Firmware power votes stay up.** `gpucc` and `gxclkctl` are enabled
  nodes without a driver, so rpmhpd's `sync_state` stays pending and the
  firmware's power-domain votes stay in place. This is what keeps the
  minimal DT's framebuffer rail (MMCX) up. Enabling the GPU later must keep
  a vote on MMCX while the firmware framebuffer is in use.
- **Bluetooth UART not yet verified.** The Bluetooth UART's SE must
  already be in UART mode from firmware; the snapshot module can confirm
  this.
