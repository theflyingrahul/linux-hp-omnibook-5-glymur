#!/usr/bin/env bash
set -euo pipefail

# Build Mesa for the Adreno X2-85 without root. See README.md.
#   scripts/linux/build-mesa-glymur.sh <work dir> [jobs]

# Mesa main, pinned: the first Mesa with Mahua's X2-85 (chip 0x44060030,
# d09fa965). No release has it yet; 26.2.3-2 was the last tarball build.
VER=26.3.0-devel
COMMIT=cec59b299704edc442d930ea9e06ab2edcf5ad7b
PKGREL=1
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

PKGS=(meson python3-mako python3-pycparser python3-yaml python3-packaging
      glslang-tools libwayland-bin
      libdrm-dev libexpat1-dev libwayland-dev wayland-protocols
      libwayland-egl-backend-dev libdisplay-info-dev
      libx11-dev libxext-dev libxfixes-dev libxcb-glx0-dev libxcb-shm0-dev
      libx11-xcb-dev libxcb-dri3-dev libxcb-present-dev libxshmfence-dev
      libxxf86vm-dev libxrandr-dev libxcb-randr0-dev libxcb-sync-dev
      libxcb-xfixes0-dev libudev-dev libvulkan-dev libglvnd-dev
      llvm-21-dev)
LLVM_CONFIG=/usr/lib/llvm-21/bin/llvm-config

echo "== build dependencies into $SYSROOT"
mkdir -p "$DEBS" "$SYSROOT" "$WORK/apt/lists/partial" "$WORK/apt/cache/archives/partial"
# Private package lists; the host's apt state is untouched.
APT=(-o Dir::State::Lists="$WORK/apt/lists" -o Dir::Cache="$WORK/apt/cache"
     -o Debug::NoLocking=1 -o APT::Sandbox::User="$(id -un)")
