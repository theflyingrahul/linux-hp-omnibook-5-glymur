"""Flatten the HP Glymur PEP0 power tables from a decompiled DSDT.

Usage: analyze-acpi-pep.py <DSDT.dsl> <out.tsv>

Windows' power engine plug-in (PEP) packages describe, per ACPI device,
what to do in each component F-state, P-state and device D-state: PMIC rail
votes (PMICVREGVOTE), TLMM GPIO writes (TLMMGPIO), GDSC footswitches, clocks
and bus bandwidth votes. These are HP's own board-level power recipes, the
evidence a device tree needs for regulators and power-sequencing GPIOs.

Each output row is one action with its context:
device, component, state (e.g. FSTATE 0 / DSTATE 3), action, fields.
The DSDT is private; the output TSV holds derived facts (rail names,
voltages, GPIO numbers) and stays in .work/ until reviewed.
"""
import re
import sys

TOKEN = re.compile(r'Package\s*\([^)]*\)\s*\{|\}|"(?:[^"\\]|\\.)*"|\b0x[0-9A-Fa-f]+\b|\b(?:Zero|One|Ones)\b|\b\d+\b')
STATE_TAGS = {'FSTATE', 'PSTATE', 'DSTATE', 'PSTATE_SET', 'ABANDON_DSTATE',
              'PRELOAD_PSTATE', 'PRELOAD_FSTATE', 'INIT_FSTATE'}
ACTIONS = {'PMICVREGVOTE', 'TLMMGPIO', 'FOOTSWITCH', 'CLOCK', 'BUSARB',
           'NPARESOURCE', 'DELAY', 'CESTA_BUSARB', 'PSTATE_ADJUST'}


def value(tok):
    if tok.startswith('"'):
        return tok[1:-1]
    return {'Zero': 0, 'One': 1, 'Ones': 0xFFFFFFFFFFFFFFFF}.get(tok, None) \
        if tok in ('Zero', 'One', 'Ones') else int(tok, 0)


class Pkg:
    def __init__(self):
        self.items = []     # scalar elements in order (nested packages as None)
        self.children = []


def parse(text):
    root = Pkg()
    stack = [root]
    for m in TOKEN.finditer(text):
        tok = m.group(0)
        if tok.startswith('Package'):
            p = Pkg()
            stack[-1].items.append(None)
            stack[-1].children.append(p)
            stack.append(p)
        elif tok == '}':
            if len(stack) > 1:
                stack.pop()
        else:
            stack[-1].items.append(value(tok))
    return root


def flat(pkg):
    """Scalars of an action package, descending into one nested package."""
    out = []
    for item in pkg.items:
        if item is not None:
            out.append(item)
    for child in pkg.children:
        out.extend(flat(child))
    return out


def fmt(v):
    return f'0x{v:x}' if isinstance(v, int) and v > 9 else str(v)


def walk(pkg, ctx, rows):
    head = [i for i in pkg.items[:2]]
    tag = head[0] if head and isinstance(head[0], str) else None
    arg = head[1] if len(head) > 1 else None
    if tag == 'DEVICE':
        # "DEVICE", [flags,] "\\_SB.NAME": take the first string after the tag.
        name = next((i for i in pkg.items[1:3] if isinstance(i, str)), None)
        if name:
            ctx = dict(ctx, device=name, component='', state='')
    elif tag == 'COMPONENT':
        ctx = dict(ctx, component=str(arg), state='')
    elif tag in STATE_TAGS:
        ctx = dict(ctx, state=f'{tag} {arg}' if arg is not None else tag)
    elif tag in ACTIONS and 'device' in ctx:
        fields = [fmt(v) for v in flat(pkg)[1:]]
        rows.append((ctx['device'], ctx['component'], ctx['state'], tag, fields))
        return
    for child in pkg.children:
        walk(child, ctx, rows)


def main():
    src, out = sys.argv[1], sys.argv[2]
    text = open(src, encoding='utf-8', errors='replace').read()
    # Drop comments so byte-dump annotations do not become tokens.
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    rows = []
    walk(parse(text), {}, rows)
    with open(out, 'w', encoding='utf-8') as f:
        f.write('device\tcomponent\tstate\taction\tfields\n')
        for dev, comp, state, action, fields in rows:
            f.write(f'{dev}\t{comp}\t{state}\t{action}\t{",".join(fields)}\n')
    devices = sorted({r[0] for r in rows})
    print(f'{len(rows)} actions across {len(devices)} devices -> {out}')


if __name__ == '__main__':
    main()
