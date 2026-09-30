#!/usr/bin/env bash
set -euo pipefail

# Install a Mesa build under /opt/mesa-glymur. See README.md.
#   sudo bash install-mesa.sh mesa-glymur-<version>.tar.gz

TARBALL="${1:?usage: install-mesa.sh mesa-glymur-<version>.tar.gz}"
[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
[ "$(findmnt -n -o LABEL /)" = glymur-root ] || { echo '/ is not glymur-root; refusing' >&2; exit 1; }
tar -tzf "$TARBALL" | grep -qv '^mesa-glymur/' && { echo 'unexpected paths in the tarball' >&2; exit 1; }

rm -rf /opt/mesa-glymur.new
mkdir /opt/mesa-glymur.new
tar -C /opt/mesa-glymur.new -xzf "$TARBALL" --strip-components=1 --no-same-owner
rm -rf /opt/mesa-glymur.old
[ -d /opt/mesa-glymur ] && mv /opt/mesa-glymur /opt/mesa-glymur.old
mv /opt/mesa-glymur.new /opt/mesa-glymur
rm -rf /opt/mesa-glymur.old
if [ -f /etc/ld.so.conf.d/00-mesa-glymur.conf ]; then ldconfig; fi

cat > /usr/local/bin/mesa-glymur-run <<'EOF'
#!/usr/bin/env bash
# Run a program with the Mesa in /opt/mesa-glymur (see install-mesa.sh).
#   mesa-glymur-run <program> [args]
#   sudo mesa-glymur-run --system on|off|status   the whole system (reboot after)
#   mesa-glymur-run --desktop on|off   older per-user switch (environment.d)
P=/opt/mesa-glymur
L="$P/lib/aarch64-linux-gnu"
ENVF="$HOME/.config/environment.d/90-mesa-glymur.conf"
VARS=(
    "LD_LIBRARY_PATH=$L"
    "__EGL_VENDOR_LIBRARY_FILENAMES=$P/share/glvnd/egl_vendor.d/50_mesa.json"
    "LIBGL_DRIVERS_PATH=$L/dri"
    "GBM_BACKENDS_PATH=$L/gbm"
    "VK_DRIVER_FILES=$(ls "$P"/share/vulkan/icd.d/freedreno_icd.*.json 2>/dev/null | head -1)"
)
LDCONF=/etc/ld.so.conf.d/00-mesa-glymur.conf
VKICD=/etc/vulkan/icd.d/freedreno_glymur_icd.aarch64.json
status() {
    echo "ld.so.conf entry: $([ -f "$LDCONF" ] && echo present || echo absent)"
    for l in libgbm.so.1 libEGL_mesa.so.0 libGLX_mesa.so.0; do
        printf '%-18s -> %s\n' "$l" "$(ldconfig -p | awk -v l="$l" '$1 == l {print $NF; exit}')"
    done
    echo "Vulkan ICD: $([ -f "$VKICD" ] && echo "$VKICD" || echo 'not installed')"
}
case "${1:-}" in
    --system)
        case "${2:-}" in
            on|off) [ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; } ;;
        esac
        case "${2:-}" in
            on) [ -d "$L" ] || { echo "no $L" >&2; exit 1; }
                echo "$L" > "$LDCONF"
                mkdir -p "${VKICD%/*}"
                cp "$(ls "$P"/share/vulkan/icd.d/freedreno_icd.*.json | head -1)" "$VKICD"
                ldconfig; status
                echo 'reboot to use it everywhere (undo: sudo mesa-glymur-run --system off)' ;;
            off) rm -f "$LDCONF" "$VKICD"; ldconfig; status
                echo 'reboot to return to Ubuntu'"'"'s Mesa everywhere' ;;
            status) status ;;
            *) echo 'usage: mesa-glymur-run --system on|off|status' >&2; exit 2 ;;
        esac ;;
    --desktop)
        case "${2:-}" in
            on) mkdir -p "${ENVF%/*}"; printf '%s\n' "${VARS[@]}" > "$ENVF"
                echo "wrote $ENVF; log out and back in (undo: mesa-glymur-run --desktop off)" ;;
            off) rm -f "$ENVF"; echo "removed $ENVF; log out and back in" ;;
            *) echo 'usage: mesa-glymur-run --desktop on|off' >&2; exit 2 ;;
        esac ;;
    '') echo 'usage: mesa-glymur-run <program> [args] | --system on|off|status | --desktop on|off' >&2; exit 2 ;;
    *) exec env "${VARS[@]}" "$@" ;;
esac
EOF
chmod 755 /usr/local/bin/mesa-glymur-run
echo "installed $(ls -d /opt/mesa-glymur/lib/aarch64-linux-gnu/libgallium-*.so) and /usr/local/bin/mesa-glymur-run"
