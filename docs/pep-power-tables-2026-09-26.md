# PEP0 Power Tables: Board Rails and GPIOs, September 26, 2026

HP's Windows power engine plug-in tables (`\_SB.PEP0` packages in the DSDT)
describe the board-level power recipe for 38 devices: PMIC rail votes,
PMIC clock-buffer votes, TLMM GPIO writes, GDSC footswitches, clocks and bus
votes, per component F-state, P-state and device D-state. These are the
facts a device tree needs for regulator voltages and power-sequencing GPIOs,
and they come from this machine rather than a reference board.

`scripts/linux/analyze-acpi-pep.py <DSDT.dsl> <out.tsv>` flattens them into
5117 actions. All 888 `PMICVREGVOTE` records are attributed to a device.
The raw TSV stays in `.work/pep-actions.tsv`; the table below lists, per
device, the rails voted on with a non-zero voltage and enable set, and the
TLMM GPIOs written. Rail IDs are HP's `PPP_RESOURCE_ID_*` names without the
prefix (for example `LDO15_B_E0` is LDO 15 on PMIC `B`, `E0` domain).

## Checks against known facts

- I²C engine pins: I2C1 GPIO 0/1, I2C5 16/17, I2C6 20/21, I2C9 32/33,
  IC10 36/37, consistent with the QUP SE pin functions in `pinctrl-glymur.c`.
- PCIe: `PCI4` (Wi-Fi) writes GPIO 147 and `PCI5` (NVMe) GPIO 153, one
  per root port as expected for PERST#; `PCI3` also writes 135, 136 and 144.
- `GPU0` component 0 (display on Qualcomm Windows) drives GPIOs 18, 70
  and 119 high in F0. Their roles (panel power, backlight enable, ...) are
  not yet established.

## Per-device rails and GPIOs (fully-on votes)

