#!/usr/bin/env python3
"""Check that a DTB's TLMM gpio-reserved-ranges is an exact allow-list.

Every TLMM pin that an enabled node uses (pinctrl states, *-gpios / gpio
properties, interrupts-extended, or interrupts with the TLMM as interrupt
parent) must be unreserved, and every other pin must be reserved. A reserved
pin in use would fail to probe; an unused pin left unreserved could be
driven by something unexpected.

Usage: check-dt-gpio-allowlist.py [--ngpios 251] DTB [DTB ...]
Needs pylibfdt (python3-libfdt). Exit status 1 on any mismatch.
"""

import argparse
import re
import sys

import libfdt

TLMM_COMPATIBLES = (b'qcom,mahua-tlmm', b'qcom,glymur-tlmm')


def prop(fdt, node, name):
    value = fdt.getprop(node, name, quiet=(libfdt.FDT_ERR_NOTFOUND,))
    return None if isinstance(value, int) else bytes(value)


def cells(data):
    return [int.from_bytes(data[i:i + 4], 'big') for i in range(0, len(data), 4)]


def strings(data):
    return [s.decode() for s in data.split(b'\0') if s]


def walk(fdt, offset=0, parent_enabled=True):
    """Yield (offset, path, enabled) for every node, depth first. A node is
    enabled when it and all its ancestors have no status or status okay."""
    status = prop(fdt, offset, 'status')
    enabled = parent_enabled and (
        status is None or status.rstrip(b'\0') in (b'okay', b'ok'))
    yield offset, fdt.get_path(offset), enabled
    child = fdt.first_subnode(offset, (libfdt.FDT_ERR_NOTFOUND,))
    while child >= 0:
        yield from walk(fdt, child, enabled)
        child = fdt.next_subnode(child, (libfdt.FDT_ERR_NOTFOUND,))


def find_tlmm(fdt):
    for offset, path, _ in walk(fdt):
        compatible = prop(fdt, offset, 'compatible') or b''
        if any(c in compatible.split(b'\0') for c in TLMM_COMPATIBLES):
            return offset, path
    raise SystemExit('no Glymur/Mahua TLMM node in the DTB')


def phandle_list(fdt, data, cells_prop):
    """Split a phandle+args list, looking up each provider's cell count."""
    values = cells(data)
    index = 0
    while index < len(values):
        handle = values[index]
        if handle == 0:
            index += 1
            continue
        provider = fdt.node_offset_by_phandle(handle)
        count_data = prop(fdt, provider, cells_prop)
        if count_data is None:
            raise ValueError(f'phandle {handle:#x} has no {cells_prop}')
        count = cells(count_data)[0]
        yield provider, values[index + 1:index + 1 + count]
        index += 1 + count


def interrupt_parent(fdt, offset):
    while offset >= 0:
        data = prop(fdt, offset, 'interrupt-parent')
        if data is not None:
            return fdt.node_offset_by_phandle(cells(data)[0])
        offset = fdt.parent_offset(offset, (libfdt.FDT_ERR_NOTFOUND,))
    return -1


def state_pins(fdt, state, tlmm_path):
    """Pins named by a pinctrl state node and its subnodes."""
    if not fdt.get_path(state).startswith(tlmm_path + '/'):
        return set()
    found = set()
    todo = [state]
    while todo:
        node = todo.pop()
        data = prop(fdt, node, 'pins')
        if data is not None:
            for name in strings(data):
                match = re.fullmatch(r'gpio(\d+)', name)
                if match:
                    found.add(int(match.group(1)))
        child = fdt.first_subnode(node, (libfdt.FDT_ERR_NOTFOUND,))
        while child >= 0:
            todo.append(child)
            child = fdt.next_subnode(child, (libfdt.FDT_ERR_NOTFOUND,))
    return found


def used_pins(fdt, tlmm, tlmm_path):
    used = {}
    for offset, path, enabled in walk(fdt):
        if not enabled or path == tlmm_path or path.startswith(tlmm_path + '/'):
            continue
        poff = fdt.first_property_offset(offset, (libfdt.FDT_ERR_NOTFOUND,))
        while poff >= 0:
            p = fdt.get_property_by_offset(poff)
            name, data = p.name, bytes(p)
            pins = set()
            if re.fullmatch(r'pinctrl-\d+', name):
                for handle in cells(data):
                    pins |= state_pins(fdt, fdt.node_offset_by_phandle(handle),
                                       tlmm_path)
            elif name in ('gpio', 'gpios') or name.endswith('-gpio') or \
                    name.endswith('-gpios'):
                for provider, args in phandle_list(fdt, data, '#gpio-cells'):
                    if provider == tlmm:
                        pins.add(args[0])
            elif name == 'interrupts-extended':
                for provider, args in phandle_list(fdt, data, '#interrupt-cells'):
                    if provider == tlmm:
                        pins.add(args[0])
            elif name == 'interrupts' and interrupt_parent(fdt, offset) == tlmm:
                pins.update(cells(data)[0::2])
            for pin in pins:
                used.setdefault(pin, set()).add(f'{path}:{name}')
            poff = fdt.next_property_offset(poff, (libfdt.FDT_ERR_NOTFOUND,))
    return used


def check(path, ngpios):
    with open(path, 'rb') as handle:
        fdt = libfdt.Fdt(handle.read())
    tlmm, tlmm_path = find_tlmm(fdt)
    data = prop(fdt, tlmm, 'gpio-reserved-ranges')
    if data is None:
        print(f'{path}: FAIL no gpio-reserved-ranges')
        return False
    values = cells(data)
    reserved = set()
    ok = True
    for start, count in zip(values[0::2], values[1::2]):
        if start + count > ngpios:
            print(f'{path}: FAIL range <{start} {count}> passes GPIO {ngpios - 1}')
            ok = False
        reserved.update(range(start, start + count))
    used = used_pins(fdt, tlmm, tlmm_path)
    for pin in sorted(set(used) & reserved):
        print(f'{path}: FAIL GPIO {pin} is reserved but used by '
              + ', '.join(sorted(used[pin])))
        ok = False
    for pin in sorted(set(range(ngpios)) - reserved - set(used)):
        print(f'{path}: FAIL GPIO {pin} is neither used nor reserved')
        ok = False
    for pin in sorted(used):
        print(f'  GPIO {pin:3d}: ' + ', '.join(sorted(used[pin])))
    print(f'{path}: {"OK" if ok else "FAIL"} ({len(used)} pins used, '
          f'{len(reserved)} reserved, {ngpios} total)')
    return ok


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--ngpios', type=int, default=251,
                        help='TLMM pin count (pinctrl-glymur.c ngpios: 251)')
    parser.add_argument('dtb', nargs='+')
    args = parser.parse_args()
    results = [check(path, args.ngpios) for path in args.dtb]
    return 0 if all(results) else 1


if __name__ == '__main__':
    sys.exit(main())
