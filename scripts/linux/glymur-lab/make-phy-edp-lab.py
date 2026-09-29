#!/usr/bin/env python3
"""Generate phy-qcom-edp-lab.c: the pinned qcom-next eDP PHY driver with
display-lab instrumentation for the HP OmniBook 5 16-bf1xxx.

Usage: make-phy-edp-lab.py KERNEL_SRC OUT_DIR

Every edit is an exact text replacement that must match once, so a changed
source tree fails loudly instead of producing a silently different driver.

Added module parameters (all 0644, read at use, so they can change between
link-training attempts without reloading):
  lab_table     0 auto (driver default), 1 eDP swing tables, 2 DP tables
  lab_ssc       -1 auto (DPCD downspread), 0 off, 1 on
  lab_uefi_tx   1: in set_voltages, write the firmware's TX drive, emphasis
                and LDO values captured at probe instead of the tables
  lab_uefi_misc 1: after power-on, restore the firmware's polarity, drive
                offset, resistor codes and TX band
  lab_fw_pll    1: after the driver programs the PLL, overwrite the rate-
                dependent v8 PLL registers with the firmware's values
                captured at probe (the firmware's PLL locks; the driver's
                does not, "phy poweron failed --> -110")
  lab_dump      1: log PHY registers at probe (firmware state) and after
                every power-on, and every set_voltages decision; on a
                power-on failure, log which wait timed out and dump the PHY
The driver registers as "qcom-edp-phy-lab"; the stock phy_qcom_edp module
must be kept from loading.
"""

import shutil
import sys
from pathlib import Path

HEADERS = ('phy-qcom-qmp-dp-phy.h', 'phy-qcom-qmp-qserdes-com-v4.h',
           'phy-qcom-qmp-qserdes-com-v6.h', 'phy-qcom-qmp-qserdes-dp-com-v8.h')

