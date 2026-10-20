#!/usr/bin/env bash
set -u

# External display over USB-C (DP alt mode), test device tree (kernel -15
# on). Run once with nothing in the USB-C ports, then with a monitor or a
# USB-C to DisplayPort/HDMI adapter in one port, then in the other.
# See README.md.
#   sudo bash check-display.sh

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
OUT="/var/log/glymur/display-test-$(date +%Y%m%dT%H%M%S).txt"
mkdir -p /var/log/glymur
exec > >(tee "$OUT") 2>&1
sect() { printf '\n==== %s\n' "$*"; }

sect system
uname -r
tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null; echo

sect "DRM connectors"
for c in /sys/class/drm/card*-*; do
    [ -e "$c/status" ] || continue
    printf '%-28s %-13s enabled=%s modes=%s\n' "$(basename "$c")" "$(cat "$c/status")" \
        "$(cat "$c/enabled" 2>/dev/null)" "$(head -3 "$c/modes" 2>/dev/null | tr '\n' ' ')"
done

sect "USB-C ports: partner and alternate modes"
for p in /sys/class/typec/port?; do
    printf '%s: data_role=%s power_role=%s orientation=%s\n' "$(basename "$p")" \
        "$(cat "$p/data_role" 2>/dev/null)" "$(cat "$p/power_role" 2>/dev/null)" \
        "$(cat "$p/orientation" 2>/dev/null)"
    for a in "$p"/port?.? "$p"-partner/port?-partner.?; do
        [ -e "$a/svid" ] || continue
        printf '  %s svid=%s mode=%s active=%s\n' "$(basename "$a")" "$(cat "$a/svid")" \
            "$(cat "$a/mode" 2>/dev/null)" "$(cat "$a/active" 2>/dev/null)"
    done
done

sect "kernel log: DisplayPort, altmode, display"
journalctl -k -b --no-pager |
    grep -iE 'displayport|af54000|af5c000|msm_dp|dp_|altmode|hpd|aux|link train|qmp.*dp|drm|dpu' |
    tail -80

sect "monitors as GNOME sees them"
if [ -n "${SUDO_USER:-}" ]; then
    sudo -u "$SUDO_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$SUDO_USER")" \
        gdbus call --session --dest org.gnome.Mutter.DisplayConfig \
        --object-path /org/gnome/Mutter/DisplayConfig \
        --method org.gnome.Mutter.DisplayConfig.GetCurrentState 2>&1 |
        grep -oE "'(eDP|DP|HDMI)-[0-9]+'|'[A-Za-z0-9 -]+'\)" | head -10
fi
echo "Saved to $OUT"
