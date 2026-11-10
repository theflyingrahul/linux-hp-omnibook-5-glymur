#!/usr/bin/env bash
set -u

# Iris video decoder/encoder report, test device tree (kernel -15 on).
# Decodes a generated H.264 clip with the hardware decoder through
# ffmpeg's V4L2 stateful decoder, and the same clip in software for
# comparison. See README.md.
# --diag (kernel -17, glymur-bringup/0003): reloads qcom_iris with one video
# core powered for each trial and decodes a short clip with each pipe and
# core ID setting, logging what the firmware answers
# (docs/video-iris-fuse-2026-10-23.md).
# --mahua (kernel -19, glymur-bringup/0004): the same with what Windows does
# on Mahua (docs/video-iris-windows-2026-11-06.md): one core on vcodec 0's
# power domain, HFI core ID 2, hardware core 1's register bits, and the
# wrapper power control released; each trial leaves one of these out.
#   sudo bash check-video.sh [--diag | --mahua]

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

if [ "${1:-}" = --diag ]; then
    sect "diagnostics: one core, pipe and core ID trials"
    command -v ffmpeg >/dev/null || { echo 'ffmpeg missing: sudo apt install ffmpeg'; exit 1; }
    modinfo -p qcom_iris 2>/dev/null | grep -q diag_cores || { echo 'qcom_iris has no diag parameters (needs kernel -17)'; exit 1; }
    ffmpeg -nostdin -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=1920x1080:rate=30 \
        -t 2 -c:v libx264 -pix_fmt yuv420p "$TMP/short.mp4"
    # pipes core_id: 0 = platform value / driver choice for pipes, -1 = driver choice, 0 = not sent for the core
    for t in "0 -1" "2 -1" "1 -1" "0 2" "2 2" "0 0" "2 0"; do
        set -- $t
        echo; echo "-- trial: diag_pipes=$1 diag_core_id=$2"
        modprobe -r qcom_iris 2>&1
        sleep 1
        modprobe qcom_iris diag_cores=1 diag_pipes="$1" diag_core_id="$2" 2>&1
        sleep 2
        # a module still in use (a video app open) keeps the old settings
        echo "loaded with: $(grep -H . /sys/module/qcom_iris/parameters/diag_* 2>/dev/null | sed 's#.*/##' | tr '\n' ' ')"
        since=$(date '+%Y-%m-%d %H:%M:%S')
        timeout 30 ffmpeg -nostdin -hide_banner -loglevel warning -c:v h264_v4l2m2m \
            -i "$TMP/short.mp4" -f null - 2>&1 | tail -4
        echo "ffmpeg exit: ${PIPESTATUS[0]}"
        journalctl -k --no-pager --since "$since" | grep -E 'diag:|not supported|fatal|power on failed|Oops' | sed 's/^.*qcom-iris [^ ]* //' | sort | uniq -c | head -12
    done
    modprobe -r qcom_iris 2>&1
    modprobe qcom_iris 2>&1
    echo "Saved to $OUT"
    exit 0
fi

if [ "${1:-}" = --mahua ]; then
    sect "Mahua trials: one core, core ID 2, hardware core and power release"
    command -v ffmpeg >/dev/null || { echo 'ffmpeg missing: sudo apt install ffmpeg'; exit 1; }
    modinfo -p qcom_iris 2>/dev/null | grep -q diag_pwr_ctl || { echo 'qcom_iris has no diag_pwr_ctl (needs kernel -19)'; exit 1; }
    ffmpeg -nostdin -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=1920x1080:rate=30 \
        -t 2 -c:v libx264 -pix_fmt yuv420p "$TMP/short.mp4"
    # hw_core pwr_ctl pipes partial_av1_only: the Windows-like set with the
    # partial-data buffer kept to AV1 (glymur-bringup/0005, from -21) first,
    # since -20's firmware rejected it on H.264; then one change each.
    for t in "1 1 0 1" "1 1 0 0" "1 1 2 0" "-1 1 0 0" "1 0 0 0"; do
        set -- $t
        echo; echo "-- trial: diag_hw_core=$1 diag_pwr_ctl=$2 diag_pipes=$3 diag_partial_av1_only=$4 (diag_cores=1 diag_core_id=2)"
        if ! modprobe -r qcom_iris 2>&1; then
            echo 'qcom_iris is still in use (a stuck decoder?); stopping the trials'
            break
        fi
        sleep 1
        modprobe qcom_iris diag_cores=1 diag_core_id=2 diag_hw_core="$1" diag_pwr_ctl="$2" diag_pipes="$3" \
            diag_partial_av1_only="$4" 2>&1
        sleep 2
        echo "loaded with: $(grep -H . /sys/module/qcom_iris/parameters/diag_* 2>/dev/null | sed 's#.*/##' | tr '\n' ' ')"
        since=$(date '+%Y-%m-%d %H:%M:%S')
        timeout -k 5 30 ffmpeg -nostdin -hide_banner -loglevel warning -c:v h264_v4l2m2m \
            -i "$TMP/short.mp4" -f null - 2>&1 | tail -4
        echo "ffmpeg exit: ${PIPESTATUS[0]} (124: timed out, 137: killed)"
        journalctl -k --no-pager --since "$since" |
            grep -E 'diag:|not supported|fatal|power on failed|stuck|failed to suspend|Oops|timeout|Buffer type' |
            sed 's/^.*qcom-iris [^ ]* //' | sort | uniq -c | head -16
    done
    modprobe -r qcom_iris 2>&1
    modprobe qcom_iris 2>&1
    echo "Saved to $OUT"
    exit 0
fi

sect "decode test (H.264, 1080p, 10 s)"
if ! command -v ffmpeg >/dev/null; then
    echo 'ffmpeg missing: sudo apt install ffmpeg'
else
    ffmpeg -nostdin -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=1920x1080:rate=30 \
        -t 10 -c:v libx264 -pix_fmt yuv420p "$TMP/test.mp4"
    TIMEFORMAT='  %R s elapsed, %U s user CPU'
    echo "software:"
    time ffmpeg -nostdin -hide_banner -loglevel error -i "$TMP/test.mp4" -f null - 2>&1
    echo "hardware (h264_v4l2m2m):"
    time ffmpeg -nostdin -hide_banner -loglevel warning -c:v h264_v4l2m2m \
        -i "$TMP/test.mp4" -f null - 2>&1 | tail -15
fi

sect "kernel log after the test"
journalctl -k -b --no-pager --since '-5 min' | grep -iE 'iris|video|smmu|Oops|error' | tail -40
echo "Saved to $OUT"
