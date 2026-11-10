#!/usr/bin/env bash
set -u

# Hardware IDs (CHIDs) distributions use to pick this laptop's device tree
# (systemd-stub, Ubuntu's stubble, Omarchy), from kernel -20 on. Read-only:
# the SMBIOS strings and the panel's EDID; no serial numbers. Three tools for
# the same IDs: systemd-analyze, stubble's hwids.py, fwupdtool. See README.md.
#   sudo bash check-chid.sh
# Run with no external monitor plugged in: the EDID CHIDs need exactly one.

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
D=/var/log/glymur
STAMP=$(date +%Y%m%dT%H%M%S)
OUT=$D/chid-$STAMP.txt
mkdir -p "$D"
exec > >(tee "$OUT") 2>&1
sect() { printf '\n==== %s\n' "$*"; }
HOME_DIR=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)

sect system
uname -r
tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null; echo
echo "compatible: $(tr '\0' ' ' < /sys/firmware/devicetree/base/compatible 2>/dev/null)"
systemctl --version | head -1

sect "SMBIOS strings (serials and UUID left out)"
for n in sys_vendor product_family product_name product_sku product_version \
         board_vendor board_name board_version chassis_vendor chassis_type \
         bios_vendor bios_version bios_date bios_release ec_firmware_release; do
    printf '%-20s %s\n' "$n" "$(cat /sys/class/dmi/id/$n 2>/dev/null || echo '(none)')"
done

sect "panels with an EDID"
# sysfs reports size 0 for edid, so count the bytes.
for e in /sys/class/drm/*/edid; do
    [ -e "$e" ] || continue
    n=$(wc -c < "$e" 2>/dev/null || echo 0)
    [ "$n" -gt 0 ] || continue
    c=${e%/edid}
    printf '%s: %s, %s bytes\n' "${c##*/}" "$(cat "$c/status" 2>/dev/null)" "$n"
done

sect "systemd-analyze chid"
systemd-analyze chid 2>&1 | tee "$D/chid.txt"

sect "stubble hwids.py (ubuntu/stubble 14963a6, the format of its hwids/txt)"
P=$HOME_DIR/stubble-hwids.py
if [ -f "$P" ]; then
    echo "sha256 $(sha256sum "$P" | cut -c1-64)"
    python3 "$P" 2>&1 | tee "$D/stubble-hwids-$STAMP.txt"
else
    echo "no $P"
fi

# Read-only SMBIOS query, as stubble's README asks. The fwupd service stays
# masked; never run any other fwupdtool or fwupdmgr command here.
sect "fwupdtool hwids"
if command -v fwupdtool >/dev/null; then
    fwupdtool --version 2>&1 | grep -iE 'fwupd|runtime' | head -2
    fwupdtool hwids 2>&1 | tee "$D/fwupd-hwids-$STAMP.txt"
else
    echo "fwupdtool not installed"
fi
echo "fwupd.service: $(systemctl is-enabled fwupd.service 2>&1)"

echo
echo "saved to $OUT, $D/chid.txt, $D/stubble-hwids-$STAMP.txt and $D/fwupd-hwids-$STAMP.txt"
