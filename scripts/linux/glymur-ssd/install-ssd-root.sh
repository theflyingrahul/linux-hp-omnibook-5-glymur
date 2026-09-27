#!/usr/bin/env bash
set -euo pipefail

# Install an Ubuntu 26.04 root filesystem onto the empty internal-SSD
# partition, for booting the Glymur qcom-next kernel from the USB's GRUB.
#
# Run as root from the "Glymur live desktop (RAM live)" session:
#   sudo bash /cdrom/glymur-tools/ssd/install-ssd-root.sh <partition-guid>
#
# Safety:
# - touches only the partition whose unique GPT GUID is given, and only if it
#   has the Linux filesystem type, is 150-300 GB, is on the internal NVMe,
#   is not mounted and carries no filesystem (or is our own glymur-root with
#   --reuse), and the operator types INSTALL;
# - never mounts or writes the SSD's EFI partition, never installs a boot
#   loader, and diverts grub-install in the target so package upgrades
#   cannot touch the SSD's EFI partition either;
# - leaves Windows (BitLocker C:) and Recovery untouched.
#
# The target is built the way Ubuntu's installer (curtin) builds the full
# "Ubuntu Desktop" source: the name prefixes of minimal.standard.<lang>
# (minimal, minimal.standard, minimal.standard.<lang>) are stacked with
# overlayfs and copied. Language layers are deltas that delete the other
# languages; minimal.<lang> belongs to the minimized source, not this one.
# The live layer is excluded.

usage() { printf 'usage: %s <partition-guid> [--reuse] [--lang en]\n' "$0" >&2; exit 2; }
[ $# -ge 1 ] || usage
GUID="$(printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -d '{}')"
shift
REUSE=0
LANG_LAYER=en
while [ $# -gt 0 ]; do
    case "$1" in
        --reuse) REUSE=1; shift ;;
        --lang) LANG_LAYER="$2"; shift 2 ;;
        *) usage ;;
    esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASPER=/cdrom/casper
KERNEL_TAR="$(ls "$HERE"/glymur-kernel-*.tar.gz 2>/dev/null | head -n 1 || true)"
FW_SRC=/cdrom/glymur-tools/firmware/ath12k/QCC2072/hw1.0/firmware-2.bin
BOARD_SRC=/cdrom/glymur-tools/acpi-input/wifi/board-2.bin
BUNDLE=/cdrom/glymur-workstation/workstation-bundle.tar.gz
LINUX_FS_TYPE=0fc63daf-8483-4772-8e79-3d69d8477de4
TARGET=/mnt/glymur-root
LAYERS=/run/glymur-layers
LOG=/run/glymur-ssd-install.log

say() { printf '\n==> %s\n' "$*" | tee -a "$LOG"; }
die() { printf '\nERROR: %s\n' "$*" | tee -a "$LOG" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die 'run with sudo'
[ -d "$CASPER" ] || die "$CASPER not found; run from the Ubuntu live session"
[ -n "$KERNEL_TAR" ] || die "no glymur-kernel-*.tar.gz next to this script"
(cd "$HERE" && sha256sum --quiet -c SHA256SUMS) || die 'kit checksum mismatch'
[ -f "$FW_SRC" ] && [ -f "$BOARD_SRC" ] || die "Wi-Fi firmware or board file missing under /cdrom/glymur-tools"
[ -f "$HERE/glymur-boot-report.sh" ] || die "glymur-boot-report.sh missing next to this script"
command -v mkfs.ext4 >/dev/null || die 'mkfs.ext4 not found'

# ---- identify the target partition ------------------------------------------
DEV="$(blkid -t PARTUUID="$GUID" -o device 2>/dev/null | head -n 1 || true)"
[ -n "$DEV" ] && [ -b "$DEV" ] || die "no partition with GUID $GUID"
DISK="/dev/$(lsblk -no PKNAME "$DEV")"
case "$DISK" in /dev/nvme*) ;; *) die "$DEV is not on the internal NVMe ($DISK)" ;; esac
PTYPE="$(lsblk -no PARTTYPE "$DEV" | tr 'A-Z' 'a-z')"
[ "$PTYPE" = "$LINUX_FS_TYPE" ] || die "$DEV partition type is $PTYPE, not Linux filesystem"
SIZE_GB=$(( $(blockdev --getsize64 "$DEV") / 1000000000 ))
[ "$SIZE_GB" -ge 150 ] && [ "$SIZE_GB" -le 300 ] || die "$DEV is ${SIZE_GB} GB; expected 150-300"
if findmnt -rn -S "$DEV" >/dev/null; then die "$DEV is mounted"; fi
FSTYPE="$(blkid -p -s TYPE -o value "$DEV" 2>/dev/null || true)"
LABEL="$(blkid -p -s LABEL -o value "$DEV" 2>/dev/null || true)"
if [ -n "$FSTYPE" ]; then
    if [ "$REUSE" -eq 1 ] && [ "$FSTYPE" = ext4 ] && [ "$LABEL" = glymur-root ]; then
        :
    else
        die "$DEV already has a $FSTYPE filesystem (label '$LABEL'); refusing"
    fi
