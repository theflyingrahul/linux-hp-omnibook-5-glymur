#!/usr/bin/env bash
set -euo pipefail

# Prepare a native qcom-next build on the SSD install. See README.md.
#   bash scripts/linux/setup-native-kernel-build.sh [src-root]

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="${1:-$HOME/src}"
URL=https://github.com/qualcomm-linux/kernel.git
BASE=6b4daa84523902fe715813633d47f1c568d2bcbc
CLONE="$ROOT/linux-qcom-next"
TREE="$ROOT/linux-qcom-next-glymur"

missing=()
for tool in gcc make bc bison flex perl python3 git rsync; do
    command -v "$tool" >/dev/null || missing+=("$tool")
done
[ -f /usr/include/openssl/ssl.h ] || missing+=(libssl-dev)
[ -f /usr/include/libelf.h ] || [ -f /usr/include/elfutils/libelf.h ] || missing+=(libelf-dev)
[ -f /usr/src/linux-headers-7.0.0-30-generic/.config ] || missing+=(linux-headers-7.0.0-30-generic)
if [ "${#missing[@]}" -gt 0 ]; then
    echo "Missing: ${missing[*]}"
    echo "Install with:"
    echo "  sudo apt install build-essential bc bison flex libssl-dev libelf-dev git rsync linux-headers-7.0.0-30-generic"
    exit 1
fi

mkdir -p "$ROOT"
if [ ! -d "$CLONE/.git" ]; then
    git init -q "$CLONE"
    git -C "$CLONE" remote add origin "$URL"
fi
if ! git -C "$CLONE" cat-file -e "$BASE^{commit}" 2>/dev/null; then
    echo "Fetching qcom-next $BASE (shallow)"
    git -C "$CLONE" fetch --depth 1 origin "$BASE"
fi
if [ -e "$TREE" ]; then
    echo "$TREE exists; leaving it as is"
else
    bash "$REPO/scripts/linux/prepare-qcom-next-glymur.sh" "$CLONE" "$TREE" "$REPO"
fi
nproc_n="$(nproc)"
cat <<EOF

Ready. Build (about 10-20 min on 12 cores) and install:
  GLYMUR_SUFFIX=-2 bash $REPO/scripts/linux/build-qcom-next-glymur.sh $TREE $ROOT/build-glymur $nproc_n
  sudo bash $REPO/scripts/linux/glymur-ssd/install-kernel.sh $ROOT/build-glymur
Use a new GLYMUR_SUFFIX for every build you install.
EOF
