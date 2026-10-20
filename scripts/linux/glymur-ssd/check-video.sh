#!/usr/bin/env bash
set -u

# Iris video decoder/encoder report, test device tree (kernel -15 on).
# Decodes a generated H.264 clip with the hardware decoder through
# ffmpeg's V4L2 stateful decoder, and the same clip in software for
# comparison. See README.md.
#   sudo bash check-video.sh

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
OUT="/var/log/glymur/video-test-$(date +%Y%m%dT%H%M%S).txt"
TMP=/tmp/glymur-video
mkdir -p /var/log/glymur "$TMP"
exec > >(tee "$OUT") 2>&1
sect() { printf '\n==== %s\n' "$*"; }

sect system
uname -r
tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null; echo
FW=/usr/lib/firmware/updates/qcom/glymur/HP/omnibook-5-16-bf1xxx/qcvss8480.mbn
ls -l "$FW" 2>&1 && sha256sum "$FW"

sect "kernel log: iris, videocc"
journalctl -k -b --no-pager | grep -iE 'iris|videocc|video-codec|aa00000|venus|vpu' | tail -60
lsmod | grep -E 'iris|videocc' || true

sect "V4L2 devices"
command -v v4l2-ctl >/dev/null || { echo 'v4l2-ctl missing: sudo apt install v4l-utils'; }
v4l2-ctl --list-devices 2>&1
for d in /dev/video*; do
    drv=$(v4l2-ctl -d "$d" --info 2>/dev/null | awk -F': ' '/Driver name/ {print $2}')
    [ "$drv" = iris_driver ] || [ "$drv" = iris ] || continue
    echo "-- $d ($drv)"
    v4l2-ctl -d "$d" --info --list-formats --list-formats-out 2>&1 | head -40
done

sect "decode test (H.264, 1080p, 10 s)"
if ! command -v ffmpeg >/dev/null; then
    echo 'ffmpeg missing: sudo apt install ffmpeg'
else
    ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=1920x1080:rate=30 \
        -t 10 -c:v libx264 -pix_fmt yuv420p "$TMP/test.mp4"
    TIMEFORMAT='  %R s elapsed, %U s user CPU'
    echo "software:"
    time ffmpeg -hide_banner -loglevel error -i "$TMP/test.mp4" -f null - 2>&1
    echo "hardware (h264_v4l2m2m):"
    time ffmpeg -hide_banner -loglevel warning -c:v h264_v4l2m2m \
        -i "$TMP/test.mp4" -f null - 2>&1 | tail -15
fi

sect "kernel log after the test"
journalctl -k -b --no-pager --since '-5 min' | grep -iE 'iris|video|smmu|Oops|error' | tail -40
echo "Saved to $OUT"
