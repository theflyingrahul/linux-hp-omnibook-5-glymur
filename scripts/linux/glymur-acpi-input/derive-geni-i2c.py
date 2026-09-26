"""Derive the Glymur ACPI GENI I2C test driver from Linux v7.0 i2c-qcom-geni.c."""
import hashlib
import sys

src_path, out_path = sys.argv[1], sys.argv[2]
src = open(src_path, encoding='utf-8').read()
assert hashlib.sha256(src.encode()).hexdigest() == \
    '74c7e931c34657dc48734e5fbf047de708bb0aff918c0d3d3adfeee480865cc0', 'unexpected source'


def sub(old, new, count=1):
    global src
    assert src.count(old) == count, f'pattern count {src.count(old)} != {count}: {old[:60]!r}'
    src = src.replace(old, new)


sub('// Copyright (c) 2017-2018, The Linux Foundation. All rights reserved.\n',
    '// Copyright (c) 2017-2018, The Linux Foundation. All rights reserved.\n'
    '//\n'
    '// HP OmniBook 5 (Glymur) ACPI bring-up variant of Linux v7.0\n'
    '// drivers/i2c/busses/i2c-qcom-geni.c. It binds only QCOM0F10, keeps the\n'
    '// firmware-owned SE clock untouched, takes SCL timing from the controller\'s\n'
    '// ACPI CLKD table, and uses FIFO transfers only. Out-of-tree test module;\n'
    '// not a replacement for the in-tree driver.\n')

# Bus allowlist by MMIO base. Only I2C1 (keyboard) and I2C5 (touchpad) were
# read successfully in the September 25 register snapshots; others must be
# added explicitly (the parameter is writable so a collector can widen it and
# then bind one device through sysfs after saving its earlier evidence).
sub('#define SE_I2C_ABORT\t\tBIT(1)\n',
    '#define SE_I2C_ABORT\t\tBIT(1)\n'
    '\n'
    'static char allow[96] = "0xb80000,0xb90000";\n'
    'module_param_string(allow, allow, sizeof(allow), 0644);\n'
    'MODULE_PARM_DESC(allow, "Comma-separated MMIO bases of QCOM0F10 controllers to bind");\n'
    '\n'
    'static bool geni_i2c_bus_allowed(resource_size_t start)\n'
    '{\n'
    '\tchar list[sizeof(allow)], *cursor = list, *token;\n'
    '\tunsigned long base;\n'
    '\n'
    '\tstrscpy(list, allow, sizeof(list));\n'
    '\twhile ((token = strsep(&cursor, ",")) != NULL)\n'
    '\t\tif (*token && !kstrtoul(strim(token), 0, &base) && base == start)\n'
    '\t\t\treturn true;\n'
    '\treturn false;\n'
    '}\n')
sub('\tgi2c->se.dev = dev;\n',
    '\tif (!platform_get_resource(pdev, IORESOURCE_MEM, 0) ||\n'
    '\t    !geni_i2c_bus_allowed(platform_get_resource(pdev, IORESOURCE_MEM, 0)->start))\n'
    '\t\treturn -ENODEV;\n'
    '\n'
    '\tgi2c->se.dev = dev;\n')
# A top-level ACPI device's parent is not a GENI wrapper; never reinterpret
# its driver data. A NULL wrapper selects the FIFO-only path below.
sub('\tgi2c->se.wrapper = dev_get_drvdata(dev->parent);\n',
    '\tgi2c->se.wrapper = has_acpi_companion(dev) ? NULL :\n'
    '\t\t\t   dev_get_drvdata(dev->parent);\n')

