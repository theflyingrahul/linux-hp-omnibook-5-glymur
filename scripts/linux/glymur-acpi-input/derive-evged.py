"""Add GpioInt event support to Linux v7.0 drivers/acpi/evged.c.

Usage: derive-evged.py <evged.c> <out.c> [--module]

The Generic Event Device driver only accepts Interrupt() resources. HP's
Glymur firmware signals EC events (\\_SB.ECGE) and lid changes (\\_SB.LIGE)
through ACPI0013 devices whose _CRS holds GpioInt() resources, which Windows
accepts. This change maps each GpioInt through acpi_dev_gpio_irq_get(), runs
_EVT with the GPIO pin number, propagates -EPROBE_DEFER while the GPIO
controller is missing, and frees already requested IRQs when a later
resource fails.

Without --module the output is the patched in-tree file (for the upstream
patch). With --module it becomes glymur_acpi_ged.ko, a test driver that binds
ACPI0013 devices the built-in acpi-ged driver failed to probe.
"""
import hashlib
import sys

src_path, out_path = sys.argv[1], sys.argv[2]
module = sys.argv[3:] == ['--module']
assert sys.argv[3:] in ([], ['--module']), 'usage: derive-evged.py <evged.c> <out.c> [--module]'
src = open(src_path, encoding='utf-8').read()
assert hashlib.sha256(src.encode()).hexdigest() == \
    '86fb002e3b41f5890d4ca7c98e46868442fb1369c4949dc9db3dc6480734ae33', 'unexpected source'


def sub(old, new, count=1):
    global src
    assert src.count(old) == count, f'pattern count {src.count(old)} != {count}: {old[:60]!r}'
    src = src.replace(old, new)


sub('''struct acpi_ged_device {
	struct device *dev;
	struct list_head event_list;
};''', '''struct acpi_ged_device {
	struct device *dev;
	struct list_head event_list;
	unsigned int gpio_index;
	int error;
};''')

sub('''	struct resource r;
	struct acpi_resource_irq *p = &ares->data.irq;''', '''	struct resource r = {};
	struct acpi_resource_irq *p = &ares->data.irq;''')

sub('''	if (ares->type == ACPI_RESOURCE_TYPE_END_TAG)
		return AE_OK;

	if (!acpi_dev_resource_interrupt(ares, 0, &r)) {''', '''	if (ares->type == ACPI_RESOURCE_TYPE_END_TAG)
		return AE_OK;

	if (ares->type == ACPI_RESOURCE_TYPE_GPIO) {
		struct acpi_resource_gpio *agpio;
		int ret;

		/* GpioIo resources are not event sources. */
		if (!acpi_gpio_get_irq_resource(ares, &agpio))
			return AE_OK;

		/* The GPIO core applies the GpioInt trigger and polarity. */
		ret = acpi_dev_gpio_irq_get(ACPI_COMPANION(dev), geddev->gpio_index++);
		if (ret < 0) {
			geddev->error = ret;
			return AE_ERROR;
		}
		irq = ret;
		gsi = agpio->pin_table[0];
		if (agpio->shareable == ACPI_SHARED)
			r.flags |= IORESOURCE_IRQ_SHAREABLE;

		/* As for GSIs above 255, GPIO-signaled events use _EVT. */
		if (ACPI_FAILURE(acpi_get_handle(handle, "_EVT", &evt_handle))) {
			dev_err(dev, "cannot locate _EVT method\\n");
			return AE_ERROR;
		}
		goto request;
	}

	if (!acpi_dev_resource_interrupt(ares, 0, &r)) {''')

sub('''	event = devm_kzalloc(dev, sizeof(*event), GFP_KERNEL);''', '''request:
	event = devm_kzalloc(dev, sizeof(*event), GFP_KERNEL);''')

# ged_shutdown() is defined after ged_probe(); declare the helper it now uses.
sub('''static int ged_probe(struct platform_device *pdev)
{''', '''static void acpi_ged_free_events(struct acpi_ged_device *geddev);

static int ged_probe(struct platform_device *pdev)
{''')
sub('''	if (ACPI_FAILURE(acpi_ret)) {
		dev_err(&pdev->dev, "unable to parse the _CRS record\\n");
		return -EINVAL;
	}''', '''	if (ACPI_FAILURE(acpi_ret)) {
		acpi_ged_free_events(geddev);
		if (geddev->error)
			return dev_err_probe(&pdev->dev, geddev->error,
					     "unable to get GPIO event IRQ\\n");
		dev_err(&pdev->dev, "unable to parse the _CRS record\\n");
		return -EINVAL;
	}''')
sub('''static void ged_shutdown(struct platform_device *pdev)
{
	struct acpi_ged_device *geddev = platform_get_drvdata(pdev);
	struct acpi_ged_event *event, *next;
''', '''static void acpi_ged_free_events(struct acpi_ged_device *geddev)
{
	struct acpi_ged_event *event, *next;
''')
sub('''			 event->gsi, event->irq);
	}
}
''', '''			 event->gsi, event->irq);
	}
}

static void ged_shutdown(struct platform_device *pdev)
{
	acpi_ged_free_events(platform_get_drvdata(pdev));
}
''')

if module:
    sub('#define MODULE_NAME\t"acpi-ged"\n', '#define MODULE_NAME\t"glymur_acpi_ged"\n')
    sub('builtin_platform_driver(ged_driver);\n',
        'module_platform_driver(ged_driver);\n'
        'MODULE_DESCRIPTION("ACPI GED test driver with GpioInt events (derived from evged.c)");\n'
        'MODULE_LICENSE("GPL");\n')

open(out_path, 'w', encoding='utf-8', newline='\n').write(src)