fi

say "Target: $DEV on $DISK, ${SIZE_GB} GB, GUID $GUID, existing fs: ${FSTYPE:-none}"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,PARTTYPENAME "$DISK" | tee -a "$LOG"
printf '\nThis will %s %s and install Ubuntu onto it.\nType INSTALL to continue: ' \
    "$([ "$REUSE" -eq 1 ] && echo 'reuse' || echo 'FORMAT')" "$DEV"
read -r answer
[ "$answer" = INSTALL ] || die 'not confirmed'

# ---- filesystem and base system ---------------------------------------------
if [ -z "$FSTYPE" ]; then
    say "Creating ext4 (label glymur-root) on $DEV"
    mkfs.ext4 -q -L glymur-root -m 1 "$DEV"
fi
mkdir -p "$TARGET"
mount "$DEV" "$TARGET"
trap 'umount -R "$TARGET" 2>/dev/null || true; umount -R "$LAYERS"/* 2>/dev/null || true' EXIT

say "Stacking squashfs layers (minimal, minimal.standard, minimal.standard.$LANG_LAYER)"
mkdir -p "$LAYERS"
lower=""
for layer in minimal minimal.standard "minimal.standard.$LANG_LAYER"; do
    [ -f "$CASPER/$layer.squashfs" ] || die "missing $CASPER/$layer.squashfs"
    mkdir -p "$LAYERS/$layer"
    mount -o loop,ro "$CASPER/$layer.squashfs" "$LAYERS/$layer"
    lower="$LAYERS/$layer${lower:+:$lower}"
done
mkdir -p "$LAYERS/merged"
mount -t overlay overlay -o "ro,lowerdir=$lower" "$LAYERS/merged"
say "Copying the system (about 8 GB)"
if command -v rsync >/dev/null; then
    rsync -aHAXx --numeric-ids --info=progress2 "$LAYERS/merged/" "$TARGET/"
else
    cp -a "$LAYERS/merged/." "$TARGET/"
fi
umount "$LAYERS/merged"
for layer in "$LAYERS"/minimal*; do umount "$layer"; done

# ---- configure the target ---------------------------------------------------
say 'Configuring fstab, hostname, machine-id'
FS_UUID="$(blkid -p -s UUID -o value "$DEV")"
[ -n "$FS_UUID" ] || die "could not read the filesystem UUID of $DEV"
cat >"$TARGET/etc/fstab" <<EOF
# Glymur SSD root. The SSD's EFI partition is intentionally not mounted.
UUID=$FS_UUID / ext4 errors=remount-ro 0 1
EOF
printf 'glymur\n' >"$TARGET/etc/hostname"
printf '127.0.0.1 localhost\n127.0.1.1 glymur\n::1 localhost ip6-localhost ip6-loopback\n' \
    >"$TARGET/etc/hosts"
# A real machine-id, so systemd does not treat the first boot as unconfigured
# and stop at interactive firstboot prompts.
tr -d '-' </proc/sys/kernel/random/uuid >"$TARGET/etc/machine-id"
# Keep the live session's locale, keyboard and time zone.
for f in default/locale default/keyboard timezone; do
    [ -f "/etc/$f" ] && cp "/etc/$f" "$TARGET/etc/$f"
done
[ -L /etc/localtime ] && ln -sfn "$(readlink /etc/localtime)" "$TARGET/etc/localtime"
# What Ubuntu's desktop installer writes: NetworkManager manages everything.
mkdir -p "$TARGET/etc/netplan"
printf 'network:\n  version: 2\n  renderer: NetworkManager\n' \
    >"$TARGET/etc/netplan/01-network-manager-all.yaml"
chmod 600 "$TARGET/etc/netplan/01-network-manager-all.yaml"
# Persistent journal, so a failed boot can be read from the live session.
mkdir -p "$TARGET/var/log/journal"
# No RTC under ACPI: \_SB.PRTC (ACPI000E) reads the time through PMIC GLink,
# which is not up, and UEFI GetTime is unavailable. The clock starts wrong
# until chrony syncs, so e2fsck must not treat superblock times "in the
# future" as errors (the Debian setting for systems without an RTC).
printf '[options]\n\tbroken_system_clock = 1\n' >"$TARGET/etc/e2fsck.conf"