EDITS = [
    ('#include "phy-qcom-qmp-qserdes-dp-com-v8.h"\n',
     '#include "phy-qcom-qmp-qserdes-dp-com-v8.h"\n'
     '\n'
     '/* glymur-lab instrumentation (scripts/linux/glymur-lab) */\n'
     'static int lab_table;\n'
     'module_param(lab_table, int, 0644);\n'
     'MODULE_PARM_DESC(lab_table, "0 auto, 1 eDP swing tables, 2 DP swing tables");\n'
     'static int lab_ssc = -1;\n'
     'module_param(lab_ssc, int, 0644);\n'
     'MODULE_PARM_DESC(lab_ssc, "-1 auto, 0 off, 1 on");\n'
     'static bool lab_uefi_tx;\n'
     'module_param(lab_uefi_tx, bool, 0644);\n'
     'MODULE_PARM_DESC(lab_uefi_tx, "use the firmware TX drive/emphasis/LDO values");\n'
     'static bool lab_uefi_misc;\n'
     'module_param(lab_uefi_misc, bool, 0644);\n'
     'MODULE_PARM_DESC(lab_uefi_misc, "restore firmware polarity/offsets/band after power-on");\n'
     'static bool lab_fw_pll;\n'
     'module_param(lab_fw_pll, bool, 0644);\n'
     'MODULE_PARM_DESC(lab_fw_pll, "overwrite the rate-dependent PLL registers with the firmware values");\n'
     'static bool lab_dump = true;\n'
     'module_param(lab_dump, bool, 0644);\n'
     'MODULE_PARM_DESC(lab_dump, "log PHY registers and swing decisions");\n'),

    ('\tbool is_edp;\n\tbool is_nord;\n};\n',
     '\tbool is_edp;\n\tbool is_nord;\n'
     '\n'
     '\t/* glymur-lab: firmware TX state captured at probe, per TX block */\n'
     '\tbool fw_valid;\n'
     '\tu32 fw_drv[2], fw_emp[2], fw_ldo[2], fw_band[2], fw_pol[2];\n'
     '\tu32 fw_drv_ofs[2], fw_res0[2], fw_res1[2];\n'
     '\tresource_size_t sz_edp, sz_tx, sz_pll;\n'
     '\tu32 fw_pll[0xd8];\n'
     '};\n'
     '\n'
     'static void lab_dump_region(const char *what, const char *name,\n'
     '\t\t\t    void __iomem *base, resource_size_t size)\n'
     '{\n'
     '\tresource_size_t off;\n'
     '\n'
     '\tfor (off = 0; off < size; off += 16) {\n'
     '\t\tu32 v[4] = { 0 };\n'
     '\t\tint i;\n'
     '\n'
     '\t\tfor (i = 0; i < 4 && off + i * 4 < size; i++)\n'
     '\t\t\tv[i] = readl(base + off + i * 4);\n'
     '\t\tpr_info("glymur-lab phy %s %s +%03llx: %08x %08x %08x %08x\\n", what,\n'
     '\t\t\tname, (unsigned long long)off, v[0], v[1], v[2], v[3]);\n'
     '\t}\n'
     '}\n'
     '\n'
     'static void lab_dump_all(const struct qcom_edp *edp, const char *what)\n'
     '{\n'
     '\tif (!lab_dump)\n'
     '\t\treturn;\n'
     '\tlab_dump_region(what, "dp", edp->edp, edp->sz_edp);\n'
     '\tlab_dump_region(what, "tx0", edp->tx0, edp->sz_tx);\n'
     '\tlab_dump_region(what, "tx1", edp->tx1, edp->sz_tx);\n'
     '\tlab_dump_region(what, "pll", edp->pll, edp->sz_pll);\n'
     '}\n'),

    ('\tif (edp->is_edp)\n'
     '\t\tcfg = edp->cfg->edp_swing_pre_emph_cfg;\n'
     '\telse\n'
     '\t\tcfg = edp->cfg->dp_swing_pre_emph_cfg;\n',
     '\tif (lab_table == 1 || (lab_table == 0 && edp->is_edp))\n'
     '\t\tcfg = edp->cfg->edp_swing_pre_emph_cfg;\n'
     '\telse\n'
     '\t\tcfg = edp->cfg->dp_swing_pre_emph_cfg;\n'),

    ('\tif (swing == 0xff || emph == 0xff)\n'
     '\t\treturn -EINVAL;\n'
     '\n'
     '\tret = edp->cfg->ver_ops->com_ldo_config(edp);\n',
     '\tif (lab_dump)\n'
     '\t\tpr_info("glymur-lab phy set_voltages: rate %u lanes %u v%u p%u table %s is_edp %d swing 0x%02x emph 0x%02x uefi_tx %d\\n",\n'
     '\t\t\tdp_opts->link_rate, dp_opts->lanes, v_level, p_level,\n'
     '\t\t\tcfg == edp->cfg->edp_swing_pre_emph_cfg ? "edp" : "dp",\n'
     '\t\t\tedp->is_edp, swing, emph, lab_uefi_tx);\n'
     '\n'
     '\tif (lab_uefi_tx && edp->fw_valid) {\n'
     '\t\twritel(edp->fw_ldo[0], edp->tx0 + TXn_LDO_CONFIG);\n'
     '\t\twritel(edp->fw_ldo[1], edp->tx1 + TXn_LDO_CONFIG);\n'
     '\t\twritel(edp->fw_drv[0], edp->tx0 + TXn_TX_DRV_LVL);\n'
     '\t\twritel(edp->fw_emp[0], edp->tx0 + TXn_TX_EMP_POST1_LVL);\n'
     '\t\twritel(edp->fw_drv[1], edp->tx1 + TXn_TX_DRV_LVL);\n'
     '\t\twritel(edp->fw_emp[1], edp->tx1 + TXn_TX_EMP_POST1_LVL);\n'
     '\t\treturn 0;\n'
     '\t}\n'
     '\n'
     '\tif (swing == 0xff || emph == 0xff)\n'
     '\t\treturn -EINVAL;\n'
     '\n'
     '\tret = edp->cfg->ver_ops->com_ldo_config(edp);\n'),

    ('\tif (edp->dp_opts.ssc) {\n'
     '\t\tret = qcom_edp_configure_ssc(edp);\n',
     '\tif (lab_ssc == 1 || (lab_ssc < 0 && edp->dp_opts.ssc)) {\n'
     '\t\tret = qcom_edp_configure_ssc(edp);\n'),

    ('\tclk_set_rate(edp->dp_link_hw.clk, edp->dp_opts.link_rate * 100000);\n'
     '\tclk_set_rate(edp->dp_pixel_hw.clk, pixel_freq);\n'
     '\n'
     '\treturn 0;\n'
     '}\n',
     '\tif (lab_uefi_misc && edp->fw_valid) {\n'
     '\t\tint t;\n'
     '\n'
     '\t\tfor (t = 0; t < 2; t++) {\n'
     '\t\t\tvoid __iomem *tx = t ? edp->tx1 : edp->tx0;\n'
     '\n'
     '\t\t\twritel(edp->fw_pol[t], tx + TXn_TX_POL_INV);\n'
     '\t\t\twritel(edp->fw_drv_ofs[t], tx + TXn_TX_DRV_LVL_OFFSET);\n'
     '\t\t\twritel(edp->fw_res0[t], tx + TXn_RES_CODE_LANE_OFFSET_TX0);\n'
     '\t\t\twritel(edp->fw_res1[t], tx + TXn_RES_CODE_LANE_OFFSET_TX1);\n'
     '\t\t\twritel(edp->fw_band[t], tx + TXn_TX_BAND);\n'
     '\t\t}\n'
     '\t}\n'
     '\tif (lab_dump)\n'
     '\t\tpr_info("glymur-lab phy power_on: rate %u lanes %u ssc %d (lab_ssc %d) is_edp %d uefi_misc %d\\n",\n'
     '\t\t\tedp->dp_opts.link_rate, edp->dp_opts.lanes, edp->dp_opts.ssc,\n'
     '\t\t\tlab_ssc, edp->is_edp, lab_uefi_misc);\n'
     '\tlab_dump_all(edp, "after-power-on");\n'
     '\n'
     '\tclk_set_rate(edp->dp_link_hw.clk, edp->dp_opts.link_rate * 100000);\n'
     '\tclk_set_rate(edp->dp_pixel_hw.clk, pixel_freq);\n'
     '\n'
     '\treturn 0;\n'
     '}\n'),

    # After the driver programs the PLL: optionally apply the firmware's values.
    ('\tret = qcom_edp_configure_pll(edp);\n'
     '\tif (ret)\n'
     '\t\treturn ret;\n'
     '\n'
     '\t/* TX Lane configuration */\n',
     '\tret = qcom_edp_configure_pll(edp);\n'
     '\tif (ret)\n'
     '\t\treturn ret;\n'
     '\n'
     '\tif (lab_fw_pll && edp->fw_valid &&\n'
     '\t    edp->cfg->ver_ops->com_power_on == qcom_edp_phy_power_on_v8) {\n'
     '\t\tstatic const u16 pll_regs[] = {\n'
     '\t\t\tDP_QSERDES_V8_COM_DEC_START_MODE0,\n'
     '\t\t\tDP_QSERDES_V8_COM_DIV_FRAC_START1_MODE0,\n'
     '\t\t\tDP_QSERDES_V8_COM_DIV_FRAC_START2_MODE0,\n'
     '\t\t\tDP_QSERDES_V8_COM_DIV_FRAC_START3_MODE0,\n'
     '\t\t\tDP_QSERDES_V8_COM_LOCK_CMP1_MODE0,\n'
     '\t\t\tDP_QSERDES_V8_COM_LOCK_CMP2_MODE0,\n'
     '\t\t\tDP_QSERDES_V8_COM_CORECLK_DIV_MODE0,\n'
     '\t\t\tDP_QSERDES_V8_COM_VCO_TUNE1_MODE0,\n'
     '\t\t\tDP_QSERDES_V8_COM_VCO_TUNE2_MODE0,\n'
     '\t\t\tDP_QSERDES_V8_COM_BIN_VCOCAL_CMP_CODE1_MODE0,\n'
     '\t\t\tDP_QSERDES_V8_COM_BIN_VCOCAL_CMP_CODE2_MODE0,\n'
     '\t\t\tDP_QSERDES_V8_COM_SSC_STEP_SIZE1_MODE0,\n'
     '\t\t\tDP_QSERDES_V8_COM_SSC_STEP_SIZE2_MODE0,\n'
     '\t\t};\n'
     '\t\tint r;\n'
     '\n'
     '\t\tfor (r = 0; r < ARRAY_SIZE(pll_regs); r++) {\n'
     '\t\t\tu32 want = edp->fw_pll[pll_regs[r] / 4] & 0xff;\n'
     '\t\t\tu32 had = readl(edp->pll + pll_regs[r]) & 0xff;\n'
     '\n'
     '\t\t\tif (lab_dump)\n'
     '\t\t\t\tpr_info("glymur-lab phy fw_pll: +0x%03x driver 0x%02x -> firmware 0x%02x\\n",\n'
     '\t\t\t\t\tpll_regs[r], had, want);\n'
     '\t\t\twritel(want, edp->pll + pll_regs[r]);\n'
     '\t\t}\n'
     '\t}\n'
     '\n'
     '\t/* TX Lane configuration */\n'),

    # Say which wait failed, and what the PHY looks like, when power-on fails.
    ('\tret = edp->cfg->ver_ops->com_power_on(edp);\n'
     '\tif (ret)\n'
     '\t\treturn ret;\n'
     '\n'
     '\tret = edp->cfg->ver_ops->com_ldo_config(edp);\n',
     '\tret = edp->cfg->ver_ops->com_power_on(edp);\n'
     '\tif (ret) {\n'
     '\t\tpr_info("glymur-lab phy power-on FAILED at com_power_on (CMN_STATUS wait): %d\\n", ret);\n'
     '\t\tlab_dump_all(edp, "poweron-failed");\n'
     '\t\treturn ret;\n'
     '\t}\n'
     '\n'
     '\tret = edp->cfg->ver_ops->com_ldo_config(edp);\n'),

    ('\tret = edp->cfg->ver_ops->com_resetsm_cntrl(edp);\n'
     '\tif (ret)\n'
     '\t\treturn ret;\n'
     '\n'
     '\twritel(0x19, edp->edp + DP_PHY_CFG);\n',
     '\tret = edp->cfg->ver_ops->com_resetsm_cntrl(edp);\n'
     '\tif (ret) {\n'
     '\t\tpr_info("glymur-lab phy power-on FAILED at com_resetsm_cntrl (C_READY wait, PLL lock): %d, rate %u lanes %u ssc %d\\n",\n'
     '\t\t\tret, edp->dp_opts.link_rate, edp->dp_opts.lanes, edp->dp_opts.ssc);\n'
     '\t\tlab_dump_all(edp, "poweron-failed");\n'
     '\t\treturn ret;\n'
     '\t}\n'
     '\n'
     '\twritel(0x19, edp->edp + DP_PHY_CFG);\n'),

    ('\tret = readl_poll_timeout(edp->edp + (edp->is_nord ? DP_PHY_STATUS_NORD : DP_PHY_STATUS),\n'
     '\t\t\t\t val, val & BIT(1), 500, 10000);\n'
     '\tif (ret)\n'
     '\t\treturn ret;\n',
     '\tret = readl_poll_timeout(edp->edp + (edp->is_nord ? DP_PHY_STATUS_NORD : DP_PHY_STATUS),\n'
     '\t\t\t\t val, val & BIT(1), 500, 10000);\n'
     '\tif (ret) {\n'
     '\t\tpr_info("glymur-lab phy power-on FAILED at DP_PHY_STATUS bit 1 (PHY ready), status 0x%08x: %d, rate %u lanes %u ssc %d fw_pll %d\\n",\n'
     '\t\t\tval, ret, edp->dp_opts.link_rate, edp->dp_opts.lanes,\n'
     '\t\t\tedp->dp_opts.ssc, lab_fw_pll);\n'
     '\t\tlab_dump_all(edp, "poweron-failed");\n'
     '\t\treturn ret;\n'
     '\t}\n'),

    ('\tedp->num_clks = devm_clk_bulk_get_all(dev, &edp->clks);\n'
     '\tif (edp->num_clks < 0)\n'
     '\t\treturn dev_err_probe(dev, edp->num_clks, "failed to get clocks\\n");\n',
     '\tedp->num_clks = devm_clk_bulk_get_all(dev, &edp->clks);\n'
     '\tif (edp->num_clks < 0)\n'
     '\t\treturn dev_err_probe(dev, edp->num_clks, "failed to get clocks\\n");\n'
     '\n'
     '\t/*\n'
     '\t * glymur-lab: capture the firmware\'s PHY state before anything\n'
     '\t * reprograms it. The clock references taken here are kept, so the\n'
     '\t * firmware\'s clocks are never gated by this capture.\n'
     '\t */\n'
     '\tedp->sz_edp = resource_size(platform_get_resource(pdev, IORESOURCE_MEM, 0));\n'
     '\tedp->sz_tx = resource_size(platform_get_resource(pdev, IORESOURCE_MEM, 1));\n'
     '\tedp->sz_pll = resource_size(platform_get_resource(pdev, IORESOURCE_MEM, 3));\n'
     '\tif (!clk_bulk_prepare_enable(edp->num_clks, edp->clks)) {\n'
     '\t\tint t;\n'
     '\n'
     '\t\tfor (t = 0; t < 2; t++) {\n'
     '\t\t\tvoid __iomem *tx = t ? edp->tx1 : edp->tx0;\n'
     '\n'
     '\t\t\tedp->fw_drv[t] = readl(tx + TXn_TX_DRV_LVL);\n'
     '\t\t\tedp->fw_emp[t] = readl(tx + TXn_TX_EMP_POST1_LVL);\n'
     '\t\t\tedp->fw_ldo[t] = readl(tx + TXn_LDO_CONFIG);\n'
     '\t\t\tedp->fw_band[t] = readl(tx + TXn_TX_BAND);\n'
     '\t\t\tedp->fw_pol[t] = readl(tx + TXn_TX_POL_INV);\n'
     '\t\t\tedp->fw_drv_ofs[t] = readl(tx + TXn_TX_DRV_LVL_OFFSET);\n'
     '\t\t\tedp->fw_res0[t] = readl(tx + TXn_RES_CODE_LANE_OFFSET_TX0);\n'
     '\t\t\tedp->fw_res1[t] = readl(tx + TXn_RES_CODE_LANE_OFFSET_TX1);\n'
     '\t\t\tpr_info("glymur-lab phy firmware tx%d: drv 0x%02x emp 0x%02x ldo 0x%02x band 0x%02x pol 0x%02x drv_ofs 0x%02x res 0x%02x/0x%02x\\n",\n'
     '\t\t\t\tt, edp->fw_drv[t], edp->fw_emp[t], edp->fw_ldo[t],\n'
     '\t\t\t\tedp->fw_band[t], edp->fw_pol[t], edp->fw_drv_ofs[t],\n'
     '\t\t\t\tedp->fw_res0[t], edp->fw_res1[t]);\n'
     '\t\t}\n'
     '\t\tfor (t = 0; t < ARRAY_SIZE(edp->fw_pll) && t * 4 < edp->sz_pll; t++)\n'
     '\t\t\tedp->fw_pll[t] = readl(edp->pll + t * 4);\n'
     '\t\tedp->fw_valid = true;\n'
     '\t\tlab_dump_all(edp, "firmware");\n'
     '\t} else {\n'
     '\t\tdev_warn(dev, "glymur-lab: could not enable clocks to capture firmware state\\n");\n'
     '\t}\n'),

    ('\t\t.name\t= "qcom-edp-phy",\n',
     '\t\t.name\t= "qcom-edp-phy-lab",\n'),

    ('MODULE_DESCRIPTION("Qualcomm eDP QMP PHY driver");\n',
     'MODULE_DESCRIPTION("Qualcomm eDP QMP PHY driver (glymur-lab instrumented)");\n'),
]


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src = Path(sys.argv[1]) / 'drivers/phy/qualcomm'
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    text = (src / 'phy-qcom-edp.c').read_text()
    for old, new in EDITS:
        count = text.count(old)
        if count != 1:
            sys.exit(f'edit anchor found {count} times, expected 1:\n{old[:120]}')
        text = text.replace(old, new)
    (out / 'phy-qcom-edp-lab.c').write_text(text)
    for header in HEADERS:
        shutil.copy(src / header, out / header)
    (out / 'Makefile').write_text('obj-m += phy-qcom-edp-lab.o\n')
    print(f'wrote {out}/phy-qcom-edp-lab.c')


if __name__ == '__main__':
    main()
