#!/usr/bin/env bash
set -u

# Headset jack report, test device tree (kernel -19 on): whether the WCD9378
# attached on swr2, what controls and jack events its SDCA driver offers,
# and, only if asked, a tone in the headphones and a recording from the
# headset microphone. There is no UCM for the headset yet: this routes the
# DSP mixers by hand and puts them back afterwards. See README.md.
#   sudo bash check-headset.sh

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
[ -n "${SUDO_USER:-}" ] || { echo 'run with sudo from the desktop user' >&2; exit 1; }
OUT="/var/log/glymur/headset-test-$(date +%Y%m%dT%H%M%S).txt"
WAV=/tmp/glymur-headset
mkdir -p /var/log/glymur "$WAV"
chown "$SUDO_USER" "$WAV"
exec > >(tee "$OUT") 2>&1
sect() { printf '\n==== %s\n' "$*"; }
ask() { local a; while read -r -t 0.05 -n 4096 _ </dev/tty 2>/dev/null; do :; done; read -r -p "$1 " a </dev/tty; a=$(printf '%s' "$a" | sed -E 's/\x1b\[[0-9;]*[~A-Za-z]//g; s/\[[0-9]+~//g'); echo "answer: $a"; REPLY=$a; }
asuser() { sudo -u "$SUDO_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$SUDO_USER")" "$@"; }
cget() { amixer -c "$CARD" cget "name=$1" 2>&1 | sed -n 's/.*: values=//p'; }
cset() { amixer -c "$CARD" -q cset "name=$1" "$2" 2>&1; echo "  $1 = $(cget "$1")"; }
# Jack controls are on the card interface (iface=CARD), so read them by numid;
# GE 35 Detected Mode (the codec's jack type) as well.
jacks() {
    amixer -c "$CARD" controls 2>/dev/null | grep -i -E "jack|Detected Mode|Selected Mode" |
        while IFS= read -r l; do
            n=${l%%,*}
            printf '  %-48s %s\n' "${l#*name=}" \
                "$(amixer -c "$CARD" cget "$n" 2>&1 | sed -n 's/.*: values=//p' | head -1)"
        done
    journalctl -k --no-pager --since "-20s" | grep -i -E 'jack|wcd|sdca' | tail -5 || true
    grep -B1 -A4 -i 'jack\|headset\|headphone' /proc/bus/input/devices | grep -E '^N:|^H:' || true
}

sect system
uname -r
tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null; echo
TPLG=/lib/firmware/updates/qcom/glymur/MAHUA-HP-OmniBook-5-16-bf1xxx-tplg.bin
ls -l "$TPLG" 2>&1 && sha256sum "$(readlink -f "$TPLG")"

sect "SoundWire controllers (swr1 6a80000 lanes only, swr2 7630000 the headset bus)"
for d in /sys/bus/platform/devices/6a80000.soundwire /sys/bus/platform/devices/7630000.soundwire; do
    printf '%s driver=%s runtime=%s\n' "$(basename "$d")" \
        "$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null)" \
        "$(cat "$d/power/runtime_status" 2>/dev/null)"
done

sect "SoundWire devices (link:manufacturer:part:version:unique id)"
for d in /sys/bus/soundwire/devices/*; do
    [ -e "$d" ] || continue
    printf '%-40s driver=%s status=%s\n' "$(basename "$d")" \
        "$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null)" \
        "$(cat "$d/status" 2>/dev/null)"
done

sect "headset reset line (TLMM 191)"
grep -E ' gpio191 ' /sys/kernel/debug/gpio 2>&1

sect "modules"
lsmod | grep -E 'wcd9378|sdca|soundwire|lpass|lpasscc|snd_soc_x1e80100' || true

sect "kernel log: headset path"
journalctl -k -b --no-pager |
    grep -iE 'wcd|tambora|sdca|sdw|swr|soundwire|rx.macro|tx.macro|lpasscc|lpassaudiocc|0217:0110|jack|Oops|BUG' |
    tail -120

sect "ALSA card"
cat /proc/asound/cards
CARD=$(awk '/OmniBook|HP-OmniBook|HPOmniBook/ {print $1; exit}' /proc/asound/cards)
echo "card: ${CARD:-none}"
[ -n "$CARD" ] || { echo 'no HP sound card; stopping'; echo "Saved to $OUT"; exit 0; }
cat /proc/asound/card"$CARD"/pcm*/info 2>/dev/null | grep -E '^(card|device|id|name|stream):'

sect "all controls with values (for the headset UCM)"
amixer -c "$CARD" contents 2>&1

sect "jack state, nothing plugged"
jacks

ask "Plug in a wired headset (or headphones) now, then press Enter."
sleep 2
sect "jack state, plugged"
ask "What did you plug in: a combo headset with a microphone (4-pole plug, three rings) or headphones only (3-pole)? Does it have buttons?"
jacks
journalctl -k -b --no-pager --since "-30s" | grep -iE 'wcd|sdca|jack|swr|sdw' || true

