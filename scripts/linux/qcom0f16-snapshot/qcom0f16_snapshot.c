// SPDX-License-Identifier: GPL-2.0-only
/*
 * Read-only snapshot of the HP Glymur GENI UARTs (ACPI QCOM0F16) and the
 * Bluetooth enable line, for planning Bluetooth over UART.
 *
 * BTH0 (QCOM0F6B, the QCC2072 Bluetooth UART transport) uses
 * UartSerialBus on \_SB.UR15 (QUP_1_SE_6, 4-wire, 0xa98000) and GpioIo
 * on TLMM GPIO 116. Before any serial driver work, this records what
 * firmware left: the SE protocol, serial clock enable and divider, UART
 * word/parity/stop configuration, FIFO/DMA mode, and GPIO 116's mux,
 * direction and level. It also covers \_SB.UARD (QUP_2_SE_5, debug).
 *
 * Safety:
 *  - default-off (snapshot=1 required);
 *  - only the known QCOM0F16 windows are mapped;
 *  - MMIO reads only: no writes, no IRQ, clock, pinctrl or GPIO requests;
 *  - probe always returns -ENODEV, so nothing binds and nothing is left
 *    configured. The TLMM window is ioremapped read-only for two registers
 *    of one pin and unmapped again.
 */

#include <linux/acpi.h>
#include <linux/io.h>
#include <linux/ioport.h>
#include <linux/module.h>
#include <linux/platform_device.h>

#define GLYMUR_UR15_BASE	0x00a98000	/* QUP_1_SE_6: Bluetooth */
#define GLYMUR_SE_SIZE		0x4000
#define GLYMUR_TLMM_BASE	0x0f100000
#define TLMM_PIN_STRIDE		0x1000
#define TLMM_CTL		0x0
#define TLMM_IO			0x4

#define SE_GENI_STATUS		0x40
#define GENI_SER_M_CLK_CFG	0x48
#define GENI_SER_S_CLK_CFG	0x4c
#define GENI_IF_DISABLE_RO	0x64
#define GENI_FW_REVISION_RO	0x68
#define SE_GENI_CLK_SEL		0x7c
#define SE_UART_LOOPBACK_CFG	0x22c
#define SE_UART_TX_TRANS_CFG	0x25c
#define SE_UART_TX_WORD_LEN	0x268
#define SE_UART_TX_STOP_BIT_LEN	0x26c
#define SE_UART_RX_TRANS_CFG	0x280
#define SE_UART_RX_WORD_LEN	0x28c
#define SE_UART_RX_STALE_CNT	0x294
#define SE_UART_TX_PARITY_CFG	0x2a4
#define SE_UART_RX_PARITY_CFG	0x2a8
#define SE_UART_MANUAL_RFR	0x2ac
#define SE_GENI_DMA_MODE_EN	0x258
#define SE_GENI_M_IRQ_STATUS	0x610
#define SE_GENI_S_IRQ_STATUS	0x640
#define SE_GENI_IOS		0x908
#define SE_HW_PARAM_0		0xe24
#define SE_HW_PARAM_1		0xe28

#define GENI_PROTO_UART		2

static bool snapshot;
module_param(snapshot, bool, 0444);
MODULE_PARM_DESC(snapshot, "Read GENI UART and BT_EN state; binds nothing");

static unsigned int bt_en_gpio = 116;
module_param(bt_en_gpio, uint, 0444);
MODULE_PARM_DESC(bt_en_gpio, "TLMM pin of BTH0's GpioIo (read only)");

static void qcom0f16_snapshot_gpio(struct device *dev)
{
	void __iomem *pin;
	u32 ctl, io;

	if (bt_en_gpio >= 250)
		return;
	pin = ioremap(GLYMUR_TLMM_BASE + bt_en_gpio * TLMM_PIN_STRIDE, 0x10);
	if (!pin)
		return;
	ctl = readl_relaxed(pin + TLMM_CTL);
	io = readl_relaxed(pin + TLMM_IO);
	iounmap(pin);
	dev_info(dev,
		 "snapshot: gpio%u ctl=0x%08x mux=%u oe=%u pull=%u drive=%u io=0x%08x in=%u out=%u\n",
		 bt_en_gpio, ctl, (ctl >> 2) & 0xf, (ctl >> 9) & 1, ctl & 3,
		 (ctl >> 6) & 7, io, io & 1, (io >> 1) & 1);
}

