#!/usr/bin/env bash
set -euo pipefail

# Start the display-lab session. See README.md.
#   sudo bash ~/glymur-lab-kit/start-lab.sh

KIT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KREL=7.3.0-rc2-glymur-3

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
[ "$(uname -r)" = "$KREL" ] || { echo "running $(uname -r), the lab kit is built for $KREL" >&2; exit 1; }
[ "$(findmnt -n -o LABEL /)" = glymur-root ] || { echo '/ is not glymur-root; refusing' >&2; exit 1; }
tr -d '\0' </proc/device-tree/model | grep -q '(display lab)' ||
    { echo 'not booted with the display-lab device tree; use the "display lab" USB entry' >&2; exit 1; }
(cd "$KIT_SRC" && sha256sum --quiet -c SHA256SUMS) || { echo 'kit checksum mismatch; refusing' >&2; exit 1; }
for ko in glymur_lab.ko phy-qcom-edp-lab.ko; do
    vm="$(modinfo -F vermagic "$KIT_SRC/$ko" | cut -d' ' -f1)"
    [ "$vm" = "$KREL" ] || { echo "$ko is built for $vm, not $KREL" >&2; exit 1; }
done
if systemctl is-active --quiet glymur-lab; then
    echo 'a lab session is already running: journalctl -fu glymur-lab' >&2
    exit 1
fi

rm -rf /run/glymur-lab
cp -a "$KIT_SRC" /run/glymur-lab
OUT="/var/log/glymur/lab-$(date +%Y%m%dT%H%M%S)"
systemd-run --unit=glymur-lab --collect -p IgnoreOnIsolate=yes \
    /bin/bash /run/glymur-lab/glymur-lab-run.sh /run/glymur-lab "$OUT"
echo "Lab started; results in $OUT. Following its log (Ctrl+C only stops following)."
echo 'The desktop will stop for the display phase; then watch the screen.'
exec journalctl -fu glymur-lab -o cat