# Timing selection: prefer the ACPI CLKD row, never pass an ERR_PTR clock.
sub('''static int geni_i2c_clk_map_idx(struct geni_i2c_dev *gi2c)
{
	const struct geni_i2c_clk_fld *itr;

	if (clk_get_rate(gi2c->se.clk) == 32 * HZ_PER_MHZ)
''', '''#ifdef CONFIG_ACPI
/*
 * HP Glymur ACPI I2C controllers carry a CLKD package of seven-integer rows:
 * (0, source kHz, bus kHz, divider, t_cycle, t_high, t_low). Live register
 * snapshots of I2C1/I2C5 matched the 400 kHz row exactly, so reuse the row
 * the firmware already programmed instead of the generic DT timing table.
 */
static int geni_i2c_acpi_clkd(struct geni_i2c_dev *gi2c)
{
	struct acpi_buffer buf = { ACPI_ALLOCATE_BUFFER, NULL };
	struct geni_i2c_clk_fld *fld;
	union acpi_object *pkg, *row;
	acpi_handle handle = ACPI_HANDLE(gi2c->se.dev);
	u64 v[7];
	unsigned int i, j;
	int ret = -ENOENT;

	if (!handle || ACPI_FAILURE(acpi_evaluate_object(handle, "CLKD", NULL, &buf)))
		return -ENOENT;

	pkg = buf.pointer;
	if (!pkg || pkg->type != ACPI_TYPE_PACKAGE)
		goto out;

	for (i = 0; i < pkg->package.count; i++) {
		row = &pkg->package.elements[i];
		if (row->type != ACPI_TYPE_PACKAGE || row->package.count != 7)
			continue;
		for (j = 0; j < 7; j++) {
			if (row->package.elements[j].type != ACPI_TYPE_INTEGER)
				break;
			v[j] = row->package.elements[j].integer.value;
		}
		if (j != 7 || v[1] != 19200 || v[2] * 1000 != gi2c->clk_freq_out)
			continue;
		if (!v[3] || v[3] > 0xfff || !v[4] || v[4] > 0x3ff ||
		    !v[5] || !v[6] || v[5] + v[6] > v[4]) {
			dev_err(gi2c->se.dev, "rejecting malformed CLKD row %u\\n", i);
			ret = -EINVAL;
			goto out;
		}
		fld = devm_kzalloc(gi2c->se.dev, sizeof(*fld), GFP_KERNEL);
		if (!fld) {
			ret = -ENOMEM;
			goto out;
		}
		fld->clk_freq_out = gi2c->clk_freq_out;
		fld->clk_div = v[3];
		fld->t_cycle_cnt = v[4];
		fld->t_high_cnt = v[5];
		fld->t_low_cnt = v[6];
		gi2c->clk_fld = fld;
		dev_info(gi2c->se.dev, "ACPI CLKD %u Hz: div=%u high=%u low=%u cycle=%u\\n",
			 fld->clk_freq_out, fld->clk_div, fld->t_high_cnt,
			 fld->t_low_cnt, fld->t_cycle_cnt);
		ret = 0;
		break;
	}
out:
	ACPI_FREE(buf.pointer);
	return ret;
}
#else
static int geni_i2c_acpi_clkd(struct geni_i2c_dev *gi2c)
{
	return -ENOENT;
}
#endif

static int geni_i2c_clk_map_idx(struct geni_i2c_dev *gi2c)
{
	const struct geni_i2c_clk_fld *itr;
	int ret;

	if (has_acpi_companion(gi2c->se.dev)) {
		ret = geni_i2c_acpi_clkd(gi2c);
		if (ret != -ENOENT)
			return ret;
	}

	/* clk_get_rate(NULL) is 0: a firmware-owned ACPI clock uses 19.2 MHz. */
	if (clk_get_rate(gi2c->se.clk) == 32 * HZ_PER_MHZ)
''')

# Clock: an absent ACPI clock becomes NULL, not an error pointer.
sub('''	gi2c->se.clk = devm_clk_get(dev, "se");
	if (IS_ERR(gi2c->se.clk) && !has_acpi_companion(dev))
		return PTR_ERR(gi2c->se.clk);

	ret = device_property_read_u32(dev, "clock-frequency",
				       &gi2c->clk_freq_out);
	if (ret) {
''', '''	gi2c->se.clk = devm_clk_get(dev, "se");
	if (IS_ERR(gi2c->se.clk)) {
		if (!has_acpi_companion(dev))
			return PTR_ERR(gi2c->se.clk);
		gi2c->se.clk = NULL;
	}

	ret = device_property_read_u32(dev, "clock-frequency",
				       &gi2c->clk_freq_out);
	if (ret && has_acpi_companion(dev)) {
		/* Slowest ConnectionSpeed of this controller's ACPI children. */
		gi2c->clk_freq_out = i2c_acpi_find_bus_speed(dev);
		if (gi2c->clk_freq_out)
			ret = 0;
	}
	if (ret) {
''')

