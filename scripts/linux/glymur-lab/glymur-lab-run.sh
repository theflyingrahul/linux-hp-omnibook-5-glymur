#!/usr/bin/env bash
set -u

# Display-lab session for the HP OmniBook 5 16-bf1xxx, run as the transient
# service glymur-lab (start-lab.sh starts it). One boot of the display-lab
# device tree collects evidence across subsystems and then tries eDP
# link-training variants at runtime, so no experiment needs its own reboot.
#
#   glymur-lab-run.sh KIT_DIR OUT_DIR
#
# Phases (everything is logged to OUT_DIR and the journal):
#   1 baseline: every subsystem as booted
#   2 firmware eDP snapshot (the working link, read-only)
#   3 Bluetooth: HP's Windows firmware pair versus linux-firmware
#   4 battery / PMIC GLink and CPU frequency diagnostics
#   5 display: stop the desktop, enable the eDP path by overlay and try
#     variants until the panel trains; on success the panel shows the
#     console and the lab stops there, otherwise it reboots at the end.
# Collectors record failures and carry on (set -u, not -e).

KIT="$1"
OUT="$2"
mkdir -p "$OUT"
LOG="$OUT/lab.log"
LAB=/sys/kernel/debug/glymur-lab
PHYP=/sys/module/phy_qcom_edp_lab/parameters
MDSS=ae00000.display-subsystem
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

say() {
    local msg="[glymur-lab $(date +%H:%M:%S)] $*"
    echo "$msg" | tee -a "$LOG"
    echo "$msg" >/dev/tty1 2>/dev/null || true
    echo "$msg" >/dev/kmsg 2>/dev/null || true
    # The laptop has hung hard twice with no oops; flush every line so the
    # last one on disk (and on the screen, tty1) names the step that did it.
    sync
    journalctl --sync 2>/dev/null || true
}
mark() { echo "glymur-lab MARK $1" >/dev/kmsg; }
since() { journalctl -k -b --no-pager -o short-monotonic | sed -n "/glymur-lab MARK $1\$/,\$p"; }
run() { echo "\$ $*"; timeout 60 "$@" 2>&1; }
sect() { printf '\n### %s\n' "$1"; }

say "session starting; output in $OUT"
{
    sect kernel; uname -a; cat /proc/cmdline; tr -d '\0' </proc/device-tree/model; echo
    sect kit; ls -l "$KIT"
} >"$OUT/00-session.txt" 2>&1

# ---------------------------------------------------------------- setup
mkdir -p /run/modprobe.d
cat >/run/modprobe.d/glymur-lab.conf <<'EOF'
# glymur-lab: keep the stock eDP PHY driver out; the instrumented one binds.
install phy_qcom_edp /bin/true
options msm dyndbg=+p
options panel_samsung_atna33xc20 dyndbg=+p
EOF
insmod "$KIT/glymur_lab.ko" 2>>"$LOG" || { say "glymur_lab.ko failed to load; stopping"; exit 1; }
insmod "$KIT/phy-qcom-edp-lab.ko" 2>>"$LOG" || { say "phy-qcom-edp-lab.ko failed to load; stopping"; exit 1; }

