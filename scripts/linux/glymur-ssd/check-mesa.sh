#!/usr/bin/env bash
set -u

# Hardware rendering check for the device-tree boots with the GPU, with the
# Mesa installed by install-mesa.sh. Run from a terminal on the desktop as
# your normal user (not sudo). Everything goes to
# ~/glymur-logs/mesa-test-<time>.txt.
#
# Needs: sudo apt install mesa-utils mesa-utils-bin vulkan-tools glmark2-es2-wayland

[ "$(id -u)" -ne 0 ] || { echo 'run as your normal user, not with sudo' >&2; exit 1; }
[ -n "${WAYLAND_DISPLAY:-}" ] || { echo 'run this from a terminal on the desktop' >&2; exit 1; }
command -v mesa-glymur-run >/dev/null || { echo 'mesa-glymur-run missing: run install-mesa.sh first' >&2; exit 1; }
mkdir -p "$HOME/glymur-logs"
OUT="$HOME/glymur-logs/mesa-test-$(date +%Y%m%dT%H%M%S).txt"
exec > >(tee "$OUT") 2>&1
START="$(date '+%Y-%m-%d %H:%M:%S')"
DF=/sys/class/devfreq/3d00000.gpu
sect() { printf '\n==== %s (%s)\n' "$*" "$(date +%T)"; }
have() { command -v "$1" >/dev/null || { echo "$1 not installed"; return 1; }; }
m() { printf '$ mesa-glymur-run %s\n' "$*"; mesa-glymur-run "$@" 2>&1; echo "exit=$?"; }
# Sample the GPU clock while a command runs: proof the GPU does the work.
loaded() {
    local f="$HOME/glymur-logs/.devfreq.$$"
    (while :; do cat "$DF/cur_freq" 2>/dev/null; sleep 0.5; done) > "$f" &
    local s=$!
    m "$@"
    kill "$s" 2>/dev/null; wait "$s" 2>/dev/null
    printf 'GPU clock during run (Hz, count): '; sort -n "$f" | uniq -c | tr '\n' ' '; echo
    rm -f "$f"
}

sect system
uname -a
cat /sys/firmware/devicetree/base/model; echo
ls /opt/mesa-glymur/lib/aarch64-linux-gnu/libgallium-*.so
[ -d "$DF" ] && echo "devfreq: $(cat "$DF/governor") cur=$(cat "$DF/cur_freq") max=$(cat "$DF/max_freq")"
ls -l /dev/dri

# What msm reports to Mesa. From kernel -11: chip 0x44060030 (Mahua X2-85)
# with 16515072 bytes (15.75 MB) of GMEM; before, 0x44070031.
sect "what the kernel reports to Mesa (MSM_GET_PARAM)"
python3 - <<'PY'
import fcntl, glob, os, struct
IOCTL = 0xC0186440  # DRM_IOCTL_MSM_GET_PARAM
for node in sorted(glob.glob('/dev/dri/renderD*')):
    try:
        fd = os.open(node, os.O_RDWR)
    except OSError as e:
        print(node, e)
        continue
    for name, param in (('GPU_ID', 1), ('GMEM_SIZE', 2), ('CHIP_ID', 3), ('GMEM_BASE', 6)):
        try:
            buf = fcntl.ioctl(fd, IOCTL, struct.pack('IIQII', 0x10, param, 0, 0, 0))
            print(f'{node} {name} = {struct.unpack("IIQII", buf)[2]:#x}')
        except OSError as e:
            print(f'{node} {name}: {e}')
    os.close(fd)
PY
journalctl -k -b --no-pager | grep -iE 'adreno|a8xx|gmu' | head -12

sect "system-wide mode and the compositor"
mesa-glymur-run --system status
pid="$(pgrep -u "$(id -u)" -x gnome-shell | head -1)"
if [ -n "$pid" ]; then
    echo "gnome-shell ($pid) has loaded:"
    grep -oE '/[^ ]*(libgallium|libgbm|libEGL_mesa|libGLX_mesa)[^ ]*' "/proc/$pid/maps" | sort -u
else
    echo 'no gnome-shell process for this user'
fi

sect "what programs get without the wrapper (Ubuntu's Mesa unless --system on)"
have eglinfo && eglinfo -B -p wayland 2>&1 | head -15

sect "EGL (Wayland, GBM, surfaceless)"
if have eglinfo; then
    for p in wayland gbm surfaceless; do m eglinfo -B -p "$p" | head -25; done
fi

sect "GLX through Xwayland"
have glxinfo && m glxinfo -B | head -30

sect Vulkan
have vulkaninfo && m vulkaninfo --summary | head -60
sync

sect "load: glmark2 (GLES 2, Wayland), about 50 s"
have glmark2-es2-wayland && loaded glmark2-es2-wayland --size 1280x800 \
    -b build:use-vbo=true:duration=10 -b texture:duration=10 \
    -b shading:shading=phong:duration=10 -b refract:duration=10 \
    -b terrain:duration=10
sync

sect "load: vkcube, 1000 frames"
have vkcube && loaded vkcube --wsi wayland --c 1000
sync

sect "kernel log since the start"
journalctl -k --no-pager --since "$START" 2>&1 | grep -iE 'adreno|a6xx|a8xx|gmu|gpu|msm|drm|smmu|iommu|fault|hang|recover|timeout' | tail -80
[ -d "$DF" ] && echo "devfreq after: cur=$(cat "$DF/cur_freq") trans_stat:" && head -20 "$DF/trans_stat" 2>/dev/null
sync
echo; echo "Saved to $OUT"
echo "If everything above rendered, try the whole desktop: mesa-glymur-run --desktop on, then log out and in."
