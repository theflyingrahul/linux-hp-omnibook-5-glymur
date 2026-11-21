#!/usr/bin/env bash
set -u

# RTC report (kernel -19 on): the ADSP's PMIC GLink RTC service, which
# Windows uses as \_SB.PRTC, and from -24 the PMK8850 RTC's raw counter
# and SDAM. See README.md.
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
# From -24: the PMK8850 RTC, read-only, as rtc1 (docs/rtc-2026-11-21.md).
# Does its counter hold wall time (UTC or local), or does an SDAM hold the
# offset the ADSP adds for Windows? Reads registers only, through the
# PMIC's debugfs regmap; the SDAM dump goes to a private file.
sect "PMK8850 RTC counter and SDAM (read-only)"
for r in /sys/class/rtc/rtc*; do
    case "$(cat "$r/name")" in
        *pm8xxx*|*6100*) printf '%s: %s %s, since_epoch=%s\n' "${r##*/}" "$(cat "$r/date")" "$(cat "$r/time")" "$(cat "$r/since_epoch")" ;;
    esac
done
journalctl -k -b --no-pager | grep -i 'pm8xxx\|6100.rtc\|rtc@6100' | tail -5
RM=""
for d in /sys/kernel/debug/regmap/*0-00*; do
    [ -r "$d/registers" ] || continue
    line=$(dd if="$d/registers" bs=9 skip=$((0x6100)) count=1 2>/dev/null)
    [ "${line%%:*}" = 6100 ] && { RM=$d; break; }
done
if [ -z "$RM" ]; then
    echo 'no PMK8850 regmap in debugfs with fixed-width lines; skipped'
else
    echo "regmap: $RM"
    regs() { dd if="$RM/registers" bs=9 skip=$(($1)) count=$(($2)) 2>/dev/null; }
    echo '-- RTC_RW (0x6100) and RTC_ALARM (0x6200) blocks'
    regs 0x6100 256 | paste -d' ' - - - - - - - - | sed 's/^/  /'
    regs 0x6200 256 | paste -d' ' - - - - - - - - | sed 's/^/  /'
    SD="/var/log/glymur/pmk8850-sdam-$(date +%Y%m%dT%H%M%S).txt"
    regs 0x7000 4096 > "$SD"
    echo "SDAM 0x7000-0x7fff saved to $SD (private: copy to .work/, never commit)"
    t_read=$(date +%s)
    c1=$(regs 0x6148 4 | awk '{print $2}' | tac | tr -d '\n')
    c2=$(regs 0x6148 4 | awk '{print $2}' | tac | tr -d '\n')
    echo "raw counter (0x6148..0x614b, LE): 0x$c1 then 0x$c2"
    # A trusted time: chrony's, or an HTTP Date header (no TLS, so no
    # certificate check against the wrong clock).
    ref=""; src=""
    if [ "$(timedatectl show -p NTPSynchronized --value)" = yes ]; then
        ref=$(date +%s); src="system clock (NTP synchronised)"
    else
        h=$(curl -sI --max-time 8 http://www.google.com/ | tr -d '\r' | sed -n 's/^[Dd]ate: //p')
        [ -n "$h" ] && { ref=$(date -d "$h" +%s); src="HTTP Date header ($h)"; }
    fi
    echo "reference: ${src:-none}"
    python3 - "$c2" "${ref:-0}" "$t_read" "$SD" <<'PY'
import sys, datetime as dt
c = int(sys.argv[1], 16); ref = int(sys.argv[2]); t_read = int(sys.argv[3])
print("counter as seconds since 1970: %s" % dt.datetime.fromtimestamp(c, dt.timezone.utc))
if not ref:
    print("no reference time: compare the line above with a clock by hand")
    sys.exit()
ref += 0  # taken right after the read
IST = 19800
for name, want in (("UTC", ref), ("IST", ref + IST)):
    print("counter - %s = %+d s" % (name, c - want))
# An SDAM word that turns the counter into wall time?
regs = {}
for line in open(sys.argv[4]):
    a, v = line.split(":")
    regs[int(a, 16)] = int(v, 16)
hits = []
for a in range(0x7000, 0x7ffd):
    if not all(a + i in regs for i in range(4)):
        continue
    w = sum(regs[a + i] << (8 * i) for i in range(4))
    for name, want in (("UTC", ref), ("IST", ref + IST)):
        if abs((c + w) % (1 << 32) - want) < 3600:
            hits.append((a, w, name, (c + w) % (1 << 32) - want))
for a, w, name, d in hits[:20]:
    print("SDAM %#06x: %#010x, counter + word = %s %+d s" % (a, w, name, d))
if not hits:
    print("no SDAM word within an hour of counter + offset = UTC or IST")
PY
fi

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
