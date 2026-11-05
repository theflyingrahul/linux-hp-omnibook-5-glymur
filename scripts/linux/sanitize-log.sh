#!/usr/bin/env bash
set -euo pipefail
# Strip identifiers from a log before it goes into captures/.
#   sanitize-log.sh IN OUT
sed -E \
 -e 's/\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b/xx:xx:xx:xx:xx:xx/g' \
 -e 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/<uuid>/g' \
 -e 's/[0-9a-fA-F]{8}\\x2d[0-9a-fA-F]{4}\\x2d[0-9a-fA-F]{4}\\x2d[0-9a-fA-F]{4}\\x2d[0-9a-fA-F]{12}/<uuid>/g' \
 -e 's/(SerialNumber: )(.*)/\1<serial>/; s/(xhci-hcd.*)<serial>/\1xhci/' \
 -e 's/\brahul\b/user/g' \
 -e 's/[A-Za-z0-9._+-]+@[A-Za-z0-9-]+\.[A-Za-z.]+/<email>/g' \
 -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/<ip>/g' "$1" > "$2"