say 'Guarding the SSD EFI partition from package scripts'
chroot "$TARGET" dpkg-divert --local --rename --add /usr/sbin/grub-install >/dev/null 2>&1 || true
cat >"$TARGET/usr/sbin/grub-install" <<'EOF'
#!/bin/sh
echo "grub-install is disabled on this Glymur install: the boot loader lives on the USB stick." >&2
exit 0
EOF
chmod 755 "$TARGET/usr/sbin/grub-install"

say "Installing the kernel modules and Wi-Fi firmware"
# Ubuntu is merged-/usr (/lib -> usr/lib). Extracting ./lib/... straight into
# the target would let tar replace that symlink with a directory, so unpack
# aside and copy into usr/lib.
LIBDIR="$TARGET/usr/lib"
[ -d "$LIBDIR" ] && [ -L "$TARGET/lib" ] || die 'target is not merged-/usr; refusing to guess'
# Unpack on the target filesystem itself: the modules are too large for the
# live session's /run tmpfs, and a same-filesystem mv is instant.
KSTAGE="$TARGET/var/tmp/glymur-kernel"
rm -rf "$KSTAGE" && mkdir -p "$KSTAGE"
tar -xzf "$KERNEL_TAR" -C "$KSTAGE"
KREL="$(ls "$KSTAGE/lib/modules" | grep -- '-glymur$' | head -n 1 || true)"
[ -n "$KREL" ] || die 'kernel modules missing from the kernel tarball'
rm -f "$KSTAGE/lib/modules/$KREL/build" "$KSTAGE/lib/modules/$KREL/source"
rm -rf "$LIBDIR/modules/$KREL"
mv "$KSTAGE/lib/modules/$KREL" "$LIBDIR/modules/"
mkdir -p "$TARGET/boot"
cp "$KSTAGE/Image" "$TARGET/boot/vmlinuz-$KREL"
cp "$KSTAGE/.config" "$TARGET/boot/config-$KREL"
cp "$KSTAGE/System.map" "$TARGET/boot/System.map-$KREL"
rm -rf "$KSTAGE"
chroot "$TARGET" depmod -a "$KREL"
mkdir -p "$LIBDIR/firmware/updates/ath12k/QCC2072/hw1.0"
cp "$FW_SRC" "$BOARD_SRC" "$LIBDIR/firmware/updates/ath12k/QCC2072/hw1.0/"

say 'Masking suspend and hibernate (untested on this kernel)'
chroot "$TARGET" systemctl mask sleep.target suspend.target hibernate.target \
    hybrid-sleep.target suspend-then-hibernate.target >/dev/null

# The owner's rules forbid firmware flashing and boot-loader changes from
# this system: fwupd stays off, and boot-loader packages are held so an
# upgrade cannot try to reach the SSD's EFI partition.
say 'Disabling fwupd and holding boot-loader packages'
chroot "$TARGET" systemctl mask fwupd.service fwupd-refresh.timer \
    fwupd-refresh.service >/dev/null 2>&1 || true
chroot "$TARGET" dpkg-query -W -f '${Package}\n' 'grub*' 'shim*' 2>/dev/null |
    xargs -r chroot "$TARGET" apt-mark hold >>"$LOG" 2>&1 || true

# Evidence without a login: if input fails on a boot, the live USB can still
# read /var/log/glymur/ from the SSD.
say 'Installing the per-boot bring-up report (/var/log/glymur)'
install -m 755 "$HERE/glymur-boot-report.sh" "$TARGET/usr/local/sbin/glymur-boot-report"
cat >"$TARGET/etc/systemd/system/glymur-boot-report.service" <<'EOF'
[Unit]
Description=Glymur bring-up report (/var/log/glymur)
After=multi-user.target

[Service]
Type=exec
ExecStart=/usr/local/sbin/glymur-boot-report
Nice=10

[Install]
WantedBy=multi-user.target
EOF
chroot "$TARGET" systemctl enable glymur-boot-report.service >/dev/null 2>&1 ||
    say 'Could not enable glymur-boot-report.service; continuing'