# ---------------------------------------------------------------- 1 baseline
say "phase 1: baseline of every subsystem"
{
    if [ -x /usr/local/sbin/glymur-boot-report ]; then
        sect 'boot report'
        GLYMUR_REPORT_DELAY=0 /usr/local/sbin/glymur-boot-report
        cat "$(ls -1t /var/log/glymur/boot-*.txt | head -n 1)"
    fi
    sect 'modules'; lsmod
    sect 'deferred'; cat /sys/kernel/debug/devices_deferred
    sect 'regulators'; cat /sys/kernel/debug/regulator/regulator_summary
    sect 'clocks (display, tcsr)'; grep -E 'disp_cc|tcsr|dptx3|edp' /sys/kernel/debug/clk/clk_summary
    sect 'interconnect'; head -n 200 /sys/kernel/debug/interconnect/interconnect_summary
    sect 'genpd'; cat /sys/kernel/debug/pm_genpd/pm_genpd_summary
    sect 'rpmsg'; ls -l /sys/bus/rpmsg/devices/
    sect 'remoteproc'; for r in /sys/class/remoteproc/*; do echo "$r $(cat "$r/name") $(cat "$r/state")"; done
    sect 'full kernel log'; journalctl -k -b --no-pager -o short-monotonic
} >"$OUT/10-baseline.txt" 2>&1

# ---------------------------------------------------------------- 2 firmware snapshot
sync
say "phase 2: firmware eDP snapshot"
cat "$LAB/snapshot" >"$OUT/20-fw-snapshot.txt" 2>&1
python3 "$KIT/analyze-fw-snapshot.py" "$OUT/20-fw-snapshot.txt" >"$OUT/21-fw-analysis.txt" 2>&1
cat "$OUT/21-fw-analysis.txt" >>"$LOG"
FW_LANES='' FW_MAP='' FW_RATE_HZ=''
eval "$(grep -E '^FW_(LANES|MAP|RATE_HZ)=[0-9,]*$' "$OUT/21-fw-analysis.txt")"
say "firmware link: lanes=${FW_LANES:-?} map=${FW_MAP:-?} rate=${FW_RATE_HZ:-?}"

# ---------------------------------------------------------------- 3 bluetooth
say "phase 3: Bluetooth, HP firmware pair versus linux-firmware"
bt_state() {
    sect "$1"
    ls /sys/class/bluetooth/
    run bluetoothctl show
    run bluetoothctl --timeout 8 scan on | grep -c 'NEW' | sed 's/^/new devices seen: /'
}
bt_rebind() {
    local dev drv=/sys/bus/serial/drivers/hci_uart_qca
    dev="$(ls "$drv" 2>/dev/null | grep -E '^serial[0-9]+-[0-9]+$' | head -n 1)"
    [ -n "$dev" ] || { echo "no hci_uart_qca device bound"; return 1; }
    echo "$dev" >"$drv/unbind"; sleep 2; echo "$dev" >"$drv/bind"; sleep 10
}
FWDIR=/lib/firmware/updates/qca
if cmp -s "$KIT/bt/clnbtfw10.tlv" "$FWDIR/ornbtfw11.tlv" && cmp -s "$KIT/bt/clnbtnv10.b17" "$FWDIR/ornnv11.b17"; then
    say "Bluetooth: HP's firmware pair is already installed and in use; skipping the A/B"
else
{
    bt_state 'before (linux-firmware)'
    FWDIR=/lib/firmware/updates/qca
    mkdir -p "$FWDIR" "$OUT/bt-backup"
    cp -a "$FWDIR"/orn*11* "$OUT/bt-backup/" 2>/dev/null
    install -m 644 "$KIT/bt/clnbtfw10.tlv" "$FWDIR/ornbtfw11.tlv"
    for f in "$KIT"/bt/clnbtnv10.*; do install -m 644 "$f" "$FWDIR/ornnv11.${f##*.}"; done
    mark bt-hp
    bt_rebind
    sect 'kernel log, HP firmware'; since bt-hp
    bt_state 'after (HP firmware)'
} >"$OUT/30-bluetooth.txt" 2>&1
if [ -e /sys/class/bluetooth/hci0 ] && bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then
    say "Bluetooth with HP's firmware pair: controller up (kept)"
else
    say "Bluetooth with HP's firmware pair failed; restoring linux-firmware"
    rm -f /lib/firmware/updates/qca/ornbtfw11.tlv /lib/firmware/updates/qca/ornnv11.*
    cp -a "$OUT/bt-backup/." /lib/firmware/updates/qca/ 2>/dev/null
    { mark bt-restore; bt_rebind; since bt-restore; bt_state 'restored'; } >>"$OUT/30-bluetooth.txt" 2>&1
fi
fi
sync

# ---------------------------------------------------------------- 4 battery, cpufreq
say "phase 4: battery / PMIC GLink and CPU frequency diagnostics"
{
    sect 'power supplies'; for s in /sys/class/power_supply/*; do echo "$s"; cat "$s/uevent"; done
    sect 'typec'; ls /sys/class/typec/
    sect 'rpmsg channels'; for d in /sys/bus/rpmsg/devices/*; do echo "$(basename "$d") driver=$(basename "$(readlink "$d/driver")" 2>/dev/null)"; done
    sect 'pmic_glink and friends'; lsmod | grep -iE 'glink|battmgr|ucsi|altmode|pdr|qrtr|rpmsg'
    sect 'aux devices'; ls -l /sys/bus/auxiliary/devices/
    sect 'kernel log (glink/battery)'; journalctl -k -b --no-pager | grep -iE 'glink|battmgr|ucsi|soccp|pdr|servreg|charger'
    mark pmic
    run modprobe qcom_battmgr; run modprobe ucsi_glink; run modprobe pmic_glink_altmode
    sleep 5
    sect 'after modprobe'; since pmic; ls /sys/class/power_supply/
    sect 'cpufreq'; ls /sys/devices/system/cpu/cpufreq/ /sys/bus/scmi_protocol/devices/
    sect 'kernel log (scmi/cpucp)'; journalctl -k -b --no-pager | grep -iE 'scmi|cpucp|mbox|cpufreq|perf'
    # Loading these took the whole laptop down in the first lab run (SCMI
    # timeouts, then a hard hang with no oops): opt in with GLYMUR_LAB_CPUFREQ=1.
    if [ "${GLYMUR_LAB_CPUFREQ:-0}" = 1 ]; then
        sync
        mark cpufreq
        run modprobe qcom-cpucp-mbox; run modprobe scmi-cpufreq
        sleep 3
        sect 'after modprobe'; since cpufreq; ls /sys/devices/system/cpu/cpufreq/ /sys/bus/scmi_protocol/devices/
    else
        echo 'scmi-cpufreq load skipped (it hung the first run); GLYMUR_LAB_CPUFREQ=1 enables it'
    fi
} >"$OUT/40-power.txt" 2>&1
sync

# ---------------------------------------------------------------- 5 display
say "phase 5: display experiments. The desktop stops now and the screen may"
say "go dark. Wait; the laptop reboots by itself when the lab is done, or"
say "shows this console if a variant trains the panel."
systemd-run --unit=glymur-lab-deadman --on-active=30min -p IgnoreOnIsolate=yes     --timer-property=IgnoreOnIsolate=yes /usr/bin/systemctl reboot >>"$LOG" 2>&1
sleep 5
say "step 5.1: stopping the desktop (this ends the logged-in session)"
# Stop only the desktop (isolate would also stop this transient service).
systemctl stop display-manager.service
sleep 5
say "step 5.2: desktop stopped; switching to this console"
chvt 1 2>/dev/null
sleep 2
say "step 5.3: enabling DRM debug logging"
echo 0x106 >/sys/module/drm/parameters/debug
sleep 2
say "step 5.4: applying the display overlay (dispcc, MDSS, DP3 PHY, panel supply)"

variant_capture() {
    local tag="$1" d
    {
        sect "kernel log $tag"; since "$tag"
        sect 'connectors'
        for c in /sys/class/drm/card*-*; do
            [ -d "$c" ] && echo "$(basename "$c") status=$(cat "$c/status") enabled=$(cat "$c/enabled") modes=$(head -n 2 "$c/modes" | tr '\n' ' ')"
        done
        sect 'DPCD'
        for d in /dev/drm_dp_aux*; do
            [ -e "$d" ] || continue
            for range in 0x0:256 0x100:32 0x200:16 0x600:1 0x700:32 0x2200:32; do
                echo "$d ${range%%:*}:"
                timeout 5 dd if="$d" bs=1 skip=$((${range%%:*})) count="${range##*:}" status=none | od -An -tx1 -v
            done
        done
        sect 'dri debugfs'; for f in /sys/kernel/debug/dri/*/dp_debug /sys/kernel/debug/dri/*/state; do [ -r "$f" ] && { echo "== $f"; timeout 5 cat "$f"; }; done
        sect 'clocks'; grep -E 'disp_cc|dptx3|edp|tcsr' /sys/kernel/debug/clk/clk_summary
        sect 'regulators'; cat /sys/kernel/debug/regulator/regulator_summary
        sect 'registers now'; timeout 10 cat "$LAB/snapshot"
        sect 'phy lab parameters'; grep -H . "$PHYP"/*
        sect 'dp_out'; cat "$LAB/dp_out"
    } >"$OUT/50-display-$tag.txt" 2>&1
}

# Wait for this attempt's verdict: trained, failed, or nothing (timeout).
verdict() {
    local tag="$1" i log
    for i in $(seq 1 40); do
        sleep 1
        log="$(since "$tag")"
        # Only msm's final verdicts: it retries lower rates and lane counts first.
        if echo "$log" | grep -qE 'Failed link training|DP display prepare failed'; then
            echo failed; return
        fi
        if echo "$log" | grep -q 'link training #2 on phy 0 successful'; then
            sleep 3
            if ! since "$tag" | grep -qE 'Failed link training|prepare failed'; then echo trained; return; fi
            echo failed; return
        fi
    done
    echo timeout
}

attempt() {
    local tag="$1"; shift
    say "variant $tag: $*"
    RESULT="$(verdict "$tag")"
    variant_capture "$tag"
    say "variant $tag: $RESULT"
    echo "$tag $RESULT $*" >>"$OUT/50-results.txt"
    [ "$RESULT" = trained ]
}

rebind() {
    local tag="$1"; shift
    echo "$MDSS" >/sys/bus/platform/drivers/msm-mdss/unbind 2>>"$LOG"
    sleep 2
    "$@"
    mark "$tag"
    echo "$MDSS" >/sys/bus/platform/drivers/msm-mdss/bind 2>>"$LOG"
}

success() {
    say "PANEL TRAINED with variant $1. The lab stops here; results in $OUT."
    say "Log in on this console and run 'sudo systemctl start display-manager' for the desktop."
    systemctl stop glymur-lab-deadman.timer 2>/dev/null
    sync
    exit 0
}

setp() { echo "$2" >"$PHYP/$1"; }

# V0: the full device tree's display path exactly as booted before.
mark v0-baseline
cat "$KIT/mahua-hp-omnibook-5-bf1xxx-lab-display.dtbo" >"$LAB/overlay"
say "step 5.5: display overlay applied; waiting for msm and the eDP link"
attempt v0-baseline "full-DT display, stock settings" && success v0-baseline

# V1: Windows' five display rails held on in high-power mode.
rebind v1-rails sh -c "cat '$KIT/mahua-hp-omnibook-5-bf1xxx-lab-rails.dtbo' >'$LAB/overlay'; sleep 5"
attempt v1-rails "HP display rails always-on HPM" && success v1-rails

rebind v2-ssc-off setp lab_ssc 0
attempt v2-ssc-off "SSC off" && success v2-ssc-off

rebind v3-ssc-on setp lab_ssc 1
attempt v3-ssc-on "SSC forced on" && success v3-ssc-on
setp lab_ssc -1

rebind v4-dp-tables setp lab_table 2
attempt v4-dp-tables "DP swing tables" && success v4-dp-tables
setp lab_table 0

rebind v5-fw-tx sh -c "echo 1 >'$PHYP/lab_uefi_tx'; echo 1 >'$PHYP/lab_uefi_misc'"
attempt v5-fw-tx "firmware TX drive/emphasis/LDO/polarity/offsets" && success v5-fw-tx

rebind v6-2lanes sh -c "echo 0 >'$PHYP/lab_uefi_tx'; echo 0 >'$PHYP/lab_uefi_misc'; echo data-lanes=0,1 >'$LAB/dp_out'"
attempt v6-2lanes "2 lanes" && success v6-2lanes

rebind v7-hbr sh -c "echo 1 >'$LAB/dp_out_reset'; echo link-frequencies=1620000000,2700000000 >'$LAB/dp_out'"
attempt v7-hbr "4 lanes, RBR/HBR only" && success v7-hbr

rebind v8-lanes-rev sh -c "echo 1 >'$LAB/dp_out_reset'; echo data-lanes=3,2,1,0 >'$LAB/dp_out'"
attempt v8-lanes-rev "lane map 3,2,1,0" && success v8-lanes-rev

# V9: copy the firmware's link: its lanes, lane map and rate, with its TX values.
spec=''
[ -n "$FW_MAP" ] && spec="data-lanes=$FW_MAP"
[ -n "$FW_RATE_HZ" ] && spec="$spec link-frequencies=$FW_RATE_HZ"
rebind v9-fw-mimic sh -c "echo 1 >'$LAB/dp_out_reset'; [ -n '$spec' ] && echo '$spec' >'$LAB/dp_out'; echo 1 >'$PHYP/lab_uefi_tx'; echo 1 >'$PHYP/lab_uefi_misc'"
attempt v9-fw-mimic "firmware lanes/map/rate + firmware TX ($spec)" && success v9-fw-mimic

say "no variant trained the panel; rebooting in 30 s (results in $OUT)"
sync
sleep 30
systemctl reboot
