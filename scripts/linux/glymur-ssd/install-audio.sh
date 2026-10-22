#!/usr/bin/env bash
set -euo pipefail

# Install the speaker and microphone userspace: the AudioReach topology, the
# ALSA UCM profile and the WirePlumber names, from audio/ next to this
# script. See README.md. --speaker-eq installs the topology variant with
# HP's speaker filter on the DSP (docs/audio-speaker-eq-2026-10-23.md);
# running it again without the option puts the plain topology back.
#   sudo bash install-audio.sh [--speaker-eq]

K="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/audio"
NAME=MAHUA-HP-OmniBook-5-16-bf1xxx
SRC=$NAME
[ "${1:-}" = --speaker-eq ] && SRC=$NAME-speaker-eq
FW=/usr/lib/firmware/updates/qcom/glymur
BOARD=HP/omnibook-5-16-bf1xxx
[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
[ "$(findmnt -n -o LABEL /)" = glymur-root ] || { echo 'not on the SSD install; refusing' >&2; exit 1; }
(cd "$K" && sha256sum --quiet -c SHA256SUMS) || { echo 'checksum mismatch; nothing installed' >&2; exit 1; }

# Topology: the board directory, plus a link at the name the kernel asks
# for (qcom/glymur/<sound card model>-tplg.bin), as linux-firmware does.
install -D -m 644 "$K/$SRC-tplg.bin" "$FW/$BOARD/$NAME-tplg.bin"
echo "Topology: $SRC"
ln -sfn "$BOARD/$NAME-tplg.bin" "$FW/$NAME-tplg.bin"
sha256sum "$FW/$BOARD/$NAME-tplg.bin"
# The kernel -13 test's topology name.
old=/usr/lib/firmware/qcom/glymur/HP-OmniBook-5-16-bf1xxx-tplg.bin
if [ -e "$old" ] && ! dpkg -S "$old" >/dev/null 2>&1; then rm -v "$old"; fi

# UCM: new files only; never replace a file the alsa-ucm-conf package owns.
U=/usr/share/alsa/ucm2
(cd "$K/ucm2" && find . -type f) | while read -r f; do
    if [ -e "$U/$f" ] && ! cmp -s "$K/ucm2/$f" "$U/$f"; then
        dpkg -S "$U/${f#./}" >/dev/null 2>&1 &&
            { echo "refusing to replace packaged $U/${f#./}" >&2; continue; }
    fi
    install -D -m 644 "$K/ucm2/$f" "$U/${f#./}"
    echo "UCM: $U/${f#./}"
done
# WirePlumber: the names Windows uses, as a local admin file.
WP=/etc/wireplumber/wireplumber.conf.d/51-hp-omnibook-5-16-audio.conf
install -D -m 644 "$K/wireplumber/${WP##*/}" "$WP"
echo "WirePlumber: $WP"

echo "Installed. Boot 'Ubuntu on SSD: test device tree', then run check-audio.sh."
echo "Undo: sudo rm -r $FW/$NAME-tplg.bin $FW/HP $U/HP/OmniBook-5-16-bf1xxx \\"
echo "  $U/conf.d/glymur/HP-HPOmniBook5Laptop16_bf1xxx-ConfigID-8F47.conf $WP"
