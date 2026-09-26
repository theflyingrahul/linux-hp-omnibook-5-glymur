// SPDX-License-Identifier: GPL-2.0-only
/*
 * HP OmniBook 5 (Glymur) ACPI TLMM GPIO/interrupt test driver.
 *
 * The HP firmware describes the TLMM as ACPI GIO0 (QCOM0F0C). Its keyboard
 * and touchpad GpioInt resources use PDC-encoded pins (704, 896): pin / 64
 * selects a GIO0._CRS ExtendedIRQ slot and the CIPR package from GIO0._DSM
 * maps that slot's PDC IRQ to a physical GPIO. This follows OpenBSD's
 * qcgpio(4) and is needed because the in-tree pinctrl-msm driver has no
 * ACPI match and is built into the stock Ubuntu kernel.
 *
 * Scope is deliberately narrow for a live-media experiment:
 *  - default-off (enable=1 required);
 *  - only allow-listed physical pins are ever accessed;
 *  - pins are read-only: no output, mux, pull, or drive changes;
 *  - interrupts use the TLMM summary line (first GIO0 IRQ) with the
 *    Glymur intr_cfg layout from pinctrl-glymur.c (target KPSS = 3);
 *  - GIO0._AEI events are not requested.
 */

#include <linux/acpi.h>
#include <linux/bitfield.h>
#include <linux/bitmap.h>
#include <linux/gpio/driver.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/irq.h>
#include <linux/irqdomain.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/spinlock.h>
#include <linux/string.h>
#include <linux/uuid.h>

#define GLYMUR_TLMM_BASE	0x0f100000
#define GLYMUR_NR_PINS		250
#define TLMM_PIN_STRIDE		0x1000

#define TLMM_CTL		0x0
#define TLMM_IO			0x4
#define TLMM_INTR_CFG		0x8
#define TLMM_INTR_STATUS	0xc

#define CTL_MUX			GENMASK(5, 2)
#define CTL_OE			BIT(9)
#define IO_IN			BIT(0)
#define INTR_EN			BIT(0)
#define INTR_POL_HIGH		BIT(1)
#define INTR_DET		GENMASK(3, 2)
#define INTR_RAW		BIT(4)
#define INTR_TARGET		GENMASK(7, 5)
#define INTR_TARGET_KPSS	3
#define INTR_STATUS		BIT(0)

#define PDC_SLOT_PINS		64
#define MAX_PDC_SLOTS		16
#define NR_ACPI_PINS		(MAX_PDC_SLOTS * PDC_SLOT_PINS)
#define NO_HWIRQ		0xffff

static bool enable;
module_param(enable, bool, 0444);
MODULE_PARM_DESC(enable, "Bind GIO0; the module does nothing unless set");

static char *pins = "3,51,67,92";
module_param(pins, charp, 0444);
MODULE_PARM_DESC(pins, "Comma-separated physical GPIOs this driver may access");

/* 921b0fd4-567c-43a0-bb14-2648f7b2a18c: PDC CIPR table, function 2 */
static const guid_t glymur_pdc_guid =
	GUID_INIT(0x921b0fd4, 0x567c, 0x43a0,
		  0xbb, 0x14, 0x26, 0x48, 0xf7, 0xb2, 0xa1, 0x8c);
/* 98b9b2a4-1663-4a5f-82f2-c6c99a394726: GPIO count, function 2 */
static const guid_t glymur_count_guid =
	GUID_INIT(0x98b9b2a4, 0x1663, 0x4a5f,
		  0x82, 0xf2, 0xc6, 0xc9, 0x9a, 0x39, 0x47, 0x26);

struct glymur_gpio {
	struct device *dev;
	struct gpio_chip gc;
	struct irq_domain *domain;
	struct fwnode_handle *domain_fwnode;
	void __iomem *base;
	raw_spinlock_t lock;
	unsigned int nslots;
	u32 slot_irq[MAX_PDC_SLOTS];
	int slot_pin[MAX_PDC_SLOTS];
	u16 pin_hwirq[GLYMUR_NR_PINS];
	DECLARE_BITMAP(allowed, GLYMUR_NR_PINS);
	DECLARE_BITMAP(irq_on, GLYMUR_NR_PINS);
};

static void __iomem *glymur_reg(struct glymur_gpio *g, unsigned int pin,
				unsigned int reg)
{
	return g->base + pin * TLMM_PIN_STRIDE + reg;
}

