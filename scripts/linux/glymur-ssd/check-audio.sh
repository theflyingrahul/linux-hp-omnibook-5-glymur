#!/usr/bin/env bash
set -u

# Speaker and microphone report, test device tree (kernel -15 on): what
# attached, how PipeWire names it, the mute switches, LEDs and keys.
# Plays or records nothing unless asked; plays and records through
# PipeWire, as the desktop user. See README.md.
#   sudo bash check-audio.sh

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
[ -n "${SUDO_USER:-}" ] || { echo 'run with sudo from the desktop user' >&2; exit 1; }
OUT="/var/log/glymur/audio-test-$(date +%Y%m%dT%H%M%S).txt"
WAV=/tmp/glymur-audio
mkdir -p /var/log/glymur "$WAV"
chown "$SUDO_USER" "$WAV"
exec > >(tee "$OUT") 2>&1
sect() { printf '\n==== %s\n' "$*"; }
ask() { local a; read -r -p "$1 " a </dev/tty; echo "answer: $a"; REPLY=$a; }
asuser() { sudo -u "$SUDO_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$SUDO_USER")" "$@"; }
# LPASS TLMM GPIO 12/13 (7760000.pinctrl) and TLMM GPIO 204/205.
resets() { awk '/^gpiochip/ { lp = /7760000/ } lp && / gpio1[23] / || / gpio20[45] /' /sys/kernel/debug/gpio; }
leds() {
    for l in platform::mute platform::micmute; do
        printf '  %-18s brightness=%s trigger=%s\n' "$l" \
            "$(cat "/sys/class/leds/$l/brightness" 2>/dev/null)" \
            "$(grep -o '\[[^]]*\]' "/sys/class/leds/$l/trigger" 2>/dev/null)"
    done
}
switches() {
    for c in 'Speakers Switch' 'Mic LED Capture Switch'; do
        printf '  %-24s %s\n' "$c" "$(amixer -c "$CARD" cget "name=$c" 2>&1 | sed -n 's/.*: values=//p')"
    done
}
mutes() {
    printf '  sink muted: %s   source muted: %s\n' \
        "$(asuser wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>&1)" \
        "$(asuser wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>&1)"
}

sect system
uname -r
tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null; echo
TPLG=/lib/firmware/updates/qcom/glymur/MAHUA-HP-OmniBook-5-16-bf1xxx-tplg.bin
ls -l "$TPLG" 2>&1 && sha256sum "$(readlink -f "$TPLG")"

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

sect "amplifier reset lines (LPASS TLMM 12, 13; TLMM 204, 205; direction and function)"
resets 2>&1

sect "audio modules"
lsmod | grep -E 'snd_soc_x1e80100|wsa884x|soundwire|lpass|q6apm|q6prm|snd_q6|pinctrl_lpass|snd_ctl_led|hp_omnibook' || true

sect "kernel log: audio and EC"
journalctl -k -b --no-pager |
    grep -iE 'soundwire|sdw|swr|wsa|lpass|q6apm|q6prm|tplg|topology|va.macro|sndcard|x1e80100|glymur-snd|ASoC|snd|omnibook|EC id|Oops|BUG' |
    tail -120

sect "ALSA cards"
cat /proc/asound/cards
CARD=$(awk '/OmniBook|HP-OmniBook|HPOmniBook/ {print $1; exit}' /proc/asound/cards)
echo "card: ${CARD:-none}"
[ -n "$CARD" ] || { echo 'no HP sound card; stopping'; echo "Saved to $OUT"; exit 0; }

sect "ALSA UCM profile (what PipeWire uses)"
ls -l /usr/share/alsa/ucm2/conf.d/glymur/ /etc/wireplumber/wireplumber.conf.d/ 2>&1
alsaucm -c "hw:$CARD" dump text 2>&1 | head -50

sect "PipeWire: names (Windows: Qualcomm(R) Aqstic(TM) ACX Static Endpoints Audio Device)"
asuser wpctl status 2>&1 | sed -n '/^Audio/,/^Video/p' | head -30
asuser pw-dump 2>/dev/null | grep -E '"(device|node)\.(description|nick|name)"|"api\.alsa\.path"' | sort -u

sect "mute switches, LED binding and LEDs"
ls /sys/class/sound/ctl-led/*/card*/list 2>/dev/null | while read -r f; do echo "  $f: $(cat "$f")"; done
switches
leds
mutes

sect "microphones (DMIC0, DMIC1) through PipeWire"
ask "Record 5 s from the Microphone Array? Speak or tap near the microphones. (y/N)"
if [ "$REPLY" = y ]; then
    asuser wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0
    asuser timeout 5 pw-record --rate 48000 --channels 2 --format s16 "$WAV/mic.wav" 2>&1 | tail -3
    python3 - "$WAV/mic.wav" <<'PY'