```
\_SB.GPU0: LDO15_B_E0=1.800V LDO18_B_E0=1.200V LDO1_C_E1=0.912V LDO1_F_E1=0.880V LDO1_F_E1=0.904V LDO2_F_E0=0.936V LDO2_F_E1=0.880V LDO3_F_E0=0.912V LDO4_C_E1=0.912V LDO4_F_E1=1.200V LDO8_B_E0=3.300V
   tlmm: gpio119=1 gpio18=1 gpio70=1
\_SB.I2C1: 
   tlmm: gpio0=0 gpio0=1 gpio1=0 gpio1=1
\_SB.I2C5: 
   tlmm: gpio16=0 gpio16=1 gpio17=0 gpio17=1
\_SB.I2C6: 
   tlmm: gpio20=0 gpio20=1 gpio21=0 gpio21=1
\_SB.I2C9: 
   tlmm: gpio32=0 gpio32=1 gpio33=0 gpio33=1
\_SB.IC10: 
   tlmm: gpio36=0 gpio36=1 gpio37=0 gpio37=1
\_SB.PCI3: LDO1_C_E1=0.912V LDO1_F_E1=0.904V LDO2_C_E1=1.200V LDO2_F_E1=0.880V LDO3_C_E1=0.936V LDO4_F_E1=1.200V  clkbuf:CLK7_A
   tlmm: gpio135=0 gpio135=1 gpio136=1 gpio144=0
\_SB.PCI4: LDO1_C_E1=0.912V LDO1_F_E1=0.904V LDO2_F_E1=0.880V LDO4_F_E1=1.200V  clkbuf:CLK7_A
   tlmm: gpio147=0
\_SB.PCI5: LDO2_F_E0=0.936V LDO3_F_E0=0.912V LDO4_H_E0=1.200V
   tlmm: gpio153=0
\_SB.PCI6: LDO1_C_E1=0.912V LDO1_F_E1=0.904V LDO2_F_E1=0.880V LDO4_F_E1=1.200V  clkbuf:CLK7_A
   tlmm: gpio150=0
\_SB.PCI7: LDO1_C_E1=0.912V LDO1_F_E1=0.904V LDO2_C_E1=1.200V LDO2_F_E1=0.880V LDO3_C_E1=0.936V LDO4_F_E1=1.200V
   tlmm: gpio156=0
\_SB.SAR1: LDO10_B=1.800V
\_SB.SAR2: LDO10_B=1.800V
\_SB.SDC2: LDO18_B_E0=1.200V LDO2_B_E0=1.800V LDO2_B_E0=3.300V LDO9_B_E0=2.960V
\_SB.UBF0.PRT0: LDO15_B_E0=1.800V LDO2_F_E0=0.936V LDO3_F_E0=0.912V LDO4_C_E0=1.200V LDO4_H_E0=1.200V LDO7_B_E0=3.072V SMPS7_F_E0=1.200V  clkbuf:CLK6_A
\_SB.UBF0.PRT1: LDO15_B_E0=1.800V LDO1_C_E0=0.936V LDO1_H_E0=0.936V LDO2_F_E0=0.936V LDO3_F_E0=0.912V LDO4_C_E0=1.200V LDO4_H_E0=1.200V LDO7_B_E0=3.072V SMPS7_F_E0=1.200V  clkbuf:CLK6_A
\_SB.UBF0.PRT2: LDO15_B_E0=1.800V LDO1_C_E1=0.912V LDO1_F_E1=0.904V LDO2_F_E1=0.880V LDO4_C_E1=0.912V LDO4_F_E1=1.200V LDO7_B_E0=3.072V SMPS7_F_E0=1.200V  clkbuf:CLK7_A
\_SB.UFS0: LDO12_B_E0=1.200V LDO17_B_E0=2.500V LDO1_C_E1=0.912V LDO1_F_E1=0.880V LDO2_F_E1=0.880V LDO4_F_E1=1.200V  clkbuf:CLK7_A,CLK8_A
\_SB.URS0.UFN0: LDO15_B_E0=1.800V LDO2_F_E0=0.936V LDO3_F_E0=0.912V LDO4_C_E0=1.200V LDO4_H_E0=1.200V LDO7_B_E0=3.072V  clkbuf:CLK6_A
\_SB.URS0.USB0: LDO15_B_E0=1.800V LDO2_F_E0=0.936V LDO3_F_E0=0.912V LDO4_C_E0=1.200V LDO4_H_E0=1.200V LDO7_B_E0=3.072V SMPS7_F_E0=1.200V  clkbuf:CLK6_A
\_SB.URS1.UFN1: LDO15_B_E0=1.800V LDO1_C_E0=0.936V LDO1_H_E0=0.936V LDO2_F_E0=0.936V LDO3_F_E0=0.912V LDO4_C_E0=1.200V LDO4_H_E0=1.200V LDO7_B_E0=3.072V  clkbuf:CLK6_A
\_SB.URS1.USB1: LDO15_B_E0=1.800V LDO1_C_E0=0.936V LDO1_H_E0=0.936V LDO2_F_E0=0.936V LDO3_F_E0=0.912V LDO4_C_E0=1.200V LDO4_H_E0=1.200V LDO7_B_E0=3.072V SMPS7_F_E0=1.200V  clkbuf:CLK6_A
\_SB.URS2.USB2: LDO15_B_E0=1.800V LDO1_C_E1=0.912V LDO1_F_E1=0.904V LDO2_F_E1=0.880V LDO4_C_E1=0.912V LDO4_F_E1=1.200V LDO7_B_E0=3.072V SMPS7_F_E0=1.200V  clkbuf:CLK7_A
\_SB.USB2: LDO15_B_E0=1.800V LDO1_C_E1=0.912V LDO1_F_E1=0.904V LDO2_F_E1=0.880V LDO4_C_E1=0.912V LDO4_F_E1=1.200V LDO7_B_E0=3.072V SMPS7_F_E0=1.200V  clkbuf:CLK7_A
\_SB.USB3: LDO15_B_E0=1.800V LDO1_F_E1=0.904V LDO2_C_E0=0.880V LDO2_H_E0=0.880V LDO4_C_E0=1.200V LDO4_F_E1=1.200V LDO4_H_E0=1.200V LDO8_B_E0=3.072V SMPS7_F_E0=1.200V  clkbuf:CLK7_A
\_SB.USB4: LDO15_B_E0=1.800V LDO1_F_E1=0.904V LDO2_C_E0=0.880V LDO2_H_E0=0.880V LDO4_C_E0=1.200V LDO4_H_E0=1.200V LDO8_B_E0=3.072V SMPS7_F_E0=1.200V  clkbuf:CLK7_A
   tlmm: gpio72=1
```

## Not covered here

- Display panel identity and backlight control; audio; battery/charger
  (PMIC GLink on the ADSP); cameras; Bluetooth. These need other evidence.
- Whether each rail is always-on or switched, and which rails are shared
  across devices beyond what the votes show.
- The mapping from HP's rail IDs to Linux RPMh regulator names needs checking
  against the Glymur PMIC topology before any DTS uses them.
