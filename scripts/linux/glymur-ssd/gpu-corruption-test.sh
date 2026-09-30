#!/usr/bin/env bash
set -u

# Test the cause of the GPU-rendered screen corruption on the Adreno X2-85
# (docs/gpu-corruption-2026-09-30.md). Run from a text console, not from the
# desktop: press Ctrl+Alt+F3, log in as yourself, then
#
#   bash gpu-corruption-test.sh
#
# (it can run straight from the USB stick). It needs kmscube:
#   sudo apt install kmscube
#
# kmscube renders a spinning cube with the GPU and shows it through KMS, the
# same path GNOME's compositor uses. Each case runs for about 8 seconds;
# afterwards, answer whether the cube and background looked clean.
#
# The first run (2026-09-30, kernel -6) was clean only with
# FD_MESA_DEBUG=sysmem, which turns off GMEM (on-chip tile memory)
# rendering. The suspected cause: msm tells Mesa the GPU has 21 MB of GMEM,
# the size for all 4 slices, but this GPU runs 3, and Qualcomm's own driver
# (KGSL) reports 21 MB / 4 x 3 = 15.75 MB. Mesa then places tiles and its
# caches past the end of the real GMEM. FD_MESA_GMEM overrides the size
# Mesa uses. Cases:
#   1. GPU, sysmem: no GMEM at all (clean last time: the reference)
#   2. GPU, default: GMEM size from the kernel
#   3. GPU, FD_MESA_GMEM = 15.75 MB: the size for 3 slices
#   4. GPU, FD_MESA_GMEM = 7.875 MB: half of that
# If the explanation is right, 1, 3 and 4 are clean. On a kernel with the
# fix (-7 on), case 2 is clean too.
# The answers and the kernel's GPU messages go to
# ~/glymur-logs/gpu-corruption-<time>.txt. Press Ctrl+Alt+F2 (or F1) to go
# back to the desktop afterwards.

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
