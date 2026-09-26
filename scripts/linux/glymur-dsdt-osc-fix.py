"""Fix the HP Glymur platform _OSC so Linux can negotiate LPI (CPU idle).

Usage: glymur-dsdt-osc-fix.py <DSDT.dat> <out-dir>

\\_SB._OSC starts with CreateDWordField (Arg3, 0x08, CDW3), but the
platform-wide _OSC buffer Linux passes has two DWORDs. The method aborts with
AE_AML_BUFFER_LIMIT before it answers, so Linux never confirms _LPI support
and registers no cpuidle driver. Only the USB4 branch uses CDW3. This moves
that one 8-byte CreateDWordField into the USB4 If body, keeping the method's
size, bumps the OEM revision and fixes the checksum so that
CONFIG_ACPI_TABLE_UPGRADE accepts the table. It writes dsdt.aml and an
uncompressed early-initrd cpio (kernel/firmware/acpi/dsdt.aml).

The input and output are HP firmware tables: keep both private (.work/ or the
installer USB), never in Git.
"""
import os
import struct
import subprocess
import sys

src_path, out_dir = sys.argv[1], sys.argv[2]
dsdt = bytearray(open(src_path, 'rb').read())
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
cpio = os.path.join(out_dir, 'acpi-override.cpio')
with open(cpio, 'wb') as f:
    subprocess.run(['cpio', '-H', 'newc', '-o', '--quiet', '-R', '0:0'],
                   input=b'kernel\nkernel/firmware\nkernel/firmware/acpi\n'
                         b'kernel/firmware/acpi/dsdt.aml\n',
                   cwd=out_dir, stdout=f, check=True)
print(f'patched \\_SB._OSC at 0x{start:x}; OEM revision {oem_rev:#x} -> {oem_rev + 1:#x}')
print(aml)
print(cpio)
