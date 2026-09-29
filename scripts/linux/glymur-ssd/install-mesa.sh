#!/usr/bin/env bash
set -euo pipefail

# Install the Mesa build from build-mesa-glymur.sh under /opt/mesa-glymur,
# next to (not over) Ubuntu's Mesa, and add /usr/local/bin/mesa-glymur-run,
# which runs one program with it:
#
#   sudo bash install-mesa.sh mesa-glymur-<version>.tar.gz
#   mesa-glymur-run eglinfo -B
#
# Nothing else changes: the desktop keeps Ubuntu's Mesa until you opt in
# with `mesa-glymur-run --desktop on` (undo: `--desktop off`).

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

cat > /usr/local/bin/mesa-glymur-run <<'EOF'
#!/usr/bin/env bash
# Run a program with the Mesa in /opt/mesa-glymur (see install-mesa.sh).
#   mesa-glymur-run <program> [args]
#   mesa-glymur-run --desktop on|off   whole GNOME session, from next login
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
case "${1:-}" in
    --desktop)
        case "${2:-}" in
            on) mkdir -p "${ENVF%/*}"; printf '%s\n' "${VARS[@]}" > "$ENVF"
                echo "wrote $ENVF; log out and back in (undo: mesa-glymur-run --desktop off)" ;;
            off) rm -f "$ENVF"; echo "removed $ENVF; log out and back in" ;;
            *) echo 'usage: mesa-glymur-run --desktop on|off' >&2; exit 2 ;;
        esac ;;
    '') echo 'usage: mesa-glymur-run <program> [args] | --desktop on|off' >&2; exit 2 ;;
    *) exec env "${VARS[@]}" "$@" ;;
esac
EOF
chmod 755 /usr/local/bin/mesa-glymur-run
echo "installed $(ls -d /opt/mesa-glymur/lib/aarch64-linux-gnu/libgallium-*.so) and /usr/local/bin/mesa-glymur-run"
