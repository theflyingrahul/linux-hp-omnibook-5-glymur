"""Fix the HP Glymur platform _OSC so Linux can negotiate LPI (CPU idle).

Usage: glymur-dsdt-osc-fix.py <DSDT.dat> <bios-version> <out-dir>

\\_SB._OSC starts with CreateDWordField (Arg3, 0x08, CDW3), but the
platform-wide _OSC buffer Linux passes has two DWORDs. The method aborts with
AE_AML_BUFFER_LIMIT before it answers, so Linux never confirms _LPI support
and registers no cpuidle driver. Only the USB4 branch uses CDW3. This moves
that one 8-byte CreateDWordField into the USB4 If body, keeping the method's
size, bumps the OEM revision and fixes the checksum so that
CONFIG_ACPI_TABLE_UPGRADE accepts the table. It writes dsdt.aml, an
uncompressed early-initrd cpio (kernel/firmware/acpi/dsdt.aml), a manifest,
and a GRUB entry that loads the cpio only when SMBIOS reports the BIOS
version the table came from.

The override replaces the whole DSDT. The kernel only checks the table
signature, OEM ID, table ID and a higher OEM revision, and HP ships revision
1, so after a BIOS update that keeps revision 1 a stale override would still
replace the new DSDT. The GRUB gate prevents that. This is a stopgap until HP
fixes the AML or Linux works around it; do not carry it into an installed
system.

The input and output are HP firmware tables: keep both private (.work/ or the
installer USB), never in Git.
"""
import hashlib
import os
import re
import struct
import sys

src_path, bios_version, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
assert re.fullmatch(r'[A-Za-z0-9.]+', bios_version), 'unexpected BIOS version string'
dsdt = bytearray(open(src_path, 'rb').read())
src_sha256 = hashlib.sha256(dsdt).hexdigest()
assert dsdt[:4] == b'DSDT' and struct.unpack_from('<I', dsdt, 4)[0] == len(dsdt), 'not a DSDT'
assert sum(dsdt) % 256 == 0, 'input checksum is wrong'
assert dsdt[10:16] == b'HPQOEM' and dsdt[16:24] == b'8F47    ', 'not the HP 8F47 DSDT'

CREATE_1_2 = (bytes([0x8A, 0x6B, 0x00]) + b'CDW1' +
              bytes([0x8A, 0x6B, 0x0A, 0x04]) + b'CDW2')
CREATE_3 = bytes([0x8A, 0x6B, 0x0A, 0x08]) + b'CDW3'
USB4_UUID = bytes.fromhex('3ad1a023ab266c489c5f0ffa525a575a')
# If (LEqual (Arg0, Buffer (0x10) { USB4 UUID }))
PREDICATE = bytes([0x93, 0x68, 0x11, 0x13, 0x0A, 0x10]) + USB4_UUID

target = CREATE_1_2 + CREATE_3 + bytes([0xA0])
offs = [i for i in range(len(dsdt)) if dsdt.startswith(target, i) and
        dsdt.startswith(PREDICATE, i + len(target) + 2)]
assert len(offs) == 1, f'expected one platform _OSC, found {len(offs)}'
start = offs[0]
if_op = start + len(CREATE_1_2) + len(CREATE_3)


def pkglen(b0, b1):
    # Two-byte PkgLength: lead byte 01xxnnnn, then the next byte.
    assert b0 >> 6 == 1, 'USB4 If PkgLength is not two bytes'
    return (b0 & 0x0F) | (b1 << 4)


old_len = pkglen(dsdt[if_op + 1], dsdt[if_op + 2])
new_len = old_len + len(CREATE_3)
assert 64 <= new_len <= 0xFFF, 'new PkgLength does not fit two bytes'
body = if_op + 3 + len(PREDICATE)
tail = bytes(dsdt[body:if_op + 1 + old_len])

patched = (CREATE_1_2 + bytes([0xA0, 0x40 | (new_len & 0x0F), new_len >> 4]) +
           PREDICATE + CREATE_3 + tail)
region_end = if_op + 1 + old_len
assert len(patched) == region_end - start, 'patched region changed size'
dsdt[start:region_end] = patched

oem_rev = struct.unpack_from('<I', dsdt, 24)[0]
struct.pack_into('<I', dsdt, 24, oem_rev + 1)
dsdt[9] = 0
dsdt[9] = (-sum(dsdt)) % 256
assert sum(dsdt) % 256 == 0

os.makedirs(os.path.join(out_dir, 'kernel/firmware/acpi'), exist_ok=True)
aml = os.path.join(out_dir, 'kernel/firmware/acpi/dsdt.aml')
open(aml, 'wb').write(dsdt)
def newc_cpio(entries):
    """Minimal uncompressed newc archive (what the kernel's early initrd
    parser reads), for hosts without cpio(1). entries: (name, mode, data)."""
    out = bytearray()
    for ino, (name, mode, data) in enumerate(entries + [('TRAILER!!!', 0, b'')], 1):
        raw = name.encode() + b'\0'
        fields = [ino if name != 'TRAILER!!!' else 0, mode, 0, 0,
                  2 if mode & 0o040000 else 1, 0, len(data), 0, 0, 0, 0, len(raw), 0]
        out += b'070701' + b''.join(b'%08X' % v for v in fields) + raw
        out += b'\0' * (-len(out) % 4) + data
        out += b'\0' * (-len(out) % 4)
    return bytes(out + b'\0' * (-len(out) % 512))


cpio = os.path.join(out_dir, 'acpi-override.cpio')
with open(cpio, 'wb') as f:
    f.write(newc_cpio([('kernel', 0o040755, b''),
                       ('kernel/firmware', 0o040755, b''),
                       ('kernel/firmware/acpi', 0o040755, b''),
                       ('kernel/firmware/acpi/dsdt.aml', 0o100644, bytes(dsdt))]))
with open(os.path.join(out_dir, 'MANIFEST'), 'w') as f:
    f.write(f'bios_version={bios_version}\n'
            f'source_dsdt_sha256={src_sha256}\n'
            f'patched_dsdt_sha256={hashlib.sha256(dsdt).hexdigest()}\n'
            f'patch_offset=0x{start:x}\n'
            f'oem_revision={oem_rev:#x}->{oem_rev + 1:#x}\n')
# GRUB: smbios type 0, string at offset 5 is the BIOS version.
with open(os.path.join(out_dir, 'grub-entry.cfg'), 'w') as f:
    f.write(f"""menuentry 'Glymur workstation + _OSC fix (CPU idle, BIOS {bios_version} only)' {{
    set gfxpayload=keep
    smbios --type 0 --get-string 5 --set glymur_bios
    linux /casper/vmlinuz persistent noprompt $cmdline glymur.workstation=1 systemd.run=/cdrom/glymur-tools/acpi-input/glymur-live-desktop-setup.sh systemd.run_success_action=none systemd.run_failure_action=none --- console=tty0 loglevel=4
    if [ "$glymur_bios" = "{bios_version}" ]; then
        initrd /glymur-tools/acpi-override/acpi-override.cpio /casper/initrd
    else
        echo "BIOS $glymur_bios is not {bios_version}: booting without the DSDT override"
        sleep 5
        initrd /casper/initrd
    fi
}}
""")
print(f'patched \\_SB._OSC at 0x{start:x}; OEM revision {oem_rev:#x} -> {oem_rev + 1:#x}')
print(aml)
print(cpio)