M_WSA='WSA_CODEC_DMA_RX_0 Audio Mixer MultiMedia1'
M_RX='RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia1'
M_VA='MultiMedia2 Mixer VA_CODEC_DMA_TX_0'
M_TX='MultiMedia2 Mixer TX_CODEC_DMA_TX_3'

# From -21: -20 and -21 played nothing and recorded silence because the RX
# macro muxes and the TX decimator path were never set (all ZERO). This
# routes the whole path, as alsa-ucm-conf's rx-macro HeadphoneEnableSeq and
# tx-macro SoundwireMic*EnableSeq do, and uses the card directly with
# PipeWire paused. Every control it changes is saved and put back.
SAVE=("$M_WSA" "$M_RX" "$M_VA" "$M_TX" 'RX_HPH PWR Mode' 'RX_MACRO RX0 MUX' 'RX_MACRO RX1 MUX'
      'RX INT0_1 MIX1 INP0' 'RX INT1_1 MIX1 INP0' 'RX INT0 DEM MUX' 'RX INT1 DEM MUX'
      'FU 6 Channel Switch' 'FU 6 Channel Volume' 'GE 35 Selected Mode'
      'TX DEC0 MUX' 'TX SMIC MUX0' 'TX_AIF1_CAP Mixer DEC0' 'DEC0 MODE' 'TX_DEC0 Volume')
declare -A SAVED
for c in "${SAVE[@]}"; do SAVED[$c]=$(cget "$c"); done
restore() {
    for c in "${SAVE[@]}"; do
        [ -n "${SAVED[$c]}" ] && amixer -c "$CARD" -q cset "name=$c" "${SAVED[$c]}" 2>/dev/null
    done
}
qset() { amixer -c "$CARD" -q cset "name=$1" "$2" 2>&1; }
PW_STOPPED=0
pw_stop() {
    asuser systemctl --user stop pipewire.socket pipewire-pulse.socket pipewire pipewire-pulse wireplumber 2>&1 | tail -2
    PW_STOPPED=1; sleep 1
}
pw_start() {
    [ "$PW_STOPPED" = 1 ] || return 0
    asuser systemctl --user start pipewire.socket pipewire-pulse.socket wireplumber 2>&1 | tail -2
    PW_STOPPED=0
}
trap 'restore; pw_start' EXIT
peak() {
    python3 -c '
import array, sys, wave
try:
    w = wave.open(sys.argv[1]); a = array.array("h", w.readframes(w.getnframes()))
    print(max((abs(x) for x in a), default=0))
except Exception:
    print(-1)
' "$1"
}
# The jack's group entity: the host selects the mode the codec detected.
select_mode() {
    local det
    det=$(cget 'GE 35 Detected Mode')
    echo "GE 35 Detected Mode: ${det:-?}"
    [ -n "$det" ] && [ "$det" != 0 ] && cset 'GE 35 Selected Mode' "$det"
}
hp_route() {
    select_mode
    cset "$M_WSA" 0
    cset "$M_RX" 1
    cset 'RX_HPH PWR Mode' LOHIFI
    cset 'RX_MACRO RX0 MUX' AIF1_PB
    cset 'RX_MACRO RX1 MUX' AIF1_PB
    cset 'RX INT0_1 MIX1 INP0' RX0
    cset 'RX INT1_1 MIX1 INP0' RX1
    cset 'RX INT0 DEM MUX' CLSH_DSM_OUT
    cset 'RX INT1 DEM MUX' CLSH_DSM_OUT
    cset 'FU 6 Channel Switch' on,on
}
play() {
    timeout -k 2 12 aplay -q -D "plughw:$CARD,0" "$1" 2>&1 | tail -3
    echo "  aplay exit ${PIPESTATUS[0]} (124: timed out)"
}

python3 -c '
import math, struct, sys, wave
for name, side in (("left", 0), ("right", 1)):
    w = wave.open("%s/%s.wav" % (sys.argv[1], name), "w")
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
    amp = int(32767 * 0.03)  # about -30 dBFS
    frames = []
    for i in range(96000):
        v = int(amp * math.sin(2 * math.pi * 1000 * i / 48000))
        frames.append(struct.pack("<hh", v if side == 0 else 0, v if side == 1 else 0))
    w.writeframes(b"".join(frames)); w.close()
