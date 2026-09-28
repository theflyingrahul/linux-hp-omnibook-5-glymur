#!/usr/bin/env bash
set -euo pipefail

# Install the HP-published firmware the device-tree boot needs, from the
# repository's boards/hp-omnibook-5-16-bf1xxx/firmware (checked against its
# MANIFEST.tsv), into /usr/lib/firmware/updates so no packaged file is
# replaced:
#   qcom/glymur/HP/omnibook-5-16-bf1xxx/  ADSP and CDSP images, dtbs, .jsn
#       (the firmware-name paths in mahua-hp-omnibook-5-bf1xxx.dts)
#   qca/ornbtfw11.tlv, qca/ornnv11.*      QCC2072 Bluetooth: HP's "Colorado"
#       clnbtfw10.tlv/clnbtnv10.* under btqca's "Orion" names. The "10" in
#       HP's names is not the ROM: the patch header says ROM build 0x0101,
#       the ROM 1.1 the controller reports, so btqca asks for ornbtfw11.tlv
#       and ornnv11.b<board> (board 0x17 has its own HP file). These
#       override linux-firmware's generic ROM-1.1 pair with the files
#       Windows uses on this laptop.
#
#   sudo bash install-firmware.sh

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FW="$REPO/boards/hp-omnibook-5-16-bf1xxx/firmware"
DEST=/usr/lib/firmware/updates

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
(cd "$FW" && awk -F'\t' '{print $1 "  " $3}' MANIFEST.tsv | sha256sum --quiet -c -) ||
    { echo 'firmware manifest mismatch; refusing' >&2; exit 1; }

soc="$DEST/qcom/glymur/HP/omnibook-5-16-bf1xxx"
mkdir -p "$soc" "$DEST/qca"
adsp="$FW/qcsubsys_ext_adsp8480_4500R_HDCP_WHQL"
cdsp="$FW/qcnspmcdm8480"
install -m 644 "$adsp/qcadsp8480.mbn" "$adsp/adsp_dtbs.elf" \
    "$adsp/adspr.jsn" "$adsp/adsps.jsn" "$adsp/adspua.jsn" "$soc/"
install -m 644 "$cdsp/qccdsp8480.mbn" "$cdsp/cdsp_dtbs.elf" "$soc/"

bt="$FW/qcbluetooth8480_WHQL"
install -m 644 "$bt/clnbtfw10.tlv" "$DEST/qca/ornbtfw11.tlv"
for nvm in "$bt"/clnbtnv10.*; do
    install -m 644 "$nvm" "$DEST/qca/ornnv11.${nvm##*.}"
done
# Earlier versions installed these under ROM-10 names, which btqca never asks for.
rm -f "$DEST"/qca/ornbtfw10.tlv "$DEST"/qca/ornnv10.*
ls -l "$soc" "$DEST"/qca/orn*
echo "Installed HP firmware under $DEST."
