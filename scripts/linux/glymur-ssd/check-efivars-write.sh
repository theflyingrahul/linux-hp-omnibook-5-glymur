#!/usr/bin/env bash
set -u

# One EFI variable write through QSEECOM (kernel -20 on; writes allowed by
# the owner on 2026-11-09). See README.md.
#   sudo bash check-efivars-write.sh            write the test variable
#   sudo bash check-efivars-write.sh --verify   after a reboot: check it, delete it
#   sudo bash check-efivars-write.sh --delete   delete a test variable left behind
# The variable is GlymurWriteTest under this project's own GUID, 32 bytes,
# non-volatile. Nothing else is written. Run dump-efivars.sh first if no
# baseline exists yet.

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
V=/sys/firmware/efi/efivars
NAME=GlymurWriteTest-ea1cbfcf-dfb4-4709-af84-abeda813833b
F="$V/$NAME"
STATE=/var/lib/glymur/efivar-write-test
OUT="/var/log/glymur/efivar-write-$(date +%Y%m%dT%H%M%S).txt"
mkdir -p /var/log/glymur /var/lib/glymur
exec > >(tee "$OUT") 2>&1

echo "kernel: $(uname -r)"
opts=$(findmnt -n -o OPTIONS "$V")
echo "efivarfs: $opts"
REMOUNTED=0
case ",$opts," in
    *,ro,*) mount -o remount,rw "$V" && REMOUNTED=1 && echo 'remounted read-write for this test' ;;
esac
count=$(ls "$V" | wc -l)
echo "$count variables visible"
t0=$(date +%s)

payload() { tail -c +5 "$1" | od -An -tx1 -v | tr -d ' \n'; }

# efivarfs deletes with attributes 0, which Qualcomm's TrustZone variable
# service refuses (EINVAL on -21). Writing only the 4-byte attribute header
# is SetVariable with the variable's own attributes and no data: a delete.
delete_var() {
    local hdr
    chattr -i "$F" 2>/dev/null
    rm -f "$F" 2>&1 | sed 's/^/rm: /'
    if [ -e "$F" ]; then
        hdr=$(mktemp)
        head -c 4 "$F" > "$hdr"
        echo "attribute header: $(od -An -tx1 "$hdr" | tr -d '\n')"
        cat "$hdr" > "$F" 2>&1 | sed 's/^/write: /'
        rm -f "$hdr"
    fi
    [ ! -e "$F" ] && echo 'deleted' || echo 'FAIL: delete'
}

if [ "${1:-}" = --delete ]; then
    [ -e "$F" ] || { echo "$NAME is not there"; exit 0; }
    delete_var
    rm -f "$STATE"
elif [ "${1:-}" = --verify ]; then
    [ -f "$STATE" ] || { echo "no $STATE: the write step did not run"; exit 1; }
    want=$(cat "$STATE")
    if [ ! -e "$F" ]; then
        echo 'FAIL: the variable did not survive the reboot'
    else
        got=$(payload "$F")
        attr=$(od -An -tx4 -N4 "$F" | tr -d ' ')
        echo "attributes $attr, data $got"
        [ "$got" = "$want" ] && echo 'PASS: survived the reboot unchanged' || echo "FAIL: expected $want"
        delete_var
        rm -f "$STATE"
    fi
else
    [ -e "$F" ] && { echo "$NAME exists already; run --verify"; exit 1; }
    # attributes NV|BS|RT (0x7), then 32 bytes of data
    data=$(printf 'glymur %s' "$(date -u +%Y%m%dT%H%M%SZ)" | head -c 32)
    data=$(printf '%-32s' "$data")
    if printf '\x07\x00\x00\x00%s' "$data" > "$F"; then
        sync
        got=$(payload "$F")
        want=$(printf '%s' "$data" | od -An -tx1 -v | tr -d ' \n')
        [ "$got" = "$want" ] && echo "PASS: written and read back ($data)" || echo "FAIL: read back $got"
        printf '%s' "$want" > "$STATE"
        echo "Reboot, then run: sudo bash ~/check-efivars-write.sh --verify"
    else
        echo 'FAIL: the write was refused'
    fi
fi
echo "$(ls "$V" | wc -l) variables visible now"
journalctl -k --no-pager --since "@$t0" | grep -iE 'efi|qseecom|uefisecapp|scm' | tail
[ "$REMOUNTED" = 1 ] && mount -o remount,ro "$V" && echo 'read-only again'
echo "log: $OUT"