/* ACPI pin (GPIO chip offset) -> allow-listed physical pin, or -EINVAL. */
static int glymur_pin(struct glymur_gpio *g, unsigned int offset)
{
	unsigned int slot;
	int pin;

	if (offset < GLYMUR_NR_PINS) {
		pin = offset;
	} else {
		slot = offset / PDC_SLOT_PINS;
		if (offset % PDC_SLOT_PINS || slot >= g->nslots)
			return -EINVAL;
		pin = g->slot_pin[slot];
		if (pin < 0)
			return -EINVAL;
	}

	return test_bit(pin, g->allowed) ? pin : -EINVAL;
}

static int glymur_init_valid_mask(struct gpio_chip *gc, unsigned long *valid,
				  unsigned int ngpios)
{
	struct glymur_gpio *g = gpiochip_get_data(gc);
	unsigned int offset;

	bitmap_zero(valid, ngpios);
	for (offset = 0; offset < ngpios; offset++)
		if (glymur_pin(g, offset) >= 0)
			set_bit(offset, valid);

	return 0;
}

static int glymur_get_direction(struct gpio_chip *gc, unsigned int offset)
{
	struct glymur_gpio *g = gpiochip_get_data(gc);
	int pin = glymur_pin(g, offset);

	if (pin < 0)
		return pin;

	return readl(glymur_reg(g, pin, TLMM_CTL)) & CTL_OE ?
		GPIO_LINE_DIRECTION_OUT : GPIO_LINE_DIRECTION_IN;
}

/* Never reconfigure firmware pins: accept only pins already muxed as inputs. */
static int glymur_direction_input(struct gpio_chip *gc, unsigned int offset)
{
	struct glymur_gpio *g = gpiochip_get_data(gc);
	int pin = glymur_pin(g, offset);
	u32 ctl;

	if (pin < 0)
		return pin;

	ctl = readl(glymur_reg(g, pin, TLMM_CTL));
	if (ctl & CTL_OE || FIELD_GET(CTL_MUX, ctl)) {
		dev_warn(g->dev, "GPIO %d is not a firmware input (ctl=0x%08x)\n",
			 pin, ctl);
		return -EPERM;
	}

	return 0;
}

static int glymur_get(struct gpio_chip *gc, unsigned int offset)
{
	struct glymur_gpio *g = gpiochip_get_data(gc);
	int pin = glymur_pin(g, offset);

	if (pin < 0)
		return pin;

	return !!(readl(glymur_reg(g, pin, TLMM_IO)) & IO_IN);
}

static int glymur_to_irq(struct gpio_chip *gc, unsigned int offset)
{
	struct glymur_gpio *g = gpiochip_get_data(gc);

	if (glymur_pin(g, offset) < 0)
		return -EINVAL;

	return irq_create_mapping(g->domain, offset);
}

static void glymur_irq_mask(struct irq_data *d)
{
	struct glymur_gpio *g = irq_data_get_irq_chip_data(d);
	int pin = glymur_pin(g, irqd_to_hwirq(d));
	unsigned long flags;
	u32 val;

	if (pin < 0)
		return;

	raw_spin_lock_irqsave(&g->lock, flags);
	val = readl(glymur_reg(g, pin, TLMM_INTR_CFG));
	writel(val & ~INTR_EN, glymur_reg(g, pin, TLMM_INTR_CFG));
	clear_bit(pin, g->irq_on);
	raw_spin_unlock_irqrestore(&g->lock, flags);
}

static void glymur_irq_unmask(struct irq_data *d)
{
	struct glymur_gpio *g = irq_data_get_irq_chip_data(d);
	int pin = glymur_pin(g, irqd_to_hwirq(d));
	unsigned long flags;
	u32 val;

	if (pin < 0)
		return;

	raw_spin_lock_irqsave(&g->lock, flags);
	val = readl(glymur_reg(g, pin, TLMM_INTR_CFG));
	writel(val | INTR_RAW | INTR_EN, glymur_reg(g, pin, TLMM_INTR_CFG));
	set_bit(pin, g->irq_on);
	raw_spin_unlock_irqrestore(&g->lock, flags);
}

static void glymur_irq_ack(struct irq_data *d)
{
	struct glymur_gpio *g = irq_data_get_irq_chip_data(d);
	int pin = glymur_pin(g, irqd_to_hwirq(d));

	/* Glymur has no intr_ack_high: writing 0 clears the latched status. */
	if (pin >= 0)
		writel(0, glymur_reg(g, pin, TLMM_INTR_STATUS));
}

