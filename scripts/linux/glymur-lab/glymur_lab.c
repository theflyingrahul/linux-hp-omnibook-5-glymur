// SPDX-License-Identifier: GPL-2.0-only
/*
 * glymur_lab: display-lab helper for the HP OmniBook 5 16-bf1xxx.
 *
 * Loaded only by scripts/linux/glymur-lab on a boot of the display-lab
 * device tree (mahua-hp-omnibook-5-bf1xxx-lab.dtb). Everything goes through
 * debugfs (root only) under /sys/kernel/debug/glymur-lab/:
 *
 *   snapshot        read: the firmware's eDP state. MMIO reads only, no
 *                   writes. The DP3 controller and PHY are read only when
 *                   dispcc reports the MDSS GDSC on and the MDSS AHB, DP3
 *                   link and DP3 aux clocks running; the AUX data region is
 *                   never read (reads pop its FIFO).
 *   overlay         write: a compiled overlay (.dtbo), applied when the file
 *                   is closed (of_overlay_fdt_apply).
 *   overlay_remove  write "last" or an id: of_overlay_remove.
 *   overlays        read: applied overlay ids.
 *   dp_out          write "data-lanes=0,1" and/or
 *                   "link-frequencies=1620000000,2700000000": updates the
 *                   eDP endpoint (label mdss_dp3_out) through an
 *                   of_changeset; read: current values.
 *   dp_out_reset    write anything: revert every dp_out change.
 *
 * Device-tree changes take effect when the display drivers next probe; the
 * lab script unbinds and rebinds msm-mdss around them.
 */

#include <linux/debugfs.h>
#include <linux/io.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/seq_file.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/uaccess.h>
#include <linux/vmalloc.h>

#define DISPCC_BASE		0x0af00000
#define DISPCC_SIZE		0x10000
#define DISPCC_MDSS_GDSCR	0x9000
#define DISPCC_MDSS_AHB_CBCR	0x80b0
#define DISPCC_DPTX3_PIXEL0_CBCR 0x809c
#define DISPCC_DPTX3_LINK_CBCR	0x80a0
#define DISPCC_DPTX3_LINK_INTF_CBCR 0x80a4
#define DISPCC_DPTX3_AUX_CBCR	0x80a8
#define DISPCC_DPTX3_PIXEL0_RCG	0x8314
#define DISPCC_DPTX3_LINK_RCG	0x832c
#define DISPCC_DPTX3_AUX_RCG	0x8348
#define CBCR_CLK_OFF		BIT(31)
#define GDSC_PWR_ON		BIT(31)

#define TCSR_BASE		0x01fd5000
#define TCSR_EDP_CLKREF		0x60

#define TLMM_BASE		0x0f100000
#define TLMM_PIN_STRIDE		0x1000

struct lab_region {
	const char *name;
	phys_addr_t base;
	size_t size;
};

/* glymur.dtsi mdss_dp3 (regions 0, 2, 3; region 1 is AUX) and mdss_dp3_phy. */
static const struct lab_region dp3_regions[] = {
	{ "dp3-ahb",  0x0af6c000, 0x200 },
	{ "dp3-link", 0x0af6d000, 0xc00 },
	{ "dp3-p0",   0x0af6e000, 0x400 },
	{ "phy-dp",   0x00faac00, 0x1d0 },
	{ "phy-tx0",  0x00faa400, 0x128 },
	{ "phy-tx1",  0x00faa800, 0x128 },
	{ "phy-pll",  0x00faa000, 0x358 },
};

/* eDP pins from HP's PEP GPU0 recipe: enable 18, power 70, HPD 119. */
static const unsigned int edp_pins[] = { 18, 70, 119 };

static DEFINE_MUTEX(lab_lock);
static struct dentry *lab_dir;

#define MAX_OVERLAYS 16
static int ovcs_ids[MAX_OVERLAYS];
static int ovcs_count;

#define MAX_DP_CHANGES 16
static struct of_changeset *dp_changes[MAX_DP_CHANGES];
static int dp_change_count;

struct overlay_buf {
	char *data;
	size_t len;
	size_t cap;
};

static u32 rd(void __iomem *base, u32 off)
{
	return readl_relaxed(base + off);
}

static void dump_region(struct seq_file *s, const struct lab_region *r)
{
	void __iomem *base = ioremap(r->base, r->size);
	size_t off;

	if (!base) {
		seq_printf(s, "%s: ioremap failed\n", r->name);
		return;
	}
	seq_printf(s, "[%s %pa +0x%zx]\n", r->name, &r->base, r->size);
	for (off = 0; off < r->size; off += 16) {
		size_t i;

		seq_printf(s, "%08llx:", (unsigned long long)r->base + off);
		for (i = 0; i < 16 && off + i < r->size; i += 4)
			seq_printf(s, " %08x", rd(base, off + i));
		seq_putc(s, '\n');
	}
	iounmap(base);
}

