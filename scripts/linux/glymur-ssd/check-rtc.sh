#!/usr/bin/env bash
set -u

# RTC report (kernel -19 on): the ADSP's PMIC GLink RTC service, which
# Windows uses as \_SB.PRTC. See README.md.
#   sudo bash check-rtc.sh
# Reads the time, works out whether the RTC holds UTC or local time (Windows
# keeps local time unless RealTimeIsUniversal is set; this laptop's Windows
# has it unset, India Standard Time), logs the raw words the service
# returns, and fires one alarm 20 s ahead without suspending. Writes
# nothing to the RTC: the driver refuses to set the time without
# allow-set-time, which the device tree does not set.

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
OUT="/var/log/glymur/rtc-test-$(date +%Y%m%dT%H%M%S).txt"
mkdir -p /var/log/glymur
exec > >(tee "$OUT") 2>&1
sect() { printf '\n==== %s\n' "$*"; }
ask() { local a; while read -r -t 0.05 -n 4096 _ </dev/tty 2>/dev/null; do :; done; read -r -p "$1 " a </dev/tty; a=$(printf '%s' "$a" | sed -E 's/\x1b\[[0-9;]*[~A-Za-z]//g; s/\[[0-9]+~//g'); printf '%s\n' "$a"; }

sect "driver"
modprobe rtc-qcom-glink 2>&1
sleep 2
journalctl -k -b --no-pager | grep -iE 'rtc|glink' | grep -viE 'pcie' | tail -20
for r in /sys/class/rtc/rtc*; do
    [ -e "$r" ] || { echo 'no RTC device'; exit 1; }
    printf '%s: name=%s hctosys=%s\n' "${r##*/}" "$(cat "$r/name")" "$(cat "$r/hctosys" 2>/dev/null)"
done
R=/sys/class/rtc/rtc0
for r in /sys/class/rtc/rtc*; do
    case "$(cat "$r/name")" in *glink*) R=$r ;; esac
done
DEV=/dev/${R##*/}
echo "using $DEV"

# On -20 the service answered nothing to 0x68 (-110) and the fallbacks
# (0x67 ticks, 0x65 property) failed too. The driver's debug lines show
# what it sends and what comes back (RX opcode, return status), per request.
sect "PMIC GLink RTC requests, with debug logging"
DD=/sys/kernel/debug/dynamic_debug/control
for m in rtc_qcom_glink pmic_glink; do
    echo "module $m +p" > "$DD" 2>/dev/null && echo "debug on: $m" || echo "no dynamic debug for $m"
done
t0=$(date '+%Y-%m-%d %H:%M:%S')
cat "$R/time" 2>&1 | sed 's/^/time read: /'
cat "$R/since_epoch" 2>&1 | sed 's/^/since_epoch read: /'
sleep 1
journalctl -k --no-pager --since "$t0" | grep -iE 'rtc|glink' | sed 's/^.*kernel: //' | head -40
for m in rtc_qcom_glink pmic_glink; do echo "module $m -p" > "$DD" 2>/dev/null; done

sect "time"
rtc_s=$(cat "$R/since_epoch")
now=$(date +%s)
off=$(date +%z)
off_s=$(( 10#${off:1:2} * 3600 + 10#${off:3:2} * 60 ))
[ "${off:0:1}" = - ] && off_s=$(( -off_s ))
diff=$(( rtc_s - now ))
echo "RTC     $(cat "$R/date") $(cat "$R/time")  (since_epoch $rtc_s)"
echo "system  $(date -u '+%F %T') UTC, $(date '+%F %T %Z') local, offset $off"
echo "RTC - UTC = $diff s"
if [ "${diff#-}" -lt 120 ]; then
    MODE=utc
    echo "=> the RTC holds UTC"
elif [ "$(( diff - off_s ))" -gt -120 ] && [ "$(( diff - off_s ))" -lt 120 ]; then
    MODE=local
    echo "=> the RTC holds local time, as Windows keeps it"
else
    MODE=unknown
    echo "=> neither UTC nor local time (off by $diff s): is the system clock synced?"
fi
timedatectl 2>&1 | sed 's/^/  /'

sect "raw words from the service (dynamic debug)"
DD=/sys/kernel/debug/dynamic_debug/control
if [ -w "$DD" ]; then
    t0=$(date +%s)
    echo 'module rtc_qcom_glink +p' > "$DD"
    cat "$R/time" >/dev/null
    cat "$R/wakealarm" >/dev/null 2>&1
    sleep 1
    echo 'module rtc_qcom_glink -p' > "$DD"
    journalctl -k --no-pager --since "@$t0" | grep -i rtc | tail -20
else
    echo "no $DD"
fi

sect "alarm, 20 s ahead, no suspend"
echo 0 > "$R/wakealarm" 2>/dev/null
before=$(grep -i rtc /proc/interrupts | tr -s ' ')
if echo +20 > "$R/wakealarm"; then
    echo "set: $(cat "$R/wakealarm")"
    sleep 25
    echo "after 25 s: wakealarm='$(cat "$R/wakealarm")' (empty once it fired)"
    grep -i rtc /proc/interrupts | tr -s ' '
    echo "before: $before"
    journalctl -k --no-pager --since '-30 s' | grep -i rtc | tail
else
    echo 'setting the alarm failed'
fi

if [ "$MODE" = local ] && ! timedatectl show -p LocalRTC --value | grep -qx yes; then
    echo
    echo "Linux treats the RTC as UTC, but it holds local time like Windows."
    if [ "$(ask 'Tell Linux the RTC is in local time (timedatectl set-local-rtc 1)? [y/N]')" = y ]; then
        timedatectl set-local-rtc 1
        timedatectl 2>&1 | sed 's/^/  /'
    fi
fi
echo "log: $OUT"