' "$WAV"
chown "$SUDO_USER" "$WAV"/*.wav

sect "headphones: the full RX path, played directly to the card"
ask "Play a quiet 1 kHz tone into the headset, left then right, about 2 s each? Keep the headset away from your ears. Desktop sound pauses during the test. (y/N)"
if [ "$REPLY" = y ]; then
    pw_stop
    hp_route
    for side in left right; do
        echo "playing $side"
        play "$WAV/$side.wav"
        ask "Tone '$side': where did you hear it: headset left, headset right, both, speakers, or nothing?"
    done
    # The codec's volume is a two-byte write over SoundWire paging; -20's
    # backports/0085 keeps both bytes. Readback may be cached, so listen too.
    sect "headset volume writes (two-byte, SoundWire paging)"
    info=$(amixer -c "$CARD" cget "name=FU 6 Channel Volume" 2>&1)
    lo=$(echo "$info" | sed -n 's/.*min=\([-0-9]*\).*/\1/p')
    hi=$(echo "$info" | sed -n 's/.*max=\([-0-9]*\).*/\1/p')
    echo "FU 6 Channel Volume: min=$lo max=$hi now $(cget 'FU 6 Channel Volume')"
    if [ -n "$lo" ] && [ -n "$hi" ]; then
        for frac in 4 2; do
            v=$(( lo + (hi - lo) / frac ))
            cset 'FU 6 Channel Volume' "$v,$v"
            echo "playing left at 1/$frac of the range"
            play "$WAV/left.wav"
        done
        ask "Was the second tone clearly louder than the first?"
    fi
    journalctl -k -b --no-pager --since "-90s" | grep -iE 'wcd|sdca|swr|sdw|q6apm|CMD timeout|error' | tail -20 || true
    restore
    pw_start
fi

sect "headset microphone: scan of the TX macro's SoundWire inputs"
ask "Find the headset microphone: 12 recordings of 2 s, one per TX input. Keep talking into it (or tap it) for about 40 s. Desktop sound pauses. (y/N)"
if [ "$REPLY" = y ]; then
    pw_stop
    select_mode
    cset "$M_VA" 0
    cset "$M_TX" 1
    cset 'TX DEC0 MUX' SWR_MIC
    cset 'TX_AIF1_CAP Mixer DEC0' 1
    cset 'DEC0 MODE' ADC_DEFAULT
    cset 'TX_DEC0 Volume' 110
    echo "Talk now."
    best=; bestpk=0
    for i in 0 1 2 3 4 5 6 7 8 9 10 11; do
        qset 'TX SMIC MUX0' "SWR_MIC$i"
        timeout -k 2 6 arecord -q -D "plughw:$CARD,1" -f S16_LE -r 48000 -c 2 -d 2 "$WAV/mic$i.wav" 2>&1 | tail -1
        pk=$(peak "$WAV/mic$i.wav")
        printf '  SWR_MIC%-2s peak %s\n' "$i" "$pk"
        if [ "$pk" -gt "$bestpk" ] 2>/dev/null; then bestpk=$pk; best=$i; fi
    done
    echo "loudest: ${best:+SWR_MIC$best} (peak $bestpk; under 50 is silence)"
    journalctl -k -b --no-pager --since "-90s" | grep -iE 'wcd|sdca|swr|sdw|q6apm|CMD timeout|error' | tail -20 || true
    if [ -n "$best" ] && [ "$bestpk" -ge 50 ]; then
        ask "Play the loudest recording back in the headset? (y/N)"
        if [ "$REPLY" = y ]; then
            hp_route
            play "$WAV/mic$best.wav"
            ask "Did you hear your voice, and how did it sound (clear, quiet, noisy, distorted, nothing)?"
        fi
    fi
    restore
    pw_start
fi

# Combo headsets report their buttons through the jack's input device.
sect "headset buttons (15 s capture)"
echo "Press each headset button once, slowly: play/pause, then volume up and down if it has them."
python3 - <<'PY'
import os, re, select, struct, time
fds = {}
for block in open("/proc/bus/input/devices").read().split(chr(10) * 2):
    name = re.search(r'N: Name="([^"]*)"', block)
    ev = re.search(r"H: Handlers=.*?(event\d+)", block)
    if name and ev and re.search("jack|headset|headphone", name.group(1), re.I):
        fds[os.open("/dev/input/" + ev.group(1), os.O_RDONLY)] = name.group(1)
print("devices:", sorted(set(fds.values())) or "none", flush=True)
fmt = "llHHi"; size = struct.calcsize(fmt); end = time.time() + 15
while fds and time.time() < end:
    for fd in select.select(list(fds), [], [], 1.0)[0]:
        data = os.read(fd, size * 16)
        for i in range(0, len(data) - size + 1, size):
            sec, usec, typ, code, val = struct.unpack(fmt, data[i:i + size])
            if typ in (1, 5):
                print(f"{sec}.{usec:06d} {fds[fd]}: {'KEY' if typ == 1 else 'SW'} code={code} value={val}", flush=True)
print("capture done", flush=True)
PY
ask "Which buttons did you press, in order?"

ask "Unplug the headset now, then press Enter."
sleep 2
sect "jack state, unplugged"
jacks

sect "mixers restored"
for c in "$M_WSA" "$M_RX" "$M_VA" "$M_TX"; do printf '  %-40s %s\n' "$c" "$(cget "$c")"; done
echo
echo "Saved to $OUT"
