#!/usr/bin/env bash
set -euo pipefail

# Build upstream Mesa with the freedreno OpenGL (gallium) and turnip Vulkan
# drivers for the Adreno X2-85, for Ubuntu 26.04 arm64. Ubuntu 26.04 ships
# Mesa 26.0.8, whose freedreno device table has no entry for this GPU
# (chip 0x44070031); Mesa 26.2 adds "Adreno (TM) X2-85".
#
# Runs as a normal user on an Ubuntu 26.04 aarch64 host (the WSL build host
# or the laptop itself): no root, no apt install. Build dependencies are
# fetched with `apt-get download` and unpacked into a private sysroot.
# Output: <out>/mesa-glymur-<version>.tar.gz, which installs under
# /opt/mesa-glymur (see glymur-ssd/install-mesa.sh).
#
#   scripts/linux/build-mesa-glymur.sh <work dir> [jobs]

VER=26.2.3
# From docs/relnotes/26.2.3.rst.
SHA256=1628058a8d2c0615975de5a15ab7bbb9638c50000b5bed9456ff423ea034a81f
WORK="${1:?usage: build-mesa-glymur.sh <work dir> [jobs]}"
JOBS="${2:-4}"
PREFIX=/opt/mesa-glymur
LIBDIR=lib/aarch64-linux-gnu

[ "$(uname -m)" = aarch64 ] || { echo 'needs an aarch64 host' >&2; exit 1; }
. /etc/os-release
[ "$VERSION_ID" = 26.04 ] || { echo "needs Ubuntu 26.04, not $VERSION_ID" >&2; exit 1; }
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"
SYSROOT="$WORK/sysroot"
DEBS="$WORK/debs"

# Build dependencies, resolved by apt against this host's installed set.
PKGS=(meson python3-mako python3-pycparser glslang-tools libwayland-bin
      libdrm-dev libexpat1-dev libwayland-dev wayland-protocols
      libwayland-egl-backend-dev libdisplay-info-dev
      libx11-dev libxext-dev libxfixes-dev libxcb-glx0-dev libxcb-shm0-dev
      libx11-xcb-dev libxcb-dri3-dev libxcb-present-dev libxshmfence-dev
      libxxf86vm-dev libxrandr-dev libxcb-randr0-dev libxcb-sync-dev
      libxcb-xfixes0-dev libudev-dev libvulkan-dev libglvnd-dev)

echo "== build dependencies into $SYSROOT"
mkdir -p "$DEBS" "$SYSROOT" "$WORK/apt/lists/partial" "$WORK/apt/cache/archives/partial"
# A private, current copy of the package lists (the host's may be stale);
# the host's own apt state is not touched.
APT=(-o Dir::State::Lists="$WORK/apt/lists" -o Dir::Cache="$WORK/apt/cache"
     -o Debug::NoLocking=1 -o APT::Sandbox::User="$(id -un)")
apt-get "${APT[@]}" -qq update
mapfile -t need < <(apt-get "${APT[@]}" -s install --no-install-recommends "${PKGS[@]}" 2>/dev/null | awk '/^Inst /{print $2}')
echo "${#need[@]} packages to unpack"
(cd "$DEBS" && apt-get "${APT[@]}" download "${need[@]}" >/dev/null)
for d in "$DEBS"/*.deb; do dpkg-deb -x "$d" "$SYSROOT"; done

# Absolute symlinks in the unpacked packages point at the host; retarget
# them into the sysroot. Dangling dev symlinks (lib*.so -> lib*.so.N whose
# runtime package is already installed on the host) go to the host copy.
# Static archives go, so a missing shared library fails instead of
# silently linking a static one.
find "$SYSROOT" -type l -lname '/*' | while read -r l; do
    t="$(readlink "$l")"
    if [ -e "$SYSROOT$t" ]; then ln -sfn "$SYSROOT$t" "$l"; fi
done
find "$SYSROOT/usr/lib/aarch64-linux-gnu" -maxdepth 1 -xtype l | while read -r l; do
    t="$(basename "$(readlink "$l")")"
    for d in /usr/lib/aarch64-linux-gnu /lib/aarch64-linux-gnu; do
        if [ -e "$d/$t" ]; then ln -sfn "$d/$t" "$l"; break; fi
    done
done
find "$SYSROOT/usr/lib/aarch64-linux-gnu" -maxdepth 1 -name '*.a' -delete
# Anything still dangling belongs to a driver not built here (libdrm_intel).
find "$SYSROOT/usr/lib/aarch64-linux-gnu" -maxdepth 1 -xtype l -print -delete |
    sed 's/^/dropped dangling link: /'

export PATH="$SYSROOT/usr/bin:$PATH"
export LD_LIBRARY_PATH="$SYSROOT/usr/lib/aarch64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PYTHONPATH="$SYSROOT/usr/lib/python3/dist-packages"
export PKG_CONFIG_PATH="$SYSROOT/usr/lib/aarch64-linux-gnu/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export CFLAGS="-I$SYSROOT/usr/include" CXXFLAGS="-I$SYSROOT/usr/include"
export LDFLAGS="-L$SYSROOT/usr/lib/aarch64-linux-gnu -Wl,-rpath-link,$SYSROOT/usr/lib/aarch64-linux-gnu"

echo "== Mesa $VER source"
TARBALL="$WORK/mesa-$VER.tar.xz"
[ -f "$TARBALL" ] || curl -sfL -o "$TARBALL" "https://archive.mesa3d.org/mesa-$VER.tar.xz"
echo "$SHA256  $TARBALL" | sha256sum -c -
rm -rf "$WORK/mesa-$VER" "$WORK/build" "$WORK/stage"
tar -C "$WORK" -xf "$TARBALL"

echo "== configure"
python3 "$SYSROOT/usr/bin/meson" setup "$WORK/build" "$WORK/mesa-$VER" \
    --prefix="$PREFIX" --libdir="$LIBDIR" --buildtype=release \
    -Dgallium-drivers=freedreno,softpipe -Dvulkan-drivers=freedreno \
    -Dfreedreno-kmds=msm -Dplatforms=x11,wayland \
    -Degl=enabled -Dgbm=enabled -Dglx=dri -Dglvnd=enabled \
    -Dllvm=disabled -Dvalgrind=disabled -Dlibunwind=disabled \
    -Dlmsensors=disabled -Dvideo-codecs= -Dtools= -Dbuild-tests=false

echo "== build"
ninja -C "$WORK/build" -j "$JOBS"
DESTDIR="$WORK/stage" ninja -C "$WORK/build" install >/dev/null

# Keep only the runtime: headers and pkgconfig are not needed, and meson's
# libarchive wrap fallback (used by no driver here) installs bsdtar/bsdcat/
# bsdcpio and libarchive.so.
S="$WORK/stage$PREFIX"
rm -rf "$S/bin" "$S/include" "$S/$LIBDIR/pkgconfig" "$S/$LIBDIR"/libarchive.so*
for f in "$S/$LIBDIR"/*.so* "$S/$LIBDIR"/*/*.so; do
    [ -L "$f" ] && continue
    if readelf -d "$f" | grep -q 'NEEDED.*libarchive'; then echo "$f needs libarchive" >&2; exit 1; fi
done

OUT="$WORK/mesa-glymur-$VER.tar.gz"
tar -C "$WORK/stage${PREFIX%/*}" -czf "$OUT" "${PREFIX##*/}"
echo "== $(sha256sum "$OUT")"
