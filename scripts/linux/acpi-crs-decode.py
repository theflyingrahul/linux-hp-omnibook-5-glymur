#!/usr/bin/env python3
"""Decode raw ACPI _CRS resource buffers from an iasl disassembly.

HP's DSDT writes most device resources as raw Buffer () byte lists instead
of ASL resource macros, so they cannot be grepped. For every Device whose
_CRS contains such a buffer this prints the decoded descriptors:
  I2cSerialBus / UartSerialBus / SpiSerialBus (address, speed, controller),
  GpioInt / GpioIo (pins, trigger, polarity, pull, controller),
  Memory32Fixed, Extended Interrupt,
plus, for HID-over-I2C devices (_DSM 3cdff6f7-...), the HID descriptor
register returned for function 1.

Usage: acpi-crs-decode.py DSDT.dsl [--device NAME] [--bus \\_SB.I2C5]
The input is private firmware; keep the output in .work/.
"""
import argparse
import re
import struct
import sys

HID_DSM = '3cdff6f7-4267-4555-ad05-b30a3d8938de'


def blocks(src):
    """Yield (name, body) for every Device (XXXX) block."""
    for m in re.finditer(r'Device \((\w{1,4})\)\s*\{', src):
        depth, i = 1, m.end()
        while depth and i < len(src):
            c = src[i]
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
            i += 1
        yield m.group(1), src[m.end():i]


def buffers(text):
    """Byte strings of every Buffer (...) { 0x.., ... } in text."""
    for m in re.finditer(r'Buffer \((0x[0-9A-Fa-f]+|\w+)\)\s*//[^\n]*\n?\s*\{|Buffer \((0x[0-9A-Fa-f]+)\)\s*\{', text):
        start = m.end()
        end = text.find('}', start)
        body = re.sub(r'//[^\n]*', '', text[start:end])
        data = bytes(int(x, 16) for x in re.findall(r'0x([0-9A-Fa-f]{2})\b', body))
        if data:
            yield data


def decode(data):
    out, i = [], 0
    while i < len(data):
        tag = data[i]
        if tag == 0x79:  # End tag
            break
        if tag & 0x80:
            length = struct.unpack_from('<H', data, i + 1)[0]
            body = data[i + 3:i + 3 + length]
            out.append(large(tag, body))
            i += 3 + length
        else:
            length = tag & 0x7
            i += 1 + length
    return [x for x in out if x]


def cstr(b):
    return b.split(b'\0', 1)[0].decode('ascii', 'replace')


def large(tag, b):
    if tag == 0x86:  # Memory32Fixed
        rw, base, size = struct.unpack_from('<BII', b)
        return f'Memory32Fixed base=0x{base:x} size=0x{size:x}'
    if tag == 0x89:  # Extended interrupt
        flags, count = b[0], b[1]
        irqs = struct.unpack_from('<' + 'I' * count, b, 2)
        mode = 'edge' if flags & 2 else 'level'
        pol = 'low' if flags & 4 else 'high'
        return f'Interrupt {mode}/{pol} {",".join(str(x) for x in irqs)}'
    if tag == 0x8C:  # GPIO connection
        rev, ctype, gflags, iflags, pincfg, drive, debounce, ptoff, rsi, rsoff = \
            struct.unpack_from('<BBHHBHHHBH', b)
        vdoff = struct.unpack_from('<H', b, 16)[0]
        base = -3  # offsets are from the descriptor start (tag byte)
        pins = []
        o = ptoff + base
        end = (rsoff + base)
        while o + 1 < end:
            pins.append(struct.unpack_from('<H', b, o)[0])
            o += 2
        src = cstr(b[rsoff + base:])
        pull = {0: 'default', 1: 'up', 2: 'down', 3: 'none'}.get(pincfg, pincfg)
        if ctype == 0:
            mode = 'edge' if iflags & 1 else 'level'
            pol = {0: 'high', 1: 'low', 2: 'both'}[(iflags >> 1) & 3]
            wake = ' wake' if iflags & 0x10 else ''
            return f'GpioInt {mode}/{pol}{wake} pull={pull} pins={pins} {src}'
        io = {0: 'any', 1: 'input', 2: 'output', 3: 'in/out'}[iflags & 3]
        return f'GpioIo {io} pull={pull} drive={drive} pins={pins} {src}'
    if tag == 0x8E:  # Generic serial bus connection
        rev, rsi, stype, gflags, tflags, trev, tlen = struct.unpack_from('<BBBBHBH', b)
        td = b[9:9 + tlen]
        src = cstr(b[9 + tlen:])
        if stype == 1:
            speed, addr = struct.unpack_from('<IH', td)
            return f'I2cSerialBus addr=0x{addr:02x} speed={speed} {src}'
        if stype == 3:
            baud, rx, tx, parity, lines = struct.unpack_from('<IHHBB', td)
            flow = {0: 'none', 1: 'hw', 2: 'xon'}[tflags & 3]
            return f'UartSerialBus baud={baud} flow={flow} rxfifo={rx} txfifo={tx} {src}'
        if stype == 2:
            speed = struct.unpack_from('<I', td)[0]
            return f'SpiSerialBus speed={speed} {src}'
        return f'SerialBus type={stype} {src}'
    return None


def hid_descriptor(body):
    """HID descriptor register for _DSM 3cdff6f7 function 1, if simple."""
    if HID_DSM not in body.lower():
        return None
    m = re.search(r'Arg2 == One\)\)\s*\{\s*Return \((0x[0-9A-Fa-f]+|One|Zero)\)', body)
    if not m:
        m = re.search(r'If \(\(_T_1 == One\)\)\s*\{\s*Return \((0x[0-9A-Fa-f]+|One|Zero)\)', body)
    if not m:
        return '?'
    v = m.group(1)
    return {'One': '0x1', 'Zero': '0x0'}.get(v, v)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('dsl')
    ap.add_argument('--device')
    ap.add_argument('--bus', help='only devices on this serial bus controller')
    args = ap.parse_args()
    src = open(args.dsl, encoding='utf-8', errors='replace').read()
    for name, body in blocks(src):
        if args.device and name != args.device:
            continue
        crs = re.search(r'Method \(_CRS[^{]*\{(.*?)Return \(', body, re.S) or \
            re.search(r'Name \(_CRS, ResourceTemplate', body)
        crs_text = crs.group(1) if crs and crs.re.groups else ''
        res = []
        for data in buffers(crs_text):
            try:
                res += decode(data)
            except (struct.error, KeyError, IndexError):
                res.append('(undecodable buffer)')
        if not res:
            continue
        if args.bus and not any(args.bus in r for r in res):
            continue
        hid = re.search(r'Name \(_HID, ("[^"]+"|[\w ]+)', body)
        uid = re.search(r'Name \(_UID, (0x[0-9A-Fa-f]+|One|Zero)', body)
        desc = hid_descriptor(body)
        head = f'{name} {hid.group(1) if hid else ""}'
        if uid:
            head += f' uid={uid.group(1)}'
        if desc:
            head += f' hid-descriptor={desc}'
        print(head)
        for r in res:
            print('    ' + r)


if __name__ == '__main__':
    main()