# Adapter name identifies this test driver in logs and sysfs.
sub('\tstrscpy(gi2c->adap.name, "Geni-I2C", sizeof(gi2c->adap.name));\n',
    '\tstrscpy(gi2c->adap.name, "Glymur-ACPI-Geni-I2C", sizeof(gi2c->adap.name));\n')

# Firmware state gate: never load SE firmware (it needs the DT wrapper) and
# never use SE DMA without a wrapper device.
sub('''	proto = geni_se_read_proto(&gi2c->se);
	if (proto == GENI_SE_INVALID_PROTO) {
''', '''	proto = geni_se_read_proto(&gi2c->se);
	if (!gi2c->se.wrapper) {
		u32 clk_cfg = readl_relaxed(gi2c->se.base + GENI_SER_M_CLK_CFG);

		if (proto != GENI_SE_I2C || !(clk_cfg & SER_CLK_EN) ||
		    (readl_relaxed(gi2c->se.base + GENI_IF_DISABLE_RO) & FIFO_IF_DISABLE)) {
			ret = dev_err_probe(dev, -ENODEV,
					    "firmware did not leave an I2C FIFO engine (proto=%u clk=0x%08x)\\n",
					    proto, clk_cfg);
			goto err_resources;
		}
		gi2c->no_dma = true;
	}
	if (proto == GENI_SE_INVALID_PROTO) {
''')
sub('''	if (desc && desc->no_dma_support) {
		fifo_disable = false;
		gi2c->no_dma = true;
	} else {''', '''	if ((desc && desc->no_dma_support) || !gi2c->se.wrapper) {
		fifo_disable = false;
		gi2c->no_dma = true;
	} else {''')

# geni_se_get_tx_fifo_depth() reads the QUP version from the wrapper to pick
# the SE_HW_PARAM_0 depth mask (first live run oopsed here on the NULL
# wrapper). Without a wrapper, accept the depth only if both masks agree.
sub('''		tx_depth = geni_se_get_tx_fifo_depth(&gi2c->se);
''', '''		if (gi2c->se.wrapper) {
			tx_depth = geni_se_get_tx_fifo_depth(&gi2c->se);
		} else {
			u32 hw = readl_relaxed(gi2c->se.base + SE_HW_PARAM_0);

			tx_depth = FIELD_GET(TX_FIFO_DEPTH_MSK_256_BYTES, hw);
			if (tx_depth != FIELD_GET(TX_FIFO_DEPTH_MSK, hw)) {
				ret = dev_err_probe(dev, -ENODEV,
						    "ambiguous TX FIFO depth without QUP version (hw_param0=0x%08x)\\n",
						    hw);
				goto err_resources;
			}
		}
''')
sub('#include <linux/acpi.h>\n', '#include <linux/acpi.h>\n#include <linux/bitfield.h>\n')

# Match only the HP Glymur controller; drop the DT/older ACPI IDs so the stock
# module keeps ownership of every other device.
sub('''static const struct acpi_device_id geni_i2c_acpi_match[] = {
	{ "QCOM0220"},
	{ "QCOM0411" },
	{ }
};''', '''static const struct acpi_device_id geni_i2c_acpi_match[] = {
	{ "QCOM0F10" },
	{ }
};''')
sub('''static const struct of_device_id geni_i2c_dt_match[] = {
	{ .compatible = "qcom,geni-i2c" },
	{ .compatible = "qcom,geni-i2c-master-hub", .data = &i2c_master_hub },
	{}
};
MODULE_DEVICE_TABLE(of, geni_i2c_dt_match);
''', '')
sub('''static const struct geni_i2c_desc i2c_master_hub = {
	.has_core_clk = true,
	.icc_ddr = NULL,
	.no_dma_support = true,
	.tx_fifo_depth = 16,
};

''', '')
sub('''		.name = "geni_i2c",
		.pm = &geni_i2c_pm_ops,
		.of_match_table = geni_i2c_dt_match,
''', '''		.name = "glymur_acpi_geni_i2c",
		.pm = &geni_i2c_pm_ops,
''')
sub('MODULE_DESCRIPTION("I2C Controller Driver for GENI based QUP cores");',
    'MODULE_DESCRIPTION("HP Glymur ACPI GENI I2C test driver (derived from i2c-qcom-geni)");')
open(out_path, 'w', encoding='utf-8', newline='\n').write(src)