static int glymur_irq_set_type(struct irq_data *d, unsigned int type)
{
	struct glymur_gpio *g = irq_data_get_irq_chip_data(d);
	irq_hw_number_t hwirq = irqd_to_hwirq(d);
	int pin = glymur_pin(g, hwirq);
	unsigned long flags;
	u32 val, sense;

	if (pin < 0)
		return -EINVAL;

	switch (type & IRQ_TYPE_SENSE_MASK) {
	case IRQ_TYPE_EDGE_RISING:
		sense = FIELD_PREP(INTR_DET, 1) | INTR_POL_HIGH;
		break;
	case IRQ_TYPE_EDGE_FALLING:
		sense = FIELD_PREP(INTR_DET, 2) | INTR_POL_HIGH;
		break;
	case IRQ_TYPE_EDGE_BOTH:
		sense = FIELD_PREP(INTR_DET, 3) | INTR_POL_HIGH;
		break;
	case IRQ_TYPE_LEVEL_HIGH:
		sense = INTR_POL_HIGH;
		break;
	case IRQ_TYPE_LEVEL_LOW:
		sense = 0;
		break;
	default:
		return -EINVAL;
	}

	raw_spin_lock_irqsave(&g->lock, flags);
	if (g->pin_hwirq[pin] != NO_HWIRQ && g->pin_hwirq[pin] != hwirq) {
		raw_spin_unlock_irqrestore(&g->lock, flags);
		return -EBUSY;
	}
	val = readl(glymur_reg(g, pin, TLMM_INTR_CFG));
	val &= ~(INTR_TARGET | INTR_DET | INTR_POL_HIGH);
	val |= FIELD_PREP(INTR_TARGET, INTR_TARGET_KPSS) | INTR_RAW | sense;
	writel(val, glymur_reg(g, pin, TLMM_INTR_CFG));
	writel(0, glymur_reg(g, pin, TLMM_INTR_STATUS));
	g->pin_hwirq[pin] = hwirq;
	raw_spin_unlock_irqrestore(&g->lock, flags);

	if (type & IRQ_TYPE_LEVEL_MASK)
		irq_set_handler_locked(d, handle_level_irq);
	else
		irq_set_handler_locked(d, handle_edge_irq);

	dev_info(g->dev, "ACPI pin %lu -> GPIO %d: type 0x%x, intr_cfg 0x%08x\n",
		 hwirq, pin, type, val);
	return 0;
}

static const struct irq_chip glymur_irq_chip = {
	.name		= "glymur-acpi-tlmm",
	.irq_ack	= glymur_irq_ack,
	.irq_mask	= glymur_irq_mask,
	.irq_unmask	= glymur_irq_unmask,
	.irq_set_type	= glymur_irq_set_type,
	.flags		= IRQCHIP_IMMUTABLE | IRQCHIP_SKIP_SET_WAKE,
};

static int glymur_domain_map(struct irq_domain *domain, unsigned int virq,
			     irq_hw_number_t hwirq)
{
	struct glymur_gpio *g = domain->host_data;

	if (glymur_pin(g, hwirq) < 0)
		return -EINVAL;

	irq_set_chip_data(virq, g);
	irq_set_chip_and_handler(virq, &glymur_irq_chip, handle_level_irq);
	irq_set_noprobe(virq);
	return 0;
}

static const struct irq_domain_ops glymur_domain_ops = {
	.map = glymur_domain_map,
};

static irqreturn_t glymur_summary(int irq, void *data)
{
	struct glymur_gpio *g = data;
	unsigned int pin;
	int handled = 0;

	for_each_set_bit(pin, g->irq_on, GLYMUR_NR_PINS) {
		if (readl(glymur_reg(g, pin, TLMM_INTR_STATUS)) & INTR_STATUS) {
			generic_handle_domain_irq(g->domain, g->pin_hwirq[pin]);
			handled++;
		}
	}

	/* IRQ_NONE lets the core disable a line that a foreign pin floods. */
	return handled ? IRQ_HANDLED : IRQ_NONE;
}

static acpi_status glymur_crs_irq(struct acpi_resource *res, void *context)
{
	struct glymur_gpio *g = context;
	struct acpi_resource_extended_irq *irq;

	if (res->type != ACPI_RESOURCE_TYPE_EXTENDED_IRQ)
		return AE_OK;

	irq = &res->data.extended_irq;
	if (irq->interrupt_count != 1 || g->nslots >= MAX_PDC_SLOTS)
		return AE_BAD_DATA;

	g->slot_pin[g->nslots] = -1;
	g->slot_irq[g->nslots++] = irq->interrupts[0];
	return AE_OK;
}

