#!/usr/bin/env bash
set -u

# Speaker and microphone report, kernel -13 test device tree on.
# Plays or records nothing unless asked. See README.md.
#   sudo bash check-audio.sh

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
OUT="/var/log/glymur/audio-test-$(date +%Y%m%dT%H%M%S).txt"
WAV=/tmp/glymur-audio
mkdir -p /var/log/glymur "$WAV"
exec > >(tee "$OUT") 2>&1
sect() { printf '\n==== %s\n' "$*"; }
ask() { local a; read -r -p "$1 " a </dev/tty; echo "answer: $a"; REPLY=$a; }

sect system
uname -r
tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null; echo
TPLG=/lib/firmware/qcom/glymur/HP-OmniBook-5-16-bf1xxx-tplg.bin
ls -l "$TPLG" 2>&1 && sha256sum "$TPLG"

sect "SoundWire devices (link:manufacturer:part:version:unique id)"
for d in /sys/bus/soundwire/devices/*; do
    [ -e "$d" ] || continue
    printf '%-40s driver=%s master=%s\n' "$(basename "$d")" \
        "$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null)" \
        "$(basename "$(dirname "$(readlink -f "$d")")")"
    for f in status dev-properties/mipi_revision; do
        [ -r "$d/$f" ] && printf '    %s: %s\n' "$f" "$(cat "$d/$f")"
    done
done
ls -d /sys/kernel/debug/soundwire/* 2>/dev/null

sect "amplifier reset lines (GPIO 204, 205)"
grep -E 'gpio20[45]\b' /sys/kernel/debug/gpio 2>&1 | head

sect "audio modules"
lsmod | grep -E 'snd_soc_x1e80100|wsa884x|soundwire|lpass|q6apm|q6prm|snd_q6|pinctrl_lpass' || true

sect "kernel log: audio"
journalctl -k -b --no-pager |
    grep -iE 'soundwire|sdw|swr|wsa|lpass|q6apm|q6prm|tplg|topology|va.macro|sndcard|x1e80100|glymur-snd|ASoC|snd' |
    tail -120

sect "ALSA cards and controls"
cat /proc/asound/cards
aplay -l 2>&1
arecord -l 2>&1
CARD=$(awk '/OmniBook|HP-OmniBook|HPOmniBook/ {print $1; exit}' /proc/asound/cards)
echo "card: ${CARD:-none}"
[ -n "$CARD" ] && amixer -c "$CARD" controls | wc -l

[ -n "$CARD" ] || { echo 'no HP sound card; stopping'; echo "Saved to $OUT"; exit 0; }
cset() { amixer -q -c "$CARD" cset "name=$1" "$2" 2>&1 | sed "s/^/  $1: /"; }

sect "microphones (DMIC0, DMIC1)"
ask "Record 5 s from the two internal microphones? Speak or tap near them. (y/N)"
if [ "$REPLY" = y ]; then
    cset 'MultiMedia2 Mixer VA_CODEC_DMA_TX_0' 1
    cset 'VA DEC0 MUX' VA_DMIC
    cset 'VA DMIC MUX0' DMIC0
    cset 'VA_AIF1_CAP Mixer DEC0' 1
    cset 'VA_DEC0 Volume' 100
    cset 'VA DEC1 MUX' VA_DMIC
    cset 'VA DMIC MUX1' DMIC1
    cset 'VA_AIF1_CAP Mixer DEC1' 1
    cset 'VA_DEC1 Volume' 100
    arecord -D "hw:$CARD,1" -f S16_LE -r 48000 -c 2 -d 5 "$WAV/mic.wav" 2>&1 | tail -3
    python3 - "$WAV/mic.wav" <<'PY'
import struct, sys, wave
w = wave.open(sys.argv[1])
n, ch = w.getnframes(), w.getnchannels()
s = struct.unpack('<%dh' % (n * ch), w.readframes(n))
for c in range(ch):
    x = s[c::ch]
    rms = (sum(v * v for v in x) / max(len(x), 1)) ** 0.5
    print('channel %d: %d frames, peak %d, rms %.0f (of 32767)' % (c, len(x), max(abs(v) for v in x), rms))
PY
    cp "$WAV/mic.wav" "/var/log/glymur/$(basename "$OUT" .txt)-mic.wav"
fi

sect "speakers"
ask "Play a quiet 1 kHz tone, left then right, about 2 s each? (y/N)"
if [ "$REPLY" = y ]; then
    python3 - "$WAV" <<'PY'
import math, struct, sys, wave
for name, side in (('left', 0), ('right', 1)):
    w = wave.open('%s/%s.wav' % (sys.argv[1], name), 'w')
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
    amp = int(32767 * 0.1)  # -20 dBFS
    frames = []
    for i in range(96000):
        v = int(amp * math.sin(2 * math.pi * 1000 * i / 48000))
        frames.append(struct.pack('<hh', v if side == 0 else 0, v if side == 1 else 0))
    w.writeframes(b''.join(frames)); w.close()
PY
    cset 'WSA_CODEC_DMA_RX_0 Audio Mixer MultiMedia1' 1
    for m in WSA WSA2; do
        cset "$m WSA RX0 MUX" AIF1_PB
        cset "$m WSA_RX0 INP0" RX0
        cset "$m WSA_RX0 Digital Volume" 68
        cset "$m WSA_COMP1 Switch" 0
    done
    for s in SpkrLeft SpkrRight; do
        for c in COMP BOOST DAC PBR; do cset "$s $c Switch" 1; done
        cset "$s VISENSE Switch" 0
        cset "$s WSA MODE" 0
        cset "$s PA Volume" 12
    done
    for side in left right; do
        echo "playing $side"
        aplay -D "hw:$CARD,0" "$WAV/$side.wav" 2>&1 | tail -2
        ask "Tone '$side': which speaker played, left, right, both or none?"
    done
    for s in SpkrLeft SpkrRight; do
        for c in COMP BOOST DAC PBR; do cset "$s $c Switch" 0; done
    done
    for m in WSA WSA2; do
        cset "$m WSA_RX0 INP0" ZERO
        cset "$m WSA RX0 MUX" ZERO
    done
fi

sect "kernel log after the tests"
journalctl -k -b --no-pager --since '-5 min' |
    grep -iE 'soundwire|sdw|swr|wsa|lpass|q6apm|ASoC|snd|error|fail' | tail -60
echo "Saved to $OUT"
