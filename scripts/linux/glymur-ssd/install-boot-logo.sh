#!/usr/bin/env bash
set -euo pipefail

# Give plymouth's "bgrt" theme the firmware's boot logo. A device-tree boot
# has no ACPI BGRT, so plymouth falls back to bgrt-fallback.png in the
# spinner theme; this installs boot-logo/bgrt-fallback.png from next to this
# script, made from HP's firmware logo and padded so that plymouth places
# it where the firmware draws it (docs/boot-logo-2026-10-23.md). A packaged
# file of that name is diverted, not overwritten. See README.md.
#   sudo bash install-boot-logo.sh            install
#   sudo bash install-boot-logo.sh --remove   restore the packaged file

K="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/boot-logo"
T=/usr/share/plymouth/themes/spinner/bgrt-fallback.png
[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
[ "$(findmnt -n -o LABEL /)" = glymur-root ] || { echo 'not on the SSD install; refusing' >&2; exit 1; }

if [ "${1:-}" = --remove ]; then
    rm -f "$T"
    dpkg-divert --local --rename --remove "$T" || true
    echo "restored: $(ls -l "$T" 2>/dev/null || echo "no $T")"
    exit 0
fi

(cd "$K" && sha256sum --quiet -c SHA256SUMS) || { echo 'checksum mismatch; nothing installed' >&2; exit 1; }
if dpkg -S "$T" >/dev/null 2>&1 && ! dpkg-divert --list "$T" | grep -q local; then
    dpkg-divert --local --rename --add "$T"
fi
install -D -m 644 "$K/bgrt-fallback.png" "$T"
echo "installed $T; plymouth theme: $(plymouth-set-default-theme 2>/dev/null || echo unknown)"
echo "It shows from the next boot. Undo: sudo bash install-boot-logo.sh --remove"
