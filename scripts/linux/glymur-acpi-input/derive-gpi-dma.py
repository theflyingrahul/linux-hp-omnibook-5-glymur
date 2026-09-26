"""Derive the Glymur ACPI GPI DMA test driver from Linux v7.0 drivers/dma/qcom/gpi.c.

Usage: derive-gpi-dma.py <linux-v7.0-tree> <output-dir>

Writes glymur_gpi_dma.c plus the two private drivers/dma headers it needs
(dmaengine.h, virt-dma.h), all hash-checked against Linux v7.0.
"""
import hashlib
import os
import sys

tree, out_dir = sys.argv[1], sys.argv[2]
SOURCES = {
    'drivers/dma/qcom/gpi.c':
        '013cac9c55feaf9e68c56f8d2cfb26fe07cf7d00d1ed1cc7dd0771c285f35782',
    'drivers/dma/dmaengine.h':
        '09d1c31b6a025adc25a6529854642689ab4302ae19007923f9cfa68f7733ec28',
    'drivers/dma/virt-dma.h':
        '695955f347bf51c852fd527c46943277694f812416d3e142991a6f120c3ddad3',
}
text = {}
for rel, digest in SOURCES.items():
    data = open(os.path.join(tree, rel), encoding='utf-8').read()
    assert hashlib.sha256(data.encode()).hexdigest() == digest, f'unexpected source: {rel}'
    text[rel] = data

src = text['drivers/dma/qcom/gpi.c']


def sub(old, new, count=1):
    global src
    assert src.count(old) == count, f'pattern count {src.count(old)} != {count}: {old[:60]!r}'
    src = src.replace(old, new)


sub(' * Copyright (c) 2020, Linaro Limited\n */\n',
    ' * Copyright (c) 2020, Linaro Limited\n'
    ' *\n'
    ' * HP OmniBook 5 (Glymur) ACPI bring-up variant of Linux v7.0\n'
    ' * drivers/dma/qcom/gpi.c. It binds only allowlisted QCOM0F88 GPI engines,\n'
    ' * takes the GPII count from the ACPI interrupts, and hands channels to the\n'
    ' * Glymur GENI I2C GSI test driver through glymur_gpi_dma_request() instead\n'
    ' * of a DT dmas phandle. Out-of-tree test module; not a replacement for the\n'
    ' * in-tree driver.\n'
    ' */\n')
sub('#include "../dmaengine.h"\n#include "../virt-dma.h"\n',
    '#include <linux/acpi.h>\n#include "dmaengine.h"\n#include "virt-dma.h"\n')

# The ACPI window starts 0x4000 above the DT block base (QGP1: 0xa04000 vs
# DT gpi_dma1 0xa00000, length 0x58000 vs 0x60000). Glymur uses the
# sm6350-style EE offset 0x10000, so every GPII register the driver touches
# (block offsets 0x20000..0x23404 + 0x4000 * gpii, minus 0x10000) lies
# inside the ACPI window for the three GPIIs ACPI describes.
sub('#define GPII_n_CH_k_CNTXT_0_OFFS(n, k)',
    '#define GLYMUR_ACPI_WINDOW_SKIP\t0x4000\n'
    '#define GLYMUR_EE_OFFSET\t0x10000\n'
    '#define GLYMUR_MAX_GPII\t\t16\n'
    '\n'
    '#define GPII_n_CH_k_CNTXT_0_OFFS(n, k)')

sub('''static int gpi_probe(struct platform_device *pdev)
{''', '''static char allow[64] = "0xa04000";
module_param_string(allow, allow, sizeof(allow), 0444);
MODULE_PARM_DESC(allow, "Comma-separated MMIO bases of QCOM0F88 GPI engines to bind");

static bool gpi_engine_allowed(resource_size_t start)
{
	char list[sizeof(allow)], *cursor = list, *token;
	unsigned long base;

	strscpy(list, allow, sizeof(list));
	while ((token = strsep(&cursor, ",")) != NULL)
		if (*token && !kstrtoul(strim(token), 0, &base) && base == start)
			return true;
	return false;
}

static DEFINE_MUTEX(glymur_gpi_lock);
static struct gpi_dev *glymur_gpi;

struct dma_chan *glymur_gpi_dma_request(u32 chid, u32 seid, u32 protocol);

/**
 * glymur_gpi_dma_request() - Request a GPI channel on the bound ACPI engine
 * @chid: 0 for TX, 1 for RX (the first DT dmas cell)
 * @seid: serial engine index within the QUP (the second DT dmas cell)
 * @protocol: QCOM_GPI_* protocol (the third DT dmas cell)
 *
 * Equivalent of a DT "dmas = <&gpi chid seid protocol>" lookup.
 */
struct dma_chan *glymur_gpi_dma_request(u32 chid, u32 seid, u32 protocol)
{
	struct of_phandle_args args = {
		.args_count = 3,
		.args = { chid, seid, protocol },
	};
	struct of_dma ofdma = {};
	struct dma_chan *chan;

	mutex_lock(&glymur_gpi_lock);
	if (!glymur_gpi) {
		mutex_unlock(&glymur_gpi_lock);
		return ERR_PTR(-EPROBE_DEFER);
	}
	ofdma.of_dma_data = glymur_gpi;
	chan = gpi_of_dma_xlate(&args, &ofdma);
	mutex_unlock(&glymur_gpi_lock);

	return chan ?: ERR_PTR(-EBUSY);
}
EXPORT_SYMBOL_GPL(glymur_gpi_dma_request);

static int gpi_probe(struct platform_device *pdev)
{''')