static int glymur_parse_acpi(struct glymur_gpio *g)
{
	acpi_handle handle = ACPI_HANDLE(g->dev);
	union acpi_object *obj, *entry;
	unsigned int i, j;
	u64 pin, irq;
	int ret = 0;

	obj = acpi_evaluate_dsm_typed(handle, &glymur_count_guid, 0, 2, NULL,
				      ACPI_TYPE_INTEGER);
	if (!obj)
		return dev_err_probe(g->dev, -ENODEV, "GPIO count _DSM failed\n");
	if (obj->integer.value != GLYMUR_NR_PINS)
		ret = -ENODEV;
	ACPI_FREE(obj);
	if (ret)
		return dev_err_probe(g->dev, ret, "unexpected ACPI GPIO count\n");

	if (ACPI_FAILURE(acpi_walk_resources(handle, METHOD_NAME__CRS,
					     glymur_crs_irq, g)) || !g->nslots)
		return dev_err_probe(g->dev, -ENODEV, "invalid GIO0._CRS IRQs\n");

	obj = acpi_evaluate_dsm_typed(handle, &glymur_pdc_guid, 0, 2, NULL,
				      ACPI_TYPE_PACKAGE);
	if (!obj)
		return dev_err_probe(g->dev, -ENODEV, "PDC _DSM failed\n");

	for (i = 0; i < obj->package.count && !ret; i++) {
		entry = &obj->package.elements[i];
		if (entry->type != ACPI_TYPE_PACKAGE || entry->package.count != 3 ||
		    entry->package.elements[1].type != ACPI_TYPE_INTEGER ||
		    entry->package.elements[2].type != ACPI_TYPE_INTEGER) {
			ret = -EINVAL;
			break;
		}
		pin = entry->package.elements[1].integer.value;
		irq = entry->package.elements[2].integer.value;
		if (pin >= GLYMUR_NR_PINS) {
			ret = -EINVAL;
			break;
		}
		/* First matching slot, as in OpenBSD; a second CIPR row is ambiguous. */
		for (j = 0; j < g->nslots; j++) {
			if (g->slot_irq[j] != irq)
				continue;
			if (g->slot_pin[j] >= 0)
				ret = -EINVAL;
			else
				g->slot_pin[j] = pin;
			break;
		}
	}
	ACPI_FREE(obj);
	if (ret)
		return dev_err_probe(g->dev, ret, "malformed PDC CIPR table\n");

	for (j = 0; j < g->nslots; j++)
		if (g->slot_pin[j] >= 0 && j * PDC_SLOT_PINS >= GLYMUR_NR_PINS)
			dev_info(g->dev, "PDC slot %u: ACPI pin %u -> IRQ %u -> GPIO %d\n",
				 j, j * PDC_SLOT_PINS, g->slot_irq[j], g->slot_pin[j]);
	return 0;
}

static int glymur_parse_allowlist(struct glymur_gpio *g)
{
	char *list, *cursor, *token;
	unsigned int pin;
	int ret = 0;

	list = kstrdup(pins ? pins : "", GFP_KERNEL);
	if (!list)
		return -ENOMEM;

	cursor = list;
	while ((token = strsep(&cursor, ",")) != NULL) {
		if (!*token)
			continue;
		ret = kstrtouint(token, 0, &pin);
		if (ret || pin >= GLYMUR_NR_PINS) {
			ret = -EINVAL;
			break;
		}
		set_bit(pin, g->allowed);
	}
	kfree(list);
	return ret;
}

static void glymur_remove_domain(void *data)
{
	struct glymur_gpio *g = data;
	unsigned int offset;

	for (offset = 0; offset < NR_ACPI_PINS; offset++)
		irq_dispose_mapping(irq_find_mapping(g->domain, offset));
	irq_domain_remove(g->domain);
	irq_domain_free_fwnode(g->domain_fwnode);
}