static int snapshot_show(struct seq_file *s, void *unused)
{
	void __iomem *dispcc, *tcsr, *pin;
	u32 gdsc, ahb, link, link_intf, aux, pix;
	bool powered;
	int i, j;

	dispcc = ioremap(DISPCC_BASE, DISPCC_SIZE);
	tcsr = ioremap(TCSR_BASE, 0x1000);
	if (!dispcc || !tcsr) {
		seq_puts(s, "ioremap failed\n");
		goto out;
	}

	gdsc = rd(dispcc, DISPCC_MDSS_GDSCR);
	ahb = rd(dispcc, DISPCC_MDSS_AHB_CBCR);
	link = rd(dispcc, DISPCC_DPTX3_LINK_CBCR);
	link_intf = rd(dispcc, DISPCC_DPTX3_LINK_INTF_CBCR);
	aux = rd(dispcc, DISPCC_DPTX3_AUX_CBCR);
	pix = rd(dispcc, DISPCC_DPTX3_PIXEL0_CBCR);

	seq_printf(s, "tcsr_edp_clkref_en %08x\n", rd(tcsr, TCSR_EDP_CLKREF));
	seq_printf(s, "dispcc mdss_gdscr %08x mdss_ahb_cbcr %08x\n", gdsc, ahb);
	seq_printf(s, "dispcc dptx3 cbcr link %08x link_intf %08x aux %08x pixel0 %08x\n",
		   link, link_intf, aux, pix);
	for (i = 0; i < 3; i++) {
		static const u32 rcgs[] = { DISPCC_DPTX3_LINK_RCG,
					    DISPCC_DPTX3_PIXEL0_RCG,
					    DISPCC_DPTX3_AUX_RCG };
		static const char * const names[] = { "link", "pixel0", "aux" };

		seq_printf(s, "dispcc dptx3 %s rcg cmd %08x cfg %08x m %08x n %08x d %08x\n",
			   names[i], rd(dispcc, rcgs[i]), rd(dispcc, rcgs[i] + 4),
			   rd(dispcc, rcgs[i] + 8), rd(dispcc, rcgs[i] + 0xc),
			   rd(dispcc, rcgs[i] + 0x10));
	}

	for (j = 0; j < ARRAY_SIZE(edp_pins); j++) {
		pin = ioremap(TLMM_BASE + edp_pins[j] * TLMM_PIN_STRIDE, 0x10);
		if (!pin)
			continue;
		seq_printf(s, "tlmm gpio%u ctl %08x io %08x\n", edp_pins[j],
			   rd(pin, 0), rd(pin, 4));
		iounmap(pin);
	}

	powered = (gdsc & GDSC_PWR_ON) && !(ahb & CBCR_CLK_OFF) &&
		  !(link & CBCR_CLK_OFF) && !(aux & CBCR_CLK_OFF);
	if (!powered) {
		seq_puts(s, "DP3/PHY not read: MDSS GDSC off or a DP3 clock gated\n");
		goto out;
	}
	for (i = 0; i < ARRAY_SIZE(dp3_regions); i++)
		dump_region(s, &dp3_regions[i]);
out:
	if (dispcc)
		iounmap(dispcc);
	if (tcsr)
		iounmap(tcsr);
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(snapshot);

static int overlay_open(struct inode *inode, struct file *file)
{
	struct overlay_buf *b = kzalloc(sizeof(*b), GFP_KERNEL);

	if (!b)
		return -ENOMEM;
	file->private_data = b;
	return 0;
}

static ssize_t overlay_write(struct file *file, const char __user *ubuf,
			     size_t count, loff_t *ppos)
{
	struct overlay_buf *b = file->private_data;

	if (b->len + count > SZ_1M)
		return -EFBIG;
	if (b->len + count > b->cap) {
		size_t cap = max_t(size_t, b->cap * 2, b->len + count);
		char *n = kvmalloc(cap, GFP_KERNEL);

		if (!n)
			return -ENOMEM;
		if (b->data)
			memcpy(n, b->data, b->len);
		kvfree(b->data);
		b->data = n;
		b->cap = cap;
	}
	if (copy_from_user(b->data + b->len, ubuf, count))
		return -EFAULT;
	b->len += count;
	return count;
}

static int overlay_release(struct inode *inode, struct file *file)
{
	struct overlay_buf *b = file->private_data;
	int id = 0, ret = 0;

	if (b->len) {
		mutex_lock(&lab_lock);
		if (ovcs_count >= MAX_OVERLAYS) {
			ret = -ENOSPC;
		} else {
			ret = of_overlay_fdt_apply(b->data, b->len, &id, NULL);
			if (!ret)
				ovcs_ids[ovcs_count++] = id;
		}
		mutex_unlock(&lab_lock);
		pr_info("glymur_lab: overlay (%zu bytes) apply: ret %d id %d\n",
			b->len, ret, id);
	}
	kvfree(b->data);
	kfree(b);
	return 0;
}

static const struct file_operations overlay_fops = {
	.owner = THIS_MODULE,
	.open = overlay_open,
	.write = overlay_write,
	.release = overlay_release,
};

static ssize_t overlay_remove_write(struct file *file, const char __user *ubuf,
				    size_t count, loff_t *ppos)
{
	char buf[16];
	int id, i, ret = -ENOENT;

	if (count >= sizeof(buf))
		return -EINVAL;
	if (copy_from_user(buf, ubuf, count))
		return -EFAULT;
	buf[count] = '\0';
	strim(buf);

	mutex_lock(&lab_lock);
	if (!strcmp(buf, "last")) {
		i = ovcs_count - 1;
	} else {
		if (kstrtoint(buf, 0, &id)) {
			mutex_unlock(&lab_lock);
			return -EINVAL;
		}
		for (i = ovcs_count - 1; i >= 0 && ovcs_ids[i] != id; i--)
			;
	}
	if (i >= 0) {
		id = ovcs_ids[i];
		ret = of_overlay_remove(&id);
		if (!ret) {
			memmove(&ovcs_ids[i], &ovcs_ids[i + 1],
				(ovcs_count - i - 1) * sizeof(int));
			ovcs_count--;
		}
	}
	mutex_unlock(&lab_lock);
	pr_info("glymur_lab: overlay remove '%s': ret %d\n", buf, ret);
	return ret ? ret : count;
}

static const struct file_operations overlay_remove_fops = {
	.owner = THIS_MODULE,
	.write = overlay_remove_write,
};

static int overlays_show(struct seq_file *s, void *unused)
{
	int i;

	mutex_lock(&lab_lock);
	for (i = 0; i < ovcs_count; i++)
		seq_printf(s, "%d\n", ovcs_ids[i]);
	mutex_unlock(&lab_lock);
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(overlays);

static struct device_node *dp_out_node(void)
{
	struct device_node *sym = of_find_node_by_path("/__symbols__");
	struct device_node *np = NULL;
	const char *path;

	if (sym && !of_property_read_string(sym, "mdss_dp3_out", &path))
		np = of_find_node_by_path(path);
	of_node_put(sym);
	return np;
}

/* Build a property from "a,b,c": u32 cells, or u64 when wide. */
static struct property *make_prop(const char *name, char *list, bool wide)
{
	struct property *prop;
	u64 vals[8];
	int n = 0, i;
	char *tok;

	while ((tok = strsep(&list, ",")) && n < ARRAY_SIZE(vals)) {
		if (kstrtou64(tok, 0, &vals[n]))
			return NULL;
		n++;
	}
	if (!n)
		return NULL;

	prop = kzalloc(sizeof(*prop), GFP_KERNEL);
	if (!prop)
		return NULL;
	prop->name = kstrdup(name, GFP_KERNEL);
	prop->length = n * (wide ? 8 : 4);
	prop->value = kzalloc(prop->length, GFP_KERNEL);
	if (!prop->name || !prop->value)
		return NULL;	/* leaked on purpose: lab module, tiny */
	for (i = 0; i < n; i++) {
		if (wide)
			((__be64 *)prop->value)[i] = cpu_to_be64(vals[i]);
		else
			((__be32 *)prop->value)[i] = cpu_to_be32((u32)vals[i]);
	}
	return prop;
}

static ssize_t dp_out_write(struct file *file, const char __user *ubuf,
			    size_t count, loff_t *ppos)
{
	struct device_node *np;
	struct of_changeset *cs;
	char *buf, *cur, *item;
	int ret = 0;

	if (count > 256)
		return -EINVAL;
	buf = memdup_user_nul(ubuf, count);
	if (IS_ERR(buf))
		return PTR_ERR(buf);

	np = dp_out_node();
	if (!np) {
		kfree(buf);
		return -ENODEV;
	}
	cs = kzalloc(sizeof(*cs), GFP_KERNEL);
	if (!cs) {
		ret = -ENOMEM;
		goto out;
	}
	of_changeset_init(cs);

	cur = strim(buf);
	while ((item = strsep(&cur, " \n")) && !ret) {
		struct property *prop = NULL;
		char *val = strchr(item, '=');

		if (!*item)
			continue;
		if (!val) {
			ret = -EINVAL;
			break;
		}
		*val++ = '\0';
		if (!strcmp(item, "data-lanes"))
			prop = make_prop("data-lanes", val, false);
		else if (!strcmp(item, "link-frequencies"))
			prop = make_prop("link-frequencies", val, true);
		if (!prop)
			ret = -EINVAL;
		else
			ret = of_changeset_update_property(cs, np, prop);
	}

	mutex_lock(&lab_lock);
	if (!ret && dp_change_count >= MAX_DP_CHANGES)
		ret = -ENOSPC;
	if (!ret)
		ret = of_changeset_apply(cs);
	if (!ret)
		dp_changes[dp_change_count++] = cs;
	mutex_unlock(&lab_lock);
	if (ret) {
		of_changeset_destroy(cs);
		kfree(cs);
	}
	pr_info("glymur_lab: dp_out update: ret %d\n", ret);
out:
	of_node_put(np);
	kfree(buf);
	return ret ? ret : count;
}

static int dp_out_show(struct seq_file *s, void *unused)
{
	struct device_node *np = dp_out_node();
	u32 lanes[4];
	u64 freqs[8];
	int n, i;

	if (!np) {
		seq_puts(s, "no mdss_dp3_out symbol\n");
		return 0;
	}
	n = of_property_count_u32_elems(np, "data-lanes");
	if (n > 0 && n <= 4 && !of_property_read_u32_array(np, "data-lanes", lanes, n)) {
		seq_puts(s, "data-lanes");
		for (i = 0; i < n; i++)
			seq_printf(s, " %u", lanes[i]);
		seq_putc(s, '\n');
	}
	n = of_property_count_u64_elems(np, "link-frequencies");
	if (n > 0 && n <= 8 && !of_property_read_u64_array(np, "link-frequencies", freqs, n)) {
		seq_puts(s, "link-frequencies");
		for (i = 0; i < n; i++)
			seq_printf(s, " %llu", freqs[i]);
		seq_putc(s, '\n');
	}
	of_node_put(np);
	return 0;
}

static int dp_out_open(struct inode *inode, struct file *file)
{
	return single_open(file, dp_out_show, NULL);
}

static const struct file_operations dp_out_fops = {
	.owner = THIS_MODULE,
	.open = dp_out_open,
	.read = seq_read,
	.llseek = seq_lseek,
	.release = single_release,
	.write = dp_out_write,
};

static ssize_t dp_out_reset_write(struct file *file, const char __user *ubuf,
				  size_t count, loff_t *ppos)
{
	int ret = 0;

	mutex_lock(&lab_lock);
	while (dp_change_count && !ret) {
		struct of_changeset *cs = dp_changes[dp_change_count - 1];

		ret = of_changeset_revert(cs);
		if (!ret) {
			of_changeset_destroy(cs);
			kfree(cs);
			dp_change_count--;
		}
	}
	mutex_unlock(&lab_lock);
	pr_info("glymur_lab: dp_out reset: ret %d\n", ret);
	return ret ? ret : count;
}

static const struct file_operations dp_out_reset_fops = {
	.owner = THIS_MODULE,
	.write = dp_out_reset_write,
};

static int __init glymur_lab_init(void)
{
	if (!of_machine_is_compatible("hp,omnibook-5-16-bf1xxx")) {
		pr_err("glymur_lab: not the HP OmniBook 5 16-bf1xxx device tree; refusing\n");
		return -ENODEV;
	}
	lab_dir = debugfs_create_dir("glymur-lab", NULL);
	debugfs_create_file("snapshot", 0400, lab_dir, NULL, &snapshot_fops);
	debugfs_create_file("overlay", 0200, lab_dir, NULL, &overlay_fops);
	debugfs_create_file("overlay_remove", 0200, lab_dir, NULL, &overlay_remove_fops);
	debugfs_create_file("overlays", 0400, lab_dir, NULL, &overlays_fops);
	debugfs_create_file("dp_out", 0600, lab_dir, NULL, &dp_out_fops);
	debugfs_create_file("dp_out_reset", 0200, lab_dir, NULL, &dp_out_reset_fops);
	pr_info("glymur_lab: ready\n");
	return 0;
}

static void __exit glymur_lab_exit(void)
{
	/* Overlays and dp_out changes stay applied; the lab reboots after. */
	debugfs_remove_recursive(lab_dir);
}

module_init(glymur_lab_init);
module_exit(glymur_lab_exit);

MODULE_DESCRIPTION("HP OmniBook 5 16-bf1xxx display-lab helper (debugfs)");
MODULE_LICENSE("GPL");
