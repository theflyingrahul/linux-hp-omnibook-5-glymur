#!/usr/bin/env bash
set -euo pipefail

# Install the Adreno X2-85 microcode and GMU firmware that msm requests
# (qcom/gen80100_sqe.fw, qcom/gen80100_gmu.bin) into
# /lib/firmware/updates/qcom, which takes precedence over the distribution's
# linux-firmware. The files come from linux-firmware (Qualcomm,
# redistributable; see WHENCE: "adreno - Qualcomm Adreno GPU firmware") and
# are staged on the USB next to the kernel, not committed here.
#
#   sudo bash install-gpu-firmware.sh <dir containing qcom/gen80100_*>

SRC="${1:?usage: install-gpu-firmware.sh <dir with qcom/gen80100_sqe.fw and gen80100_gmu.bin>}"
DST=/lib/firmware/updates/qcom

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
[ "$(findmnt -n -o LABEL /)" = glymur-root ] || { echo '/ is not glymur-root; refusing' >&2; exit 1; }

# Hashes of the linux-firmware files as fetched on 2026-09-29 (identical on
# gitlab.com/kernel-firmware and git.kernel.org).
while read -r sum name; do
    got="$(sha256sum "$SRC/qcom/$name" | cut -d' ' -f1)"
    [ "$got" = "$sum" ] || { echo "hash mismatch for $name" >&2; exit 1; }
    install -D -m 644 "$SRC/qcom/$name" "$DST/$name"
    echo "installed $DST/$name"
done <<'EOF'
bfcc5193269855bab8961a83425d7ef1f1188e76cd6aee70a5a82f0c1aa7b258 gen80100_sqe.fw
dae725872a751eccb73aa563dc2d4aeee3ddcc53805a900783787c329cab4d20 gen80100_gmu.bin
EOF
