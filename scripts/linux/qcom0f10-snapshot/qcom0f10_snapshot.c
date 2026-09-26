// SPDX-License-Identifier: GPL-2.0-only
/* Read-only follow-up snapshot of HP Glymur I2C1 and I2C5 GENI state. */

#include <linux/acpi.h>
#include <linux/io.h>
#include <linux/ioport.h>
#include <linux/module.h>
#include <linux/platform_device.h>

#define GLYMUR_I2C1_BASE        0x00b80000
#define GLYMUR_I2C5_BASE        0x00b90000
#define GLYMUR_I2C_SIZE         0x4000

#define SE_GENI_STATUS          0x40
#define GENI_SER_M_CLK_CFG      0x48
#define GENI_IF_DISABLE_RO      0x64
#define GENI_FW_REVISION_RO     0x68
#define SE_GENI_CLK_SEL         0x7c
#define SE_GENI_DMA_MODE_EN     0x258
#define SE_I2C_SCL_COUNTERS     0x278
#define SE_GENI_M_IRQ_STATUS    0x610
#define SE_GENI_IOS             0x908
#define SE_HW_PARAM_0           0xe24

#define GENI_PROTO_I2C          3
#define GENI_SER_CLK_EN         BIT(0)
#define GENI_FIFO_IF_DISABLE    BIT(0)

static bool snapshot;
module_param(snapshot, bool, 0444);
MODULE_PARM_DESC(snapshot, "Read HP I2C1/I2C5 GENI state without configuring an adapter");

static int qcom0f10_snapshot_probe(struct platform_device *pdev)
{
	struct resource *res;
	void __iomem *base;
	u32 revision, clk_cfg, scl, status, ios, irq, dma, hw, clk_sel;

	if (!snapshot)
		return -ENODEV;

	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!res || resource_size(res) != GLYMUR_I2C_SIZE ||
	    (res->start != GLYMUR_I2C1_BASE && res->start != GLYMUR_I2C5_BASE))
		return -ENODEV;

	base = devm_platform_ioremap_resource(pdev, 0);
	if (IS_ERR(base))
		return PTR_ERR(base);

	dev_info(&pdev->dev, "snapshot: starting read-only MMIO\n");
	revision = readl_relaxed(base + GENI_FW_REVISION_RO);
	if (((revision >> 8) & 0xff) != GENI_PROTO_I2C) {
		dev_info(&pdev->dev, "snapshot: unexpected revision=0x%08x; stopping\n",
			 revision);
		return -ENODEV;
	}

	clk_cfg = readl_relaxed(base + GENI_SER_M_CLK_CFG);
	if (!(clk_cfg & GENI_SER_CLK_EN) ||
	    (readl_relaxed(base + GENI_IF_DISABLE_RO) & GENI_FIFO_IF_DISABLE)) {
		dev_info(&pdev->dev, "snapshot: clock=0x%08x or FIFO unavailable; stopping\n",
			 clk_cfg);
		return -ENODEV;
	}

	clk_sel = readl_relaxed(base + SE_GENI_CLK_SEL);
	scl = readl_relaxed(base + SE_I2C_SCL_COUNTERS);
	status = readl_relaxed(base + SE_GENI_STATUS);
	ios = readl_relaxed(base + SE_GENI_IOS);
	irq = readl_relaxed(base + SE_GENI_M_IRQ_STATUS);
	dma = readl_relaxed(base + SE_GENI_DMA_MODE_EN);
	hw = readl_relaxed(base + SE_HW_PARAM_0);

	dev_info(&pdev->dev,
		 "snapshot: rev=0x%08x clk=0x%08x div=%u sel=0x%08x scl=0x%08x high=%u low=%u cycle=%u\n",
		 revision, clk_cfg, (clk_cfg >> 4) & 0xfff, clk_sel, scl,
		 (scl >> 20) & 0x3ff, (scl >> 10) & 0x3ff, scl & 0x3ff);
	dev_info(&pdev->dev,
		 "snapshot: status=0x%08x ios=0x%08x irq=0x%08x dma=0x%08x hw=0x%08x\n",
		 status, ios, irq, dma, hw);

	return -ENODEV;
}

static const struct acpi_device_id qcom0f10_snapshot_acpi_match[] = {
	{ "QCOM0F10" },
	{ }
};
MODULE_DEVICE_TABLE(acpi, qcom0f10_snapshot_acpi_match);

static struct platform_driver qcom0f10_snapshot_driver = {
	.probe = qcom0f10_snapshot_probe,
	.driver = {
		.name = "qcom0f10_snapshot",
		.acpi_match_table = qcom0f10_snapshot_acpi_match,
	},
};
module_platform_driver(qcom0f10_snapshot_driver);

MODULE_DESCRIPTION("Read-only HP Glymur GENI I2C state snapshot");
MODULE_LICENSE("GPL");