apt-get "${APT[@]}" -qq update
mapfile -t need < <(apt-get "${APT[@]}" -s install --no-install-recommends "${PKGS[@]}" 2>/dev/null | awk '/^Inst /{print $2}')
echo "${#need[@]} packages to unpack"
(cd "$DEBS" && apt-get "${APT[@]}" download "${need[@]}" >/dev/null)
for d in "$DEBS"/*.deb; do dpkg-deb -x "$d" "$SYSROOT"; done

# Retarget absolute and dangling links; drop static archives.
find "$SYSROOT" -type l -lname '/*' | while read -r l; do
    t="$(readlink "$l")"
    if [ -e "$SYSROOT$t" ]; then ln -sfn "$SYSROOT$t" "$l"; fi
done
find "$SYSROOT" -xtype l | while read -r l; do
    t="$(readlink "$l")"
    rel="${l#"$SYSROOT"}"
    case "$t" in
        /*) host="$t" ;;
        *) host="$(realpath -m "$(dirname "$rel")/$t")" ;;
    esac
    if [ -e "$host" ]; then
        ln -sfn "$host" "$l"
        continue
    fi
    for d in /usr/lib/aarch64-linux-gnu /lib/aarch64-linux-gnu; do
        if [ -e "$d/$(basename "$t")" ]; then ln -sfn "$d/$(basename "$t")" "$l"; break; fi
    done
done
find "$SYSROOT/usr/lib/aarch64-linux-gnu" -maxdepth 1 -name '*.a' -delete
# Anything still dangling belongs to a driver not built here.
find "$SYSROOT/usr/lib/aarch64-linux-gnu" -maxdepth 1 -xtype l -print -delete |
    sed 's/^/dropped dangling link: /'

export PATH="$SYSROOT/usr/bin:$PATH"
export LD_LIBRARY_PATH="$SYSROOT/usr/lib/aarch64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PYTHONPATH="$SYSROOT/usr/lib/python3/dist-packages"
export PKG_CONFIG_PATH="$SYSROOT/usr/lib/aarch64-linux-gnu/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export CFLAGS="-I$SYSROOT/usr/include" CXXFLAGS="-I$SYSROOT/usr/include"
export LDFLAGS="-L$SYSROOT/usr/lib/aarch64-linux-gnu -Wl,-rpath-link,$SYSROOT/usr/lib/aarch64-linux-gnu"

VER="$VER-${COMMIT:0:8}"
SRC="$WORK/mesa-$VER"
echo "== Mesa $VER source"
rm -rf "$WORK/build" "$WORK/stage"
if [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$COMMIT" ]; then
    rm -rf "$SRC"
    git init -q "$SRC"
    git -C "$SRC" fetch -q --depth 1 https://gitlab.freedesktop.org/mesa/mesa.git "$COMMIT"
    git -C "$SRC" checkout -q FETCH_HEAD
fi
[ "$(git -C "$SRC" rev-parse HEAD)" = "$COMMIT" ] || { echo "source is not $COMMIT" >&2; exit 1; }
git -C "$SRC" diff --quiet || { echo "$SRC has local changes" >&2; exit 1; }
grep -q 0xffff44060030 "$SRC/src/freedreno/common/freedreno_devices.py" ||
    { echo "this Mesa does not know the Mahua X2-85" >&2; exit 1; }

echo "== configure"
# Prefer the sysroot's llvm-config; fall back to the host's.
if [ -x "$SYSROOT$LLVM_CONFIG" ]; then LLVM_CONFIG="$SYSROOT$LLVM_CONFIG"; fi
[ "$("$LLVM_CONFIG" --version | cut -d. -f1)" = 21 ] ||
    { echo "need LLVM 21 (Ubuntu's Mesa links libllvm21), got $("$LLVM_CONFIG" --version)" >&2; exit 1; }
"$LLVM_CONFIG" --version --includedir --libdir --shared-mode
printf "[binaries]\nllvm-config = '%s'\n" "$LLVM_CONFIG" > "$WORK/native.ini"
python3 "$SYSROOT/usr/bin/meson" setup "$WORK/build" "$SRC" \
    --native-file "$WORK/native.ini" \
    --prefix="$PREFIX" --libdir="$LIBDIR" --buildtype=release \
    -Dgallium-drivers=freedreno,llvmpipe,softpipe -Dvulkan-drivers=freedreno \
    -Dfreedreno-kmds=msm -Dplatforms=x11,wayland \
    -Degl=enabled -Dgbm=enabled -Dglx=dri -Dglvnd=enabled \
    -Dllvm=enabled -Dshared-llvm=enabled -Dvalgrind=disabled -Dlibunwind=disabled \
    -Dlmsensors=disabled -Dvideo-codecs= -Dtools= -Dbuild-tests=false

echo "== build"
ninja -C "$WORK/build" -j "$JOBS"
DESTDIR="$WORK/stage" ninja -C "$WORK/build" install >/dev/null

# Runtime only.
S="$WORK/stage$PREFIX"
rm -rf "$S/bin" "$S/include" "$S/$LIBDIR/pkgconfig" "$S/$LIBDIR"/libarchive.so*
for f in "$S/$LIBDIR"/*.so* "$S/$LIBDIR"/*/*.so; do
    [ -L "$f" ] && continue
    if readelf -d "$f" | grep -q 'NEEDED.*libarchive'; then echo "$f needs libarchive" >&2; exit 1; fi
done
echo "== LLVM libraries needed: $(for f in "$S/$LIBDIR"/*.so*; do [ -L "$f" ] || readelf -d "$f"; done |
    sed -n 's/.*NEEDED.*\[\(libLLVM[^]]*\)\]/\1/p' | sort -u | tr '\n' ' ')"

OUT="$WORK/mesa-glymur-$VER-$PKGREL.tar.gz"
tar -C "$WORK/stage${PREFIX%/*}" -czf "$OUT" "${PREFIX##*/}"
echo "== $(sha256sum "$OUT")"