# ---- user account (interactive) ---------------------------------------------
say 'Create your login account for the installed system'
printf 'Username (lowercase): '
read -r NEWUSER
case "$NEWUSER" in ''|*[!a-z0-9_-]*) die 'invalid username' ;; esac
mount --bind /dev "$TARGET/dev"
mount -t proc proc "$TARGET/proc"
mount -t sysfs sys "$TARGET/sys"
# The desktop image has no git; the kit carries git, git-man and
# liberror-perl from the Ubuntu 26.04 arm64 archive (checked by SHA256SUMS).
if compgen -G "$HERE/debs/*.deb" >/dev/null; then
    say 'Installing git from the kit (offline)'
    mkdir -p "$TARGET/var/tmp/glymur-debs"
    cp "$HERE"/debs/*.deb "$TARGET/var/tmp/glymur-debs/"
    chroot "$TARGET" sh -c 'dpkg -i /var/tmp/glymur-debs/*.deb' >>"$LOG" 2>&1 ||
        say 'git install failed; install it later with: sudo apt install git'
    rm -rf "$TARGET/var/tmp/glymur-debs"
fi
chroot "$TARGET" adduser --comment '' "$NEWUSER"
chroot "$TARGET" usermod -aG sudo,adm,netdev "$NEWUSER" 2>/dev/null ||
    chroot "$TARGET" usermod -aG sudo,adm "$NEWUSER"
HOMEDIR="$TARGET/home/$NEWUSER"

say 'Copying the repository and evidence into the new home'
if [ -f "$BUNDLE" ] &&
    (cd /cdrom/glymur-workstation && sha256sum --quiet -c SHA256SUMS); then
    tar -xzf "$BUNDLE" -C "$HOMEDIR"
    repo="/home/$NEWUSER/linux-hp-omnibook-5-glymur"
    chroot "$TARGET" chown -R "$NEWUSER:$NEWUSER" "/home/$NEWUSER"
    chroot "$TARGET" runuser -u "$NEWUSER" -- git -C "$repo" config core.filemode false || true
else
    say 'Workstation bundle not found or failed its checksum; skipped'
fi

# Results the Linux live sessions left in the persistent home (casper-rw on
# the installer USB: boot logs, fan and lid tests). Mounted read-only with
# noload, so the unreplayed journal of a stick that lost power is not written;
# large trees (kernel checkouts, caches) are skipped. Private, so into .work.
import_live_home() {
    local part mnt=/run/glymur-persist src dest
    # blkid exits 2 when nothing matches; under pipefail that must not abort.
    part="$(blkid -t LABEL=casper-rw -o device 2>/dev/null | head -n 1 || true)"
    [ -n "$part" ] ||
        part="$(blkid -t LABEL=writable -o device 2>/dev/null | head -n 1 || true)"
    if [ -z "$part" ]; then
        say 'No casper-rw persistence partition found; nothing imported'
        return 0
    fi
    local own_mount=0 existing
    # findmnt exits 1 for an unmounted device (the RAM-live case).
    existing="$(findmnt -rn -S "$part" -o TARGET | head -n 1 || true)"
    if [ -n "$existing" ]; then
        # Automounted by the desktop: read from there, leave it mounted.
        mnt="$existing"
    else
        mkdir -p "$mnt"
        if ! mount -o ro,noload "$part" "$mnt"; then
            say "Could not mount $part read-only; nothing imported"
            return 0
        fi
        own_mount=1
    fi
    for src in "$mnt"/upper/home/*; do
        [ -d "$src" ] || continue
        dest="$HOMEDIR/linux-hp-omnibook-5-glymur/.work/live-persistence-home-$(basename "$src")"
        say "Importing $src (read-only) into ${dest#"$TARGET"}"
        mkdir -p "$dest"
        # Never import credentials: logins, SSH/GPG keys,
        # keyrings, browser and app configuration.
        rsync -a --max-size=64M \
            --exclude='/.ssh/' \
            --exclude='/.gnupg/' --exclude='/.pki/' --exclude='/.local/share/keyrings/' \
            --exclude='/.config/' --exclude='/.mozilla/' --exclude='/snap/' \
            --exclude='/.cache/' --exclude='/.local/share/Trash/' --exclude='/.local/bin/' \
            --exclude='linux-qcom-next*/' \
            "$src/" "$dest/" >>"$LOG" 2>&1 ||
            say "Import from $src finished with rsync status $?"
    done
    [ "$own_mount" -eq 0 ] || umount "$mnt"
    chroot "$TARGET" chown -R "$NEWUSER:$NEWUSER" "/home/$NEWUSER"
}
if [ -d "$HOMEDIR/linux-hp-omnibook-5-glymur" ]; then
    import_live_home
fi

umount "$TARGET/sys" "$TARGET/proc" "$TARGET/dev"
sync
say "Done. Kernel $KREL; filesystem UUID $FS_UUID; partition GUID $GUID."
cat <<EOF | tee -a "$LOG"

Next:
  1. Reboot and choose "Ubuntu on SSD: qcom-next $KREL".
     If it misbehaves, photograph the screen and try the "(no DSDT override)" entry.
  2. After logging in:
       POWER_SOURCE=battery bash ~/linux-hp-omnibook-5-glymur/scripts/linux/fan-thermal-profile.sh
  A bring-up report is written 60 s after every boot to /var/log/glymur/,
  readable from this live USB even if login is impossible.
EOF
cp "$LOG" "$TARGET/root/glymur-ssd-install.log" 2>/dev/null || true