sub('''	gpi_dev->ee_base = gpi_dev->regs;

	ret = of_property_read_u32(gpi_dev->dev->of_node, "dma-channels",
				   &gpi_dev->max_gpii);
	if (ret) {
		dev_err(gpi_dev->dev, "missing 'max-no-gpii' DT node\\n");
		return ret;
	}

	ret = of_property_read_u32(gpi_dev->dev->of_node, "dma-channel-mask",
				   &gpi_dev->gpii_mask);
	if (ret) {
		dev_err(gpi_dev->dev, "missing 'gpii-mask' DT node\\n");
		return ret;
	}

	ee_offset = (uintptr_t)device_get_match_data(gpi_dev->dev);
	gpi_dev->ee_base = gpi_dev->ee_base - ee_offset;
''', '''	gpi_dev->ee_base = gpi_dev->regs;

	if (glymur_gpi || !gpi_engine_allowed(gpi_dev->res->start))
		return -ENODEV;
	if ((gpi_dev->res->start & 0xffff) != GLYMUR_ACPI_WINDOW_SKIP) {
		dev_err(gpi_dev->dev, "unexpected ACPI window %pR\\n", gpi_dev->res);
		return -ENODEV;
	}

	/* ACPI lists one interrupt per GPII assigned to this EE, in order. */
	ret = platform_irq_count(pdev);
	if (ret <= 0 || ret > GLYMUR_MAX_GPII)
		return ret < 0 ? ret : -ENODEV;
	gpi_dev->max_gpii = ret;
	gpi_dev->gpii_mask = GENMASK(ret - 1, 0);

	ee_offset = GLYMUR_EE_OFFSET + GLYMUR_ACPI_WINDOW_SKIP;
	gpi_dev->ee_base = gpi_dev->ee_base - ee_offset;
	dev_info(gpi_dev->dev, "ACPI GPI engine %pR: %u GPIIs\\n", gpi_dev->res,
		 gpi_dev->max_gpii);
''')

sub('''	ret = of_dma_controller_register(gpi_dev->dev->of_node,
					 gpi_of_dma_xlate, gpi_dev);
	if (ret) {
		dev_err(gpi_dev->dev, "of_dma_controller_reg failed ret:%d", ret);
		return ret;
	}

	return ret;
}''', '''	mutex_lock(&glymur_gpi_lock);
	glymur_gpi = gpi_dev;
	mutex_unlock(&glymur_gpi_lock);

	return ret;
}''')

# Match only the HP Glymur ACPI GPI engine. Like the in-tree driver, the
# module has no exit path: a DMA engine with live clients cannot be removed.
start = src.index('static const struct of_device_id gpi_of_match[] = {')
end = src.index('MODULE_DEVICE_TABLE(of, gpi_of_match);\n') + len('MODULE_DEVICE_TABLE(of, gpi_of_match);\n')
src = src[:start] + '''static const struct acpi_device_id gpi_acpi_match[] = {
	{ "QCOM0F88" },
	{ }
};
MODULE_DEVICE_TABLE(acpi, gpi_acpi_match);
''' + src[end:]
sub('''		.name = KBUILD_MODNAME,
		.of_match_table = gpi_of_match,
''', '''		.name = KBUILD_MODNAME,
		.acpi_match_table = gpi_acpi_match,
''')
# Channels are only for the GSI I2C driver. Without DMA_PRIVATE, a loaded
# async_tx (pulled in by raid456 on the Ubuntu live image) takes every
# channel at registration and starts it with seid 0 / protocol 0; on
# 2026-09-26 those CH START commands timed out and left no free GPII.
sub('''	dma_cap_zero(gpi_dev->dma_device.cap_mask);
	dma_cap_set(DMA_SLAVE, gpi_dev->dma_device.cap_mask);
''', '''	dma_cap_zero(gpi_dev->dma_device.cap_mask);
	dma_cap_set(DMA_SLAVE, gpi_dev->dma_device.cap_mask);
	dma_cap_set(DMA_PRIVATE, gpi_dev->dma_device.cap_mask);
''')
sub('subsys_initcall(gpi_init)\n', 'module_init(gpi_init);\n')
sub('MODULE_DESCRIPTION("QCOM GPI DMA engine driver");',
    'MODULE_DESCRIPTION("HP Glymur ACPI GPI DMA test driver (derived from qcom gpi)");')

os.makedirs(out_dir, exist_ok=True)
open(os.path.join(out_dir, 'glymur_gpi_dma.c'), 'w', encoding='utf-8', newline='\n').write(src)
for rel in ('drivers/dma/dmaengine.h', 'drivers/dma/virt-dma.h'):
    open(os.path.join(out_dir, os.path.basename(rel)), 'w', encoding='utf-8',
         newline='\n').write(text[rel])
