// SPDX-License-Identifier: GPL-2.0-only
/* Read-only first-pass inspection of HP Glymur ACPI QCOM0F10 I2C engines. */

#include <linux/acpi.h>
#include <linux/io.h>
#include <linux/ioport.h>
#include <linux/module.h>
#include <linux/platform_device.h>

#define GLYMUR_I2C1_BASE	0x00b80000
#define GLYMUR_I2C5_BASE	0x00b90000
#define GLYMUR_I2C_SIZE	0x4000

#define GENI_SER_M_CLK_CFG	0x48
#define GENI_IF_DISABLE_RO	0x64
#define GENI_FW_REVISION_RO	0x68
#define GENI_PROTO_I2C		3
#define GENI_SER_CLK_EN		BIT(0)
#define GENI_FIFO_IF_DISABLE	BIT(0)

static bool inspect;
module_param(inspect, bool, 0444);
MODULE_PARM_DESC(inspect, "Read HP I2C1/I2C5 GENI status without binding an I2C adapter");

static int qcom0f10_inspect_probe(struct platform_device *pdev)
{
	struct resource *res;
	void __iomem *base;
	u32 revision, protocol, fifo_disabled, clk_cfg;

	if (!inspect)
		return -ENODEV;

	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!res || resource_size(res) != GLYMUR_I2C_SIZE ||
	    (res->start != GLYMUR_I2C1_BASE && res->start != GLYMUR_I2C5_BASE))
		return -ENODEV;

	base = devm_platform_ioremap_resource(pdev, 0);
	if (IS_ERR(base))
		return PTR_ERR(base);

	dev_info(&pdev->dev, "inspection: starting MMIO reads\n");
	revision = readl_relaxed(base + GENI_FW_REVISION_RO);
	protocol = (revision >> 8) & 0xff;
	if (protocol != GENI_PROTO_I2C) {
		dev_info(&pdev->dev, "inspection: revision=0x%08x protocol=%u (I2C=%u)\n",
			 revision, protocol, GENI_PROTO_I2C);
		return -ENODEV;
	}

	fifo_disabled = !!(readl_relaxed(base + GENI_IF_DISABLE_RO) &
			    GENI_FIFO_IF_DISABLE);
	clk_cfg = readl_relaxed(base + GENI_SER_M_CLK_CFG);
	dev_info(&pdev->dev,
		 "inspection: revision=0x%08x protocol=I2C fifo_disabled=%u m_clk_cfg=0x%08x enabled=%u\n",
		 revision, fifo_disabled, clk_cfg, !!(clk_cfg & GENI_SER_CLK_EN));

	return -ENODEV;
}

static const struct acpi_device_id qcom0f10_inspect_acpi_match[] = {
	{ "QCOM0F10" },
	{ }
};
MODULE_DEVICE_TABLE(acpi, qcom0f10_inspect_acpi_match);

static struct platform_driver qcom0f10_inspect_driver = {
	.probe = qcom0f10_inspect_probe,
	.driver = {
		.name = "qcom0f10_inspect",
		.acpi_match_table = qcom0f10_inspect_acpi_match,
	},
};
module_platform_driver(qcom0f10_inspect_driver);

MODULE_DESCRIPTION("Read-only HP Glymur QCOM0F10 ACPI inspection");
MODULE_LICENSE("GPL");