static int qcom0f16_snapshot_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct resource *res;
	void __iomem *base;
	u32 rev, m_clk, s_clk, proto;

	if (!snapshot)
		return -ENODEV;

	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!res || resource_size(res) != GLYMUR_SE_SIZE ||
	    res->start < 0x00a80000 || res->start >= 0x00bc0000)
		return -ENODEV;

	base = ioremap(res->start, GLYMUR_SE_SIZE);
	if (!base)
		return -ENODEV;

	dev_info(dev, "snapshot: %pR starting read-only MMIO\n", res);
	rev = readl_relaxed(base + GENI_FW_REVISION_RO);
	proto = (rev >> 8) & 0xff;
	m_clk = readl_relaxed(base + GENI_SER_M_CLK_CFG);
	s_clk = readl_relaxed(base + GENI_SER_S_CLK_CFG);
	dev_info(dev,
		 "snapshot: rev=0x%08x proto=%u%s m_clk=0x%08x (en=%u div=%u) s_clk=0x%08x (en=%u div=%u) clk_sel=0x%08x\n",
		 rev, proto, proto == GENI_PROTO_UART ? " (UART)" : "",
		 m_clk, m_clk & 1, (m_clk >> 4) & 0xfff,
		 s_clk, s_clk & 1, (s_clk >> 4) & 0xfff,
		 readl_relaxed(base + SE_GENI_CLK_SEL));
	dev_info(dev,
		 "snapshot: if_disable=0x%08x dma=0x%08x status=0x%08x ios=0x%08x m_irq=0x%08x s_irq=0x%08x hw0=0x%08x hw1=0x%08x\n",
		 readl_relaxed(base + GENI_IF_DISABLE_RO),
		 readl_relaxed(base + SE_GENI_DMA_MODE_EN),
		 readl_relaxed(base + SE_GENI_STATUS),
		 readl_relaxed(base + SE_GENI_IOS),
		 readl_relaxed(base + SE_GENI_M_IRQ_STATUS),
		 readl_relaxed(base + SE_GENI_S_IRQ_STATUS),
		 readl_relaxed(base + SE_HW_PARAM_0),
		 readl_relaxed(base + SE_HW_PARAM_1));
	if (proto == GENI_PROTO_UART)
		dev_info(dev,
			 "snapshot: uart tx_cfg=0x%08x tx_word=%u tx_stop=%u rx_cfg=0x%08x rx_word=%u stale=%u tx_par=0x%08x rx_par=0x%08x rfr=0x%08x loopback=0x%08x\n",
			 readl_relaxed(base + SE_UART_TX_TRANS_CFG),
			 readl_relaxed(base + SE_UART_TX_WORD_LEN),
			 readl_relaxed(base + SE_UART_TX_STOP_BIT_LEN),
			 readl_relaxed(base + SE_UART_RX_TRANS_CFG),
			 readl_relaxed(base + SE_UART_RX_WORD_LEN),
			 readl_relaxed(base + SE_UART_RX_STALE_CNT),
			 readl_relaxed(base + SE_UART_TX_PARITY_CFG),
			 readl_relaxed(base + SE_UART_RX_PARITY_CFG),
			 readl_relaxed(base + SE_UART_MANUAL_RFR),
			 readl_relaxed(base + SE_UART_LOOPBACK_CFG));
	iounmap(base);

	if (res->start == GLYMUR_UR15_BASE)
		qcom0f16_snapshot_gpio(dev);
	return -ENODEV;
}

static const struct acpi_device_id qcom0f16_snapshot_acpi_match[] = {
	{ "QCOM0F16" },
	{ }
};
MODULE_DEVICE_TABLE(acpi, qcom0f16_snapshot_acpi_match);

static struct platform_driver qcom0f16_snapshot_driver = {
	.probe = qcom0f16_snapshot_probe,
	.driver = {
		.name = "qcom0f16_snapshot",
		.acpi_match_table = qcom0f16_snapshot_acpi_match,
	},
};
module_platform_driver(qcom0f16_snapshot_driver);

MODULE_DESCRIPTION("Read-only HP Glymur GENI UART and BT_EN snapshot");
MODULE_LICENSE("GPL");
