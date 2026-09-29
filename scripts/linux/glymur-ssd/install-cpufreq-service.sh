#!/usr/bin/env bash
set -euo pipefail

# Install and enable glymur-cpufreq.service (see the unit for when it runs).
#   sudo bash install-cpufreq-service.sh          install and enable
#   sudo bash install-cpufreq-service.sh --remove disable and remove

U=/etc/systemd/system/glymur-cpufreq.service
[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
[ "$(findmnt -n -o LABEL /)" = glymur-root ] || { echo '/ is not glymur-root; refusing' >&2; exit 1; }
if [ "${1:-}" = --remove ]; then
    systemctl disable glymur-cpufreq.service 2>/dev/null || true
    rm -f "$U"; systemctl daemon-reload; echo "removed $U"; exit 0
fi
install -m 644 "$(dirname "$0")/glymur-cpufreq.service" "$U"
systemctl daemon-reload
systemctl enable glymur-cpufreq.service
echo "enabled $U (runs only on boots whose device tree has the SCMI polling fix)"
