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
 * direction and level, the UART pins 56-59 (from HP's BSRC_UART_4Wire_1.bin)
 * and the GCC state of the SE6 serial clock: rate generator, divider,
 * branch and vote. HP's PEP recipe steps that clock through 7.3728-100 MHz
 * at runtime, which ACPI gives Linux no way to do. It also covers
 * \_SB.UARD (QUP_2_SE_5, debug).
 *
 * Safety:
 *  - default-off (snapshot=1 required);
 *  - only the known QCOM0F16 windows are mapped;
 *  - MMIO reads only (SE, one TLMM pin at a time, a GCC window): no writes,
 *    no IRQ, clock, pinctrl or GPIO requests;
 *  - probe always returns -ENODEV, so nothing binds and nothing is left
 *    configured.
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

/*
 * GCC state of the UR15 serial clock (offsets from qcom-next gcc-glymur.c):
 * gcc_qupv3_wrap1_qspi_s6_clk_src RCG at 0xb366c (CMD, CFG, M, N, D),
 * gcc_qupv3_wrap1_s6_clk_src divider at 0xb352c, and the
 * gcc_qupv3_wrap1_s6_clk branch (status 0xb351c, vote 0x62018 bit 21).
 * CFG source 0 = TCXO 19.2 MHz, 1 = GPLL0 main, 4 = GPLL1, 6 = GPLL0 even.
 */
#define GLYMUR_GCC_BASE		0x00100000
#define GCC_S6_RCG		0xb366c
#define GCC_S6_DIV		0xb352c
#define GCC_S6_CBCR		0xb351c
#define GCC_QUPV3_VOTE		0x62018

static void qcom0f16_snapshot_gcc(struct device *dev)
{
	void __iomem *gcc;
	u32 cmd, cfg, m, n, d, div, cbcr, vote;

	gcc = ioremap(GLYMUR_GCC_BASE, 0xc0000);
	if (!gcc)
		return;
	cmd = readl_relaxed(gcc + GCC_S6_RCG);
	cfg = readl_relaxed(gcc + GCC_S6_RCG + 0x4);
	m = readl_relaxed(gcc + GCC_S6_RCG + 0x8);
	n = readl_relaxed(gcc + GCC_S6_RCG + 0xc);
	d = readl_relaxed(gcc + GCC_S6_RCG + 0x10);
	div = readl_relaxed(gcc + GCC_S6_DIV);
	cbcr = readl_relaxed(gcc + GCC_S6_CBCR);
	vote = readl_relaxed(gcc + GCC_QUPV3_VOTE);
	iounmap(gcc);
	dev_info(dev,
		 "snapshot: gcc s6 rcg cmd=0x%08x (root_off=%u) cfg=0x%08x (src=%u hid=%u mode=%u) m=0x%x n=0x%x d=0x%x div=0x%x cbcr=0x%08x (clk_off=%u) vote=0x%08x (s6=%u)\n",
		 cmd, (cmd >> 31) & 1, cfg, (cfg >> 8) & 7, cfg & 0x1f,
		 (cfg >> 12) & 3, m, n, d, div, cbcr, (cbcr >> 31) & 1,
		 vote, (vote >> 21) & 1);
}

/* UR15's UART lines per HP's BSRC_UART_4Wire_1.bin TLMMGPIO actions. */
static const unsigned int ur15_pins[] = { 56, 57, 58, 59 };

/*
 * Device-tree evidence: candidate pins whose firmware state (mux, direction,
 * level) confirms the board wiring, read once. Defaults: PCIe4/5 PERST# and
 * WAKE# (146, 148, 152, 154; CLKREQ# 147/153 are in HP's PEP tables), WLAN
 * enable 117, eDP power/enable/HPD 70/18/119, USB 72, lid 92, EC event 66,
 * keyboard 67, touchpad 3, touchscreen 51 and a possible touchscreen reset
 * 48. None is in the secure ranges (4-7, 10-11, 44-47, 90).
 */
static unsigned int dt_pins[32] = { 146, 147, 148, 152, 153, 154, 117, 70, 18,
				    119, 72, 92, 66, 67, 3, 51, 48 };
static int dt_pins_count = 17;
module_param_array_named(dt_pins, dt_pins, uint, &dt_pins_count, 0444);
MODULE_PARM_DESC(dt_pins, "Extra TLMM pins to read (read only)");

static void qcom0f16_snapshot_pin(struct device *dev, unsigned int gpio)
{
	void __iomem *pin;
	u32 ctl, io;

	/*
	 * Never read pins the secure world may own (reference-design reserved
	 * ranges: secure I3C 4-7, OOB UART 10-11, TPM SPI 44-47, TPM 90).
	 */
	if (gpio >= 250 || (gpio >= 4 && gpio <= 7) || gpio == 10 || gpio == 11 ||
	    (gpio >= 44 && gpio <= 47) || gpio == 90) {
		dev_info(dev, "snapshot: gpio%u skipped (reserved or out of range)\n", gpio);
		return;
	}
	pin = ioremap(GLYMUR_TLMM_BASE + gpio * TLMM_PIN_STRIDE, 0x10);
	if (!pin)
		return;
	ctl = readl_relaxed(pin + TLMM_CTL);
	io = readl_relaxed(pin + TLMM_IO);
	iounmap(pin);
	dev_info(dev,
		 "snapshot: gpio%u ctl=0x%08x mux=%u oe=%u pull=%u drive=%u io=0x%08x in=%u out=%u\n",
		 gpio, ctl, (ctl >> 2) & 0xf, (ctl >> 9) & 1, ctl & 3,
		 (ctl >> 6) & 7, io, io & 1, (io >> 1) & 1);
}

static int qcom0f16_snapshot_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct resource *res;
	void __iomem *base;
	u32 rev, m_clk, s_clk, proto;
	unsigned int bt_pin;

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

	if (res->start == GLYMUR_UR15_BASE) {
		qcom0f16_snapshot_gcc(dev);
		for (bt_pin = 0; bt_pin < ARRAY_SIZE(ur15_pins); bt_pin++)
			qcom0f16_snapshot_pin(dev, ur15_pins[bt_pin]);
		qcom0f16_snapshot_pin(dev, bt_en_gpio);
		for (bt_pin = 0; bt_pin < dt_pins_count; bt_pin++)
			qcom0f16_snapshot_pin(dev, dt_pins[bt_pin]);
	}
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
