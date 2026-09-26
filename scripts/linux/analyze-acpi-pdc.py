#!/usr/bin/env python3
"""Read-only PDC GPIO pin mapping check for an iasl-disassembled DSDT."""

import argparse
import re
import sys
from pathlib import Path


def mask_comments_and_strings(text):
    pattern = re.compile(r'"(?:\\.|[^"\\])*"|/\*.*?\*/|//[^\n]*', re.S)
    return pattern.sub(lambda match: re.sub(r'[^\n]', ' ', match.group()), text)


def named_block(text, kind, name):
    masked = mask_comments_and_strings(text)
    match = re.search(rf'\b{kind}\s*\(\s*{name}\s*[,)]', masked)
    if not match:
        raise ValueError(f'{kind} ({name}) not found')
    opening = masked.find('{', match.end())
    if opening < 0:
        raise ValueError(f'{kind} ({name}) has no body')
    depth = 0
    for index in range(opening, len(masked)):
        if masked[index] == '{':
            depth += 1
        elif masked[index] == '}':
            depth -= 1
            if depth == 0:
                return text[opening + 1:index]
    raise ValueError(f'{kind} ({name}) has an unclosed body')


def resource_bytes(gio):
    crs = named_block(gio, 'Method', '_CRS')
    length_match = re.search(r'\bName\s*\(\s*RBUF\s*,\s*Buffer\s*\(\s*'
                             r'(0x[0-9A-Fa-f]+|\d+)\s*\)',
                             mask_comments_and_strings(crs))
    if not length_match:
        raise ValueError('GIO0._CRS RBUF length not found')
    expected_length = int(length_match.group(1), 0)
    rbuf = named_block(crs, 'Name', 'RBUF')
    data = []
    for line in rbuf.splitlines():
        match = re.search(r'/\*\s*([0-9A-Fa-f]{4})\s*\*/(.*)', line)
        if match:
            if int(match.group(1), 16) != len(data):
                raise ValueError('non-contiguous GIO0._CRS RBUF byte offsets')
            data.extend(int(value, 16) for value in
                        re.findall(r'\b0x([0-9A-Fa-f]{2})\b', match.group(2)))
    if len(data) != expected_length:
        raise ValueError('GIO0._CRS RBUF byte count does not match Buffer length')
    return bytes(data)


def extended_irqs(data):
    irqs = []
    offset = 0
    end_tag_found = False
    while offset < len(data):
        tag = data[offset]
        if tag & 0x80:
            if offset + 3 > len(data):
                raise ValueError('truncated large ACPI resource header')
            length = int.from_bytes(data[offset + 1:offset + 3], 'little')
            body = data[offset + 3:offset + 3 + length]
            if len(body) != length:
                raise ValueError('truncated large ACPI resource')
            if tag == 0x89:
                if length < 2 or length != 2 + 4 * body[1]:
                    raise ValueError('malformed ExtendedIRQ resource')
                if body[1] != 1:
                    raise ValueError('PDC mapping requires one IRQ per ExtendedIRQ resource')
                irqs.append(int.from_bytes(body[2:6], 'little'))
            offset += 3 + length
        else:
            length = tag & 7
            if offset + 1 + length > len(data):
                raise ValueError('truncated small ACPI resource')
            if tag >> 3 == 0x0F:
                if offset + 1 + length != len(data):
                    raise ValueError('data after EndTag')
                end_tag_found = True
                break
            offset += 1 + length
    if not end_tag_found:
        raise ValueError('GIO0._CRS has no EndTag')
    if not irqs:
        raise ValueError('GIO0._CRS has no ExtendedIRQ resources')
    return irqs


def cipr_entries(gio):
    cipr = named_block(gio, 'Name', 'CIPR')
    entries = []
    for match in re.finditer(r'\bPackage\s*\(\s*0x03\s*\)', cipr):
        opening = cipr.find('{', match.end())
        closing = cipr.find('}', opening + 1)
        if opening < 0 or closing < 0:
            raise ValueError('malformed CIPR entry')
        tokens = re.findall(r'0x[0-9A-Fa-f]+|\bZero\b|\bOne\b',
                            mask_comments_and_strings(cipr[opening + 1:closing]))
        if len(tokens) != 3:
            raise ValueError('CIPR entry is not an integer triple')
        entries.append(tuple(0 if token == 'Zero' else
                             1 if token == 'One' else int(token, 16)
                             for token in tokens))
    if not entries:
        raise ValueError('GIO0.CIPR has no entries')
    return entries


def pdc_map(dsdt):
    gio = named_block(dsdt, 'Device', 'GIO0')
    count_match = re.search(r'\bName\s*\(\s*GPIC\s*,\s*(0x[0-9A-Fa-f]+|\d+)',
                            mask_comments_and_strings(gio))
    if not count_match:
        raise ValueError('GIO0.GPIC pin count not found')
    count = int(count_match.group(1), 0)
    if not 0 < count <= 4096:
        raise ValueError('invalid GIO0.GPIC pin count')
    irqs = extended_irqs(resource_bytes(gio))
    entries = cipr_entries(gio)
    by_irq = {}
    for _, pin, irq in entries:
        if not 0 <= pin < count:
            raise ValueError(f'CIPR IRQ {irq} has invalid physical GPIO {pin}')
        if irq in by_irq:
            raise ValueError(f'duplicate CIPR IRQ {irq}')
        by_irq[irq] = pin
    return count, [(irq, by_irq.get(irq)) for irq in irqs]


def resolve_pin(pin, count, mapping):
    if pin < 0:
        raise ValueError('negative ACPI GPIO pin')
    if pin < count:
        return pin, None, None
    index = pin // 64
    if index >= len(mapping):
        raise ValueError(f'ACPI pin {pin} has no PDC IRQ index {index}')
    irq, physical = mapping[index]
    if physical is None:
        raise ValueError(f'ACPI pin {pin} has no CIPR mapping for IRQ {irq}')
    return physical, index, irq


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dsdt', type=Path, help='private iasl-disassembled DSDT DSL')
    parser.add_argument('--pin', type=lambda value: int(value, 0), action='append',
                        default=[], help='ACPI GPIO pin to resolve; repeatable')
    args = parser.parse_args()
    try:
        count, mapping = pdc_map(args.dsdt.read_text(encoding='utf-8'))
        print(f'GIO0: {count} physical GPIOs, {len(mapping)} PDC IRQ slots')
        for pin in args.pin:
            physical, index, irq = resolve_pin(pin, count, mapping)
            if index is None:
                print(f'ACPI pin {pin}: direct GPIO {physical}')
            else:
                print(f'ACPI pin {pin}: PDC index {index}, IRQ {irq}, GPIO {physical}')
    except (OSError, UnicodeError, ValueError) as error:
        print(f'error: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
