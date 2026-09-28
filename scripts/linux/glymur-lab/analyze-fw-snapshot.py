#!/usr/bin/env python3
"""Decode a glymur_lab 'snapshot' of the firmware's live eDP link.

Usage: analyze-fw-snapshot.py SNAPSHOT [--pixel-khz 149760]

Prints human-readable findings, then shell assignments (FW_LANES, FW_MAP,
FW_RATE_HZ) that glymur-lab-run.sh evaluates for its "firmware-mimic"
variant. A value that cannot be derived is left empty, never guessed.

Link rate: DP Mvid/Nvid = pixel clock / link symbol clock, and the symbol
clock is the per-lane bit rate / 10, so rate = pixel * Nvid / Mvid * 10.
The pixel clock defaults to the panel EDID's 149.76 MHz (1920x1200@60).
"""

import argparse
import re
import sys

DP_LINK_BASE = 0x0af6d000
REG_CONFIGURATION_CTRL = 0x08
REG_SOFTWARE_MVID = 0x10
REG_SOFTWARE_NVID = 0x18
REG_MAINLINK_CTRL = 0x00
REG_LANE_MAPPING = 0x38
STANDARD_RATES = (1620000000, 2160000000, 2430000000, 2700000000,
                  3240000000, 4320000000, 5400000000, 8100000000)


def parse(text):
    regs = {}
    for line in text.splitlines():
        m = re.match(r'([0-9a-f]{8}):((?: [0-9a-f]{8})+)$', line.strip())
        if m:
            addr = int(m.group(1), 16)
            for i, word in enumerate(m.group(2).split()):
                regs[addr + 4 * i] = int(word, 16)
    return regs


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('snapshot')
    ap.add_argument('--pixel-khz', type=int, default=149760)
    args = ap.parse_args()
    text = open(args.snapshot, encoding='utf-8', errors='replace').read()
    for line in text.splitlines():
        if line.startswith(('tcsr', 'dispcc', 'tlmm', 'DP3/PHY')):
            print('#', line)
    regs = parse(text)

    lanes = mapping = rate = ''
    cfg = regs.get(DP_LINK_BASE + REG_CONFIGURATION_CTRL)
    if cfg is not None:
        n = ((cfg >> 4) & 0x3) + 1
        lanes = str(n)
        print(f'# CONFIGURATION_CTRL {cfg:08x}: {n} lanes, bpc field {(cfg >> 8) & 3}, '
              f'enhanced framing {bool(cfg & 0x40)}, ASSR {bool(cfg & 0x400)}')
        mlc = regs.get(DP_LINK_BASE + REG_MAINLINK_CTRL)
        if mlc is not None:
            print(f'# MAINLINK_CTRL {mlc:08x} (enable bit0 {mlc & 1})')
        lm = regs.get(DP_LINK_BASE + REG_LANE_MAPPING)
        if lm is not None:
            lane_map = [(lm >> (2 * i)) & 3 for i in range(4)]
            mapping = ','.join(str(x) for x in lane_map[:n])
            print(f'# LOGICAL2PHYSICAL_LANE_MAPPING {lm:08x}: {lane_map}')
        mvid = regs.get(DP_LINK_BASE + REG_SOFTWARE_MVID)
        nvid = regs.get(DP_LINK_BASE + REG_SOFTWARE_NVID)
        if mvid and nvid:
            est = args.pixel_khz * 1000 * nvid / mvid * 10
            best = min(STANDARD_RATES, key=lambda r: abs(r - est))
            print(f'# MVID {mvid:#x} NVID {nvid:#x}: ~{est / 1e9:.3f} Gb/s per lane '
                  f'(nearest standard {best / 1e9:.2f})')
            if abs(best - est) / best < 0.05:
                rate = str(best)
        else:
            print('# software MVID/NVID not set: link rate not derivable here')
    else:
        print('# DP3 registers not in the snapshot (display not powered by firmware?)')

    for name, base in (('tx0', 0x00faa400), ('tx1', 0x00faa800)):
        vals = {k: regs.get(base + off) for k, off in
                (('drv', 0x14), ('emp', 0x04), ('ldo', 0x84), ('band', 0x28),
                 ('pol', 0x5c), ('highz', 0x58), ('bias', 0x54))}
        if all(v is not None for v in vals.values()):
            print(f'# phy {name}: ' + ' '.join(f'{k} {v:#04x}' for k, v in vals.items()))

    print(f'FW_LANES={lanes}')
    print(f'FW_MAP={mapping}')
    print(f'FW_RATE_HZ={rate}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
