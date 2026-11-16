# Hardware IDs for stubble

These are the files for this laptop in the layout of
[ubuntu/stubble](https://github.com/ubuntu/stubble)'s `hwids/` directory.
Stubble's boot stub uses them to pick the device tree on an ACPI-only
boot.

- `txt/mahua-hp-omnibook-5-bf1xxx.txt` is `sudo fwupdtool hwids` from the
  `-20` boot on 2026-11-10 (BIOS F.06), without its progress lines. This is
  the format stubble's README asks for. The raw output is
  `../fwupd-hwids-20261110T131253.txt`. `systemd-analyze chid` in
  `../chid-20261110T131253.txt` gives the same 15 IDs, plus three that
  include the panel's EDID (`SDC4214`).
- `json/mahua-hp-omnibook-5-bf1xxx.json` holds CHIDs 3 to 10. Each of them
  includes the product name, the SKU or the baseboard (`8F47`), so each
  names this model only. Left out:
    - CHIDs 0 to 2 change with every BIOS version;
    - CHIDs 11 to 14 are shared with other HP laptops: the 14-he0 and 16-bf0
      have the same Family, `103C_5335KV HP OmniBook 5`;
    - the panel IDs: the Family + EDID one would also match a 16-bf0 with
      the same panel.
- The compatible, `hp,omnibook-5-16-bf1xxx`, is this repository's device
  tree (`dts/qcom/mahua-hp-omnibook-5-bf1xxx.dts`), which is not upstream
  yet.

Stubble's `hwids.py` (`../stubble-hwids-20261110T131253.txt`) gives CHID 12 as
`4c84c882-…`, where fwupd and systemd give `f999e8e2-…`. The script hashes
the enclosure type as decimal (`HP&10`) instead of hex (`HP&a`).
