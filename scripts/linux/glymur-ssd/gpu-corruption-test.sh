#!/usr/bin/env bash
set -u

# kmscube cases for the GMEM corruption test. See README.md.
#   bash gpu-corruption-test.sh   (on a text console, as yourself)

[ "$(id -u)" -ne 0 ] || { echo 'run as your normal user, not with sudo' >&2; exit 1; }
command -v kmscube >/dev/null || { echo 'kmscube is missing: sudo apt install kmscube' >&2; exit 1; }
command -v mesa-glymur-run >/dev/null || { echo 'mesa-glymur-run is missing: run install-from-usb.sh first' >&2; exit 1; }
case "$(tty)" in /dev/tty[0-9]*) ;; *) echo 'run this on a text console (Ctrl+Alt+F3), not in a desktop terminal' >&2; exit 1 ;; esac

CARD=
for c in /sys/class/drm/card[0-9]; do
    if [ "$(basename "$(readlink -f "$c/device/driver" 2>/dev/null)")" = msm_dpu ]; then
        CARD="/dev/dri/${c##*/}"
    fi
done
[ -n "$CARD" ] || { echo 'no msm display card found' >&2; exit 1; }

mkdir -p "$HOME/glymur-logs"
OUT="$HOME/glymur-logs/gpu-corruption-$(date +%Y%m%dT%H%M%S).txt"
log() { printf '%s\n' "$*" | tee -a "$OUT"; }
log "gpu-corruption-test (GMEM size) on $(uname -r), $(tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null), card $CARD"
log "$(mesa-glymur-run --system status 2>&1 | tr '\n' ';')"
log "kmscube: $(dpkg-query -W -f='${Version}' kmscube 2>/dev/null)"
START="$(date '+%Y-%m-%d %H:%M:%S')"

GMEM3=$(( 21 * 1024 * 1024 / 4 * 3 ))
N=4
run_case() {
    local n="$1" label="$2"; shift 2
    printf '\n[%s/%s] %s\nPress Enter to start (the cube shows for about 8 seconds)... ' "$n" "$N" "$label"
    read -r _
    timeout 8 "$@" -D "$CARD" > "$HOME/glymur-logs/.kmscube.$$" 2>&1
    local rc=$?
    printf '\n'
    read -r -p "Case $n ($label): was the screen clean? [y = clean, n = corrupted, b = blank/no cube] " ans
    log "case $n | $label | exit $rc | answer: ${ans:-none}"
    grep -iE 'error|fail|modifier|renderer' "$HOME/glymur-logs/.kmscube.$$" | head -5 | sed 's/^/    /' | tee -a "$OUT"
}

run_case 1 'GPU, sysmem (reference)'        env FD_MESA_DEBUG=sysmem mesa-glymur-run kmscube
run_case 2 'GPU, default'                   mesa-glymur-run kmscube
run_case 3 "GPU, GMEM $GMEM3 (3 slices)"     env FD_MESA_GMEM=$GMEM3 mesa-glymur-run kmscube
run_case 4 "GPU, GMEM $(( GMEM3 / 2 )) (half)" env FD_MESA_GMEM=$(( GMEM3 / 2 )) mesa-glymur-run kmscube
rm -f "$HOME/glymur-logs/.kmscube.$$"

log ''
log '== kernel GPU/display messages during the test'
journalctl -k --no-pager --since "$START" 2>&1 | grep -iE 'msm|adreno|a8xx|a6xx|gmu|dpu|fault|hang|recover|iommu|smmu' | tail -60 | tee -a "$OUT"
sync
echo; echo "Saved to $OUT. Ctrl+Alt+F2 (or F1) returns to the desktop."
