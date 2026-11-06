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
ask() { local a; read -r -p "$1 " a </dev/tty; echo "answer: $a"; REPLY=$a; }
asuser() { sudo -u "$SUDO_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$SUDO_USER")" "$@"; }
cget() { amixer -c "$CARD" cget "name=$1" 2>&1 | sed -n 's/.*: values=//p'; }
cset() { amixer -c "$CARD" -q cset "name=$1" "$2" 2>&1; echo "  $1 = $(cget "$1")"; }
jacks() {
    amixer -c "$CARD" controls 2>/dev/null | grep -i 'jack' | sed 's/.*name=//' |
        while read -r c; do printf '  %-40s %s\n' "$c" "$(cget "${c//\'/}")"; done
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
jacks
journalctl -k -b --no-pager --since "-30s" | grep -iE 'wcd|sdca|jack|swr|sdw' || true

M_WSA='WSA_CODEC_DMA_RX_0 Audio Mixer MultiMedia1'
M_RX='RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia1'
M_VA='MultiMedia2 Mixer VA_CODEC_DMA_TX_0'
M_TX='MultiMedia2 Mixer TX_CODEC_DMA_TX_3'

sect "headphones: a quiet tone, speakers routed off"
ask "Play a quiet 1 kHz tone into the headset, left then right, about 2 s each? Keep the headset away from your ears at first. (y/N)"
if [ "$REPLY" = y ]; then
    python3 - "$WAV" <<'PY'
import math, struct, sys, wave
for name, side in (('left', 0), ('right', 1)):
    w = wave.open('%s/%s.wav' % (sys.argv[1], name), 'w')
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
    amp = int(32767 * 0.03)  # about -30 dBFS
    frames = []
    for i in range(96000):
        v = int(amp * math.sin(2 * math.pi * 1000 * i / 48000))
        frames.append(struct.pack('<hh', v if side == 0 else 0, v if side == 1 else 0))
    w.writeframes(b''.join(frames)); w.close()
PY
    chown "$SUDO_USER" "$WAV"/*.wav
    cset "$M_WSA" 0
    cset "$M_RX" 1
    asuser wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
    asuser wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.3
    for side in left right; do
        echo "playing $side"
        asuser pw-play "$WAV/$side.wav" 2>&1 | tail -2
        ask "Tone '$side': where did you hear it: headset left, headset right, both, speakers, or nothing?"
    done
    journalctl -k -b --no-pager --since "-60s" | grep -iE 'wcd|sdca|swr|sdw|q6apm|CMD timeout|error' || true
    cset "$M_RX" 0
    cset "$M_WSA" 1
fi

sect "headset microphone: 5 s recording, built-in microphones routed off"
ask "Record 5 s from the headset microphone? Speak into it. (y/N)"
if [ "$REPLY" = y ]; then
    cset "$M_VA" 0
    cset "$M_TX" 1
    asuser timeout 5 pw-record --rate 48000 --channels 2 --format s16 "$WAV/headset-mic.wav" 2>&1 | tail -3
    python3 - "$WAV/headset-mic.wav" <<'PY'
import array, sys, wave
try:
    w = wave.open(sys.argv[1]); a = array.array('h', w.readframes(w.getnframes()))
    peak = max((abs(x) for x in a), default=0)
    print('frames %d, peak %d (%s)' % (w.getnframes(), peak, 'SILENT' if peak < 50 else 'signal'))
except Exception as e:
    print('no recording:', e)
PY
    journalctl -k -b --no-pager --since "-30s" | grep -iE 'wcd|sdca|swr|sdw|q6apm|CMD timeout|error' || true
    cset "$M_TX" 0
    cset "$M_VA" 1
fi

sect "mixers restored"
for c in "$M_WSA" "$M_RX" "$M_VA" "$M_TX"; do printf '  %-40s %s\n' "$c" "$(cget "$c")"; done
echo
echo "Saved to $OUT"
