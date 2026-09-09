#!/usr/bin/env bash
set -eo pipefail

EXTRACT_DIR=$1
PKG_ID=$2

if [[ -z "$EXTRACT_DIR" || -z "$PKG_ID" || ! -d "$EXTRACT_DIR" ]]; then
    echo "Usage: $0 <extract_dir> <pkg_id>"
    exit 1
fi

MANIFEST_DIR=".work/hp-software/manifests"
mkdir -p "$MANIFEST_DIR"
MANIFEST_FILE="${MANIFEST_DIR}/${PKG_ID}-analysis.txt"
true > "$MANIFEST_FILE"

echo "Inventorying INFs in $EXTRACT_DIR ..." | tee -a "$MANIFEST_FILE"
find "$EXTRACT_DIR" -type f -iname "*.inf" | while read -r inf; do
    echo "----------------------------------------" >> "$MANIFEST_FILE"
    echo "INF: $inf" >> "$MANIFEST_FILE"
    ./scripts/linux/parse-windows-inf.py "$inf" >> "$MANIFEST_FILE"
done

echo "" >> "$MANIFEST_FILE"
echo "Subsystem String Matches:" >> "$MANIFEST_FILE"

# List of interesting tokens
TOKENS="glymur X2E X2 Elite CPUCP SCMI SoCCP ADSP CDSP Hexagon Adreno GMU WCN C7700 WLAN Bluetooth LPASS WSA WCD SoundWire UCSI Type-C PCIe QUP I2C camera touch HID thermal EC"
for token in $TOKENS; do
    # search non-binary files for the token
    # to avoid huge binary dumps
    grep -rniI "$token" "$EXTRACT_DIR" 2>/dev/null | cut -c1-200 >> "$MANIFEST_FILE" || true
done

echo "Analysis written to $MANIFEST_FILE"