import struct, sys, wave
w = wave.open(sys.argv[1])
n, ch = w.getnframes(), w.getnchannels()
s = struct.unpack('<%dh' % (n * ch), w.readframes(n))
for c in range(ch):
    x = s[c::ch]
    rms = (sum(v * v for v in x) / max(len(x), 1)) ** 0.5
    print('channel %d: %d frames, peak %d, rms %.0f (of 32767), %d distinct values' %
          (c, len(x), max(abs(v) for v in x), rms, len(set(x))))
PY
    cp "$WAV/mic.wav" "/var/log/glymur/$(basename "$OUT" .txt)-mic.wav"
fi

sect "speakers through PipeWire"
ask "Play a quiet 1 kHz tone on the Internal Speakers, left then right, about 2 s each? (y/N)"
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
    chown "$SUDO_USER" "$WAV"/*.wav
    asuser wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
    asuser wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5
    # The amplifiers detach when the bus runtime-suspends and need a while to
    # re-attach; a tone sent in that window is lost, so wake them first.
    python3 - "$WAV" <<'PY'
import sys, wave
w = wave.open(sys.argv[1] + '/wake.wav', 'w')
w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
w.writeframes(b'\0' * 4 * 48000); w.close()
PY
    chown "$SUDO_USER" "$WAV/wake.wav"
    asuser pw-play "$WAV/wake.wav" 2>&1 | tail -2
    for i in $(seq 1 40); do
        n=$(cat /sys/bus/soundwire/devices/sdw:*/status 2>/dev/null | grep -c '^Attached$')
        [ "$n" -ge 2 ] && break
        sleep 1
    done
    echo "amplifiers attached: $n of 2 after the wake-up"
    for side in left right; do
        echo "playing $side"
        asuser pw-play "$WAV/$side.wav" 2>&1 | tail -2
        ask "Tone '$side': which speaker played, left, right, both or none?"
    done
fi

sect "mute from the desktop: switches and LEDs follow"
ask "Mute the speakers, then the microphones, from software and watch the F6 and F9 LEDs? (y/N)"
if [ "$REPLY" = y ]; then
    asuser wpctl set-mute @DEFAULT_AUDIO_SINK@ 1; sleep 1
    echo "speakers muted:"; switches; leds; mutes
    ask "Which mute LEDs are lit now: F6, F9, both or none?"
    asuser wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
    asuser wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1; sleep 1
    echo "microphones muted:"; switches; leds; mutes
    ask "Which mute LEDs are lit now: F6, F9, both or none?"
    # The mute switches are UCM user controls; PipeWire must still mute
    # the samples. A muted recording has to be silent.
    echo "recording 3 s while muted (speak now):"
    asuser timeout 3 pw-record --rate 48000 --channels 2 --format s16 "$WAV/muted.wav" 2>&1 | tail -2
    python3 - "$WAV/muted.wav" <<'PY'
import struct, sys, wave
w = wave.open(sys.argv[1])
n, ch = w.getnframes(), w.getnchannels()
s = struct.unpack('<%dh' % (n * ch), w.readframes(n))
peak = max((abs(v) for v in s), default=0)
print('muted recording: %d frames, peak %d -> %s' % (n, peak, 'SILENT, OK' if peak == 0 else 'NOT SILENT: mute does not work'))
PY
    asuser wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0; sleep 1
    echo "both unmuted:"; switches; leds; mutes
fi

sect "mute keys: F6 (speakers) and F9 (microphones)"
ask "Press F6 once, then answer: did GNOME show the speaker-mute icon? (y/N)"
echo "after F6:"; switches; leds; mutes
irq0=$(awk '/hp-omnibook-5-ec/ {s = 0; for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+$/) s += $i; print s}' /proc/interrupts)
ask "Press F9 once, then answer: which icon did GNOME show, speaker mute, microphone mute, both or none?"
irq1=$(awk '/hp-omnibook-5-ec/ {s = 0; for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+$/) s += $i; print s}' /proc/interrupts)
echo "after F9:"; switches; leds; mutes
echo "EC interrupts during F9: ${irq0:-none} -> ${irq1:-none}"
journalctl -k -b --no-pager | grep -i 'omnibook' | tail -5
asuser wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
asuser wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0

sect "kernel log after the tests"
journalctl -k -b --no-pager --since '-10 min' |
    grep -iE 'soundwire|sdw|swr|wsa|lpass|q6apm|ASoC|snd|omnibook|error|fail|Oops' | tail -60
echo "Saved to $OUT"
