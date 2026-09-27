#!/usr/bin/env python3
"""Decode Qualcomm Windows PEP resource files (BSRC_*.bin, magic "AeoB").

HP's Qualcomm driver packs ship per-driver power recipes as BSRC_*.bin files
(for example qcuart8480/BSRC_UART_4Wire_1.bin, qcbluetooth8480/BSRC_BT.bin).
Windows' PEP applies them the same way as the \\_SB.PEP0 packages in the
DSDT: per device, component and F-/P-state, a list of CLOCK, BUSARB,
TLMMGPIO, PMICVREGVOTE ... actions.

Encoding (little-endian): "AeoB", u32 total size, u32 element count, then
elements of u16 type + u16 length:
  type 0: integer, length 8 (u64)
  type 1: NUL-terminated string
  type 3: package; its length covers the nested elements
Usage:
  parse-bsrc.py FILE [--device \\_SB.UR15]   print the tree (or one device)
"""
import argparse
import struct
import sys


def parse(data, off, end):
    items = []
    while off < end:
        typ, length = struct.unpack_from('<HH', data, off)
        off += 4
        body = data[off:off + length]
        if len(body) != length:
            raise ValueError(f'truncated element at 0x{off - 4:x}')
        if typ == 0:
            items.append(struct.unpack('<Q', body.ljust(8, b'\0')[:8])[0])
        elif typ == 1:
            items.append(body.split(b'\0', 1)[0].decode('ascii', 'replace'))
        elif typ == 3:
            items.append(parse(data, off, off + length))
        else:
            raise ValueError(f'unknown element type {typ} at 0x{off - 4:x}')
        off += length
    return items


def load(path):
    data = open(path, 'rb').read()
    if data[:4] != b'AeoB':
        raise ValueError(f'{path}: not an AeoB resource file')
    size = struct.unpack_from('<I', data, 4)[0]
    if size != len(data):
        raise ValueError(f'{path}: header size {size} != file size {len(data)}')
    return parse(data, 12, len(data))


def show(node, depth=0, out=sys.stdout):
    if isinstance(node, list):
        # Print leaf-only packages on one line: they are single actions.
        if all(not isinstance(x, list) for x in node):
            out.write('  ' * depth + '  '.join(fmt(x) for x in node) + '\n')
        else:
            for x in node:
                show(x, depth + 1 if isinstance(x, list) else depth, out)
    else:
        out.write('  ' * depth + fmt(node) + '\n')


def fmt(x):
    return f'{x}' if isinstance(x, str) else (f'0x{x:x}' if x > 9 else str(x))


def devices(tree):
    """Yield (name, package) for every DEVICE package."""
    for node in tree:
        if isinstance(node, list) and len(node) >= 2 and node[0] == 'DEVICE':
            yield node[1], node
        elif isinstance(node, list):
            yield from devices(node)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('file')
    ap.add_argument('--device', help='only this device, e.g. \\_SB.UR15')
    ap.add_argument('--list', action='store_true', help='list device names')
    args = ap.parse_args()
    tree = load(args.file)
    if args.list:
        for name, _ in devices(tree):
            print(name)
        return
    if args.device:
        found = [pkg for name, pkg in devices(tree) if name == args.device]
        if not found:
            sys.exit(f'{args.device} not in {args.file}')
        for pkg in found:
            show(pkg)
        return
    show(tree)


if __name__ == '__main__':
    main()