static int glymur_gpio_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct glymur_gpio *g;
	struct resource *res;
	unsigned int pin;
	int irq, ret;

	if (!enable)
		return -ENODEV;

	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!res || res->start != GLYMUR_TLMM_BASE ||
	    resource_size(res) < GLYMUR_NR_PINS * TLMM_PIN_STRIDE)
		return dev_err_probe(dev, -ENODEV, "unexpected GIO0 MMIO resource\n");

	g = devm_kzalloc(dev, sizeof(*g), GFP_KERNEL);
	if (!g)
		return -ENOMEM;
	g->dev = dev;
	raw_spin_lock_init(&g->lock);
	memset(g->pin_hwirq, 0xff, sizeof(g->pin_hwirq));

	ret = glymur_parse_allowlist(g);
	if (ret)
		return dev_err_probe(dev, ret, "invalid pins= list\n");
	ret = glymur_parse_acpi(g);
	if (ret)
		return ret;

	g->base = devm_ioremap(dev, res->start, GLYMUR_NR_PINS * TLMM_PIN_STRIDE);
	if (!g->base)
		return -ENOMEM;

	/*
	 * Record the firmware state of allowed pins. Only a pin already routed
	 * to the application processor can raise the summary line before a
	 * consumer owns it, so only such a pin is masked and cleared here.
	 */
	for_each_set_bit(pin, g->allowed, GLYMUR_NR_PINS) {
		u32 ctl = readl(glymur_reg(g, pin, TLMM_CTL));
		u32 cfg = readl(glymur_reg(g, pin, TLMM_INTR_CFG));
		u32 sts = readl(glymur_reg(g, pin, TLMM_INTR_STATUS));
		u32 io = readl(glymur_reg(g, pin, TLMM_IO));
		bool routed = FIELD_GET(INTR_TARGET, cfg) == INTR_TARGET_KPSS &&
			      (cfg & INTR_EN);

		dev_info(dev, "GPIO %u firmware state: ctl=0x%08x io=0x%08x intr_cfg=0x%08x status=0x%08x%s\n",
			 pin, ctl, io, cfg, sts, routed ? " (masked)" : "");
		if (routed) {
			writel(cfg & ~INTR_EN, glymur_reg(g, pin, TLMM_INTR_CFG));
			writel(0, glymur_reg(g, pin, TLMM_INTR_STATUS));
		}
	}

	g->domain_fwnode = irq_domain_alloc_named_fwnode("glymur-acpi-tlmm");
	if (!g->domain_fwnode)
		return -ENOMEM;
	g->domain = irq_domain_create_linear(g->domain_fwnode, NR_ACPI_PINS,
					     &glymur_domain_ops, g);
	if (!g->domain) {
		irq_domain_free_fwnode(g->domain_fwnode);
		return -ENOMEM;
	}
	ret = devm_add_action_or_reset(dev, glymur_remove_domain, g);
	if (ret)
		return ret;

	irq = platform_get_irq(pdev, 0);
	if (irq < 0)
		return irq;
	ret = devm_request_irq(dev, irq, glymur_summary, IRQF_NO_THREAD,
			       dev_name(dev), g);
	if (ret)
		return dev_err_probe(dev, ret, "summary IRQ %d\n", irq);

	g->gc.label = "glymur-acpi-tlmm";
	g->gc.parent = dev;
	g->gc.fwnode = dev_fwnode(dev);
	g->gc.owner = THIS_MODULE;
	g->gc.base = -1;
	g->gc.ngpio = NR_ACPI_PINS;
	g->gc.init_valid_mask = glymur_init_valid_mask;
	g->gc.get_direction = glymur_get_direction;
	g->gc.direction_input = glymur_direction_input;
	g->gc.get = glymur_get;
	g->gc.to_irq = glymur_to_irq;

	ret = devm_gpiochip_add_data(dev, &g->gc, g);
	if (ret)
		return dev_err_probe(dev, ret, "gpiochip registration failed\n");

	dev_info(dev, "registered: summary IRQ %d, %u PDC slots, pins=%s\n",
		 irq, g->nslots, pins);
	return 0;
}

static const struct acpi_device_id glymur_gpio_acpi_match[] = {
	{ "QCOM0F0C" },
	{ }
};
MODULE_DEVICE_TABLE(acpi, glymur_gpio_acpi_match);

static struct platform_driver glymur_gpio_driver = {
	.probe = glymur_gpio_probe,
	.driver = {
		.name = "glymur_acpi_gpio",
		.acpi_match_table = glymur_gpio_acpi_match,
		.suppress_bind_attrs = true,
	},
};
module_platform_driver(glymur_gpio_driver);

MODULE_DESCRIPTION("HP Glymur ACPI TLMM GPIO/IRQ test driver");
MODULE_LICENSE("GPL");
