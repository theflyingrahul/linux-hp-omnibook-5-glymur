#!/usr/bin/env bash
set -u

# Read-only copy of every EFI variable Linux can see (kernel -17 on, with
# the QSEECOM allowlist), as the baseline before any variable is written.
# The copy holds machine-specific data: keep it private (.work/), never
# commit it. See README.md.
#   sudo bash dump-efivars.sh

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
V=/sys/firmware/efi/efivars
OUT="/var/log/glymur/efivars-$(date +%Y%m%dT%H%M%S)"
mkdir -p "$OUT"
{
    echo "kernel: $(uname -r)"
    findmnt -n -o OPTIONS "$V" | sed 's/^/efivarfs mount: /'
    journalctl -k -b --no-pager | grep -iE 'qseecom|uefisecapp|efivar|rtc' | tail -20
} > "$OUT/report.txt" 2>&1
if [ -z "$(ls -A "$V" 2>/dev/null)" ]; then
    echo "no variables visible in $V" | tee -a "$OUT/report.txt"
    exit 1
fi
# name, size and attributes (the first 4 bytes) of each variable
for f in "$V"/*; do
    printf '%-80s %6d  attr %s\n' "${f##*/}" "$(stat -c %s "$f")" "$(od -An -tx4 -N4 "$f" | tr -d ' ')"
done > "$OUT/list.txt"
tar -C "$V" -czf "$OUT/efivars.tar.gz" . 2>>"$OUT/report.txt"
sha256sum "$OUT/efivars.tar.gz" >> "$OUT/report.txt"
echo "$(wc -l < "$OUT/list.txt") variables; saved to $OUT"
grep -E '^(RTCInfo|SmartAmpCalibrationData|BootOrder|SecureBoot)-' "$OUT/list.txt"
