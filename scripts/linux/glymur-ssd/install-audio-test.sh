#!/usr/bin/env bash
set -euo pipefail

# Install the audio test: the test DTB for the newest kernel and the
# AudioReach topology. See README.md.
#   sudo bash install-audio-test.sh

K="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/audio-test"
DTB=mahua-hp-omnibook-5-bf1xxx-test.dtb
TPLG=HP-OmniBook-5-16-bf1xxx-tplg.bin
[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
[ "$(findmnt -n -o LABEL /)" = glymur-root ] || { echo 'not on the SSD install; refusing' >&2; exit 1; }
(cd "$K" && sha256sum --quiet -c SHA256SUMS) || { echo 'checksum mismatch; nothing installed' >&2; exit 1; }

want="$(cat "$K/kernel-release")"
dir="$(readlink -f /boot/glymur-dtb)"
case "$dir" in
    */dtbs/"$want"/qcom) ;;
    *) echo "/boot/glymur-dtb is $dir, not kernel $want; refusing" >&2; exit 1 ;;
esac
[ -f "$dir/$DTB.orig" ] || cp -a "$dir/$DTB" "$dir/$DTB.orig"
install -m 644 "$K/$DTB" "$dir/$DTB"
install -D -m 644 "$K/$TPLG" "/lib/firmware/qcom/glymur/$TPLG"
sha256sum "$dir/$DTB" "/lib/firmware/qcom/glymur/$TPLG"
echo "Installed. Boot 'Ubuntu on SSD: test device tree', then run check-audio.sh."
echo "Undo: sudo cp $dir/$DTB.orig $dir/$DTB"
