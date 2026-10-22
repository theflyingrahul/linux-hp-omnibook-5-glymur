#!/usr/bin/env python3
"""Read an AudioReach calibration database (ACDB) and extract module
calibration for an AudioReach topology. See scripts/linux/README.md."""

import argparse
import collections
import struct
import sys

MODULE_LIST = 0x08001002            # APM_PARAM_ID_MODULE_LIST
MODULE_CFG_TYPE = 0x01001006        # SND_SOC_AR_TPLG_MODULE_CFG_TYPE


def u32(b, off):
    return struct.unpack_from('<I', b, off)[0]


class Acdb:
    def __init__(self, path):
        self.b = open(path, 'rb').read()
        if self.b[:4] != b'ACDB':
            sys.exit('%s: not an ACDB file' % path)
        self.ch = {}
        off = 12
        while off + 8 <= len(self.b) and self.b[off:off + 4].isalnum():
            size = u32(self.b, off + 4)
            self.ch[self.b[off:off + 4].decode()] = (off + 8, size)
            off += 8 + size

    def chunk(self, name):
        return self.ch[name][0]

    def graphs(self):
        """(key/value pairs, subgraph list) for each graph key vector."""
        b = self.b
        gkvt, gkvl, pool = self.chunk('GKVT'), self.chunk('GKVL'), self.chunk('POOL')
        off = gkvt + 4
        for _ in range(u32(b, gkvt)):
            nk, ne = struct.unpack_from('<II', b, off)
            off += 8
            for _ in range(ne):
                keys = [u32(b, off + 4 * i) for i in range(nk)]
                lut = u32(b, off + 4 * nk)
                off += 4 * nk + 4
                lk, le = struct.unpack_from('<II', b, gkvl + lut)
                r = gkvl + lut + 8
                for _ in range(le):
                    vals = [u32(b, r + 4 * i) for i in range(lk)]
                    sgl = u32(b, r + 4 * lk)
                    r += 4 * lk + 8
                    nsg = u32(b, pool + sgl + 4)
                    p = pool + sgl + 8
                    sgs = []
                    for _ in range(nsg):
                        sg, n = struct.unpack_from('<II', b, p)
                        sgs.append(sg)
                        p += 8 + 4 * n
                    yield tuple(zip(keys, vals)), sgs

    def module_lists(self):
        """{subgraph: [(module id, instance id)]} from the APM module lists."""
        b = self.b
        out = {}
        pat = struct.pack('<I', MODULE_LIST)
        off = 0
        while True:
            off = b.find(pat, off + 1)
            if off < 0:
                return out
            size = u32(b, off + 4)
            p = off + 8
            if not 4 <= size <= 4096 or not 0 < u32(b, p) < 16:
                continue
            q = p + 4
            entries = []
            for _ in range(u32(b, p)):
                sg, _cont, n = struct.unpack_from('<III', b, q)
                q += 12
                if not 0 < n < 64 or (sg >> 28) == 0:
                    entries = None
                    break
                entries.append((sg, [struct.unpack_from('<II', b, q + 8 * i) for i in range(n)]))
                q += 8 * n
            if entries and q - p <= size:
                for sg, ms in entries:
                    out.setdefault(sg, ms)

    def cal_rows(self, subgraph):
        """For a subgraph: (calibration key/value pairs, [(iid, pid, data)])."""
        b = self.b
        cslu, csz = self.ch['CSLU']
        cakt, cdlu = self.chunk('CAKT'), self.chunk('CDLU')
        cdde, cddo, pool = self.chunk('CDDE'), self.chunk('CDDO'), self.chunk('POOL')
        off = cslu + 4
        while off < cslu + csz:
            sg, n = struct.unpack_from('<II', b, off)
            off += 8
            for _ in range(n):
                okt, olut = struct.unpack_from('<II', b, off)
                off += 8
                if sg != subgraph:
                    continue
                nk = u32(b, cakt + okt)
                keys = [u32(b, cakt + okt + 4 + 4 * i) for i in range(nk)]
                row = cdlu + olut + 8
                for _ in range(u32(b, cdlu + olut + 4)):
                    vals = [u32(b, row + 4 * i) for i in range(nk)]
                    odef, odot, _ = struct.unpack_from('<III', b, row + 4 * nk)
                    row += 4 * nk + 12
                    recs = []
                    for i in range(u32(b, cdde + odef)):
                        iid, pid = struct.unpack_from('<II', b, cdde + odef + 4 + 8 * i)
                        po = pool + u32(b, cddo + odot + 4 + 4 * i)
                        recs.append((iid, pid, b[po + 4:po + 4 + u32(b, po)]))
                    yield tuple(zip(keys, vals)), recs


def kv_str(kvs):
    return ' '.join('%x=%x' % kv for kv in kvs) or '(no keys)'


def parse_kv(items):
    return {int(k, 16): int(v, 16) for k, v in (s.split('=') for s in items)}


def param_records(recs, remap):
    """APM_CMD_SET_CFG payload: <iid, pid, size, error> plus data, 8-byte aligned."""
    out = bytearray()
    for iid, pid, data in recs:
        out += struct.pack('<IIII', remap.get(iid, iid), pid, len(data), 0)
        out += data + b'\0' * (-len(data) % 8)
    return bytes(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('acdb')
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('chunks', help='list the chunks')
    g = sub.add_parser('graphs', help='list graph key vectors and their subgraphs')
    g.add_argument('--sg', action='append', default=[], help='only graphs with this subgraph (hex)')
    m = sub.add_parser('modules', help='list module instances per subgraph')
    m.add_argument('--sg', action='append', default=[], help='only this subgraph (hex)')
    c = sub.add_parser('cal', help="list or extract a subgraph's calibration")
    c.add_argument('sg', help='subgraph id (hex)')
    c.add_argument('--ckv', action='append', default=[], help='KEY=VALUE (hex) a row must have')
    c.add_argument('--iid', action='append', default=[], help='only this module instance (hex)')
    c.add_argument('--remap', action='append', default=[], help='ACDB_IID=TOPOLOGY_IID (hex)')
    c.add_argument('--max', type=int, default=0, help='skip parameters larger than this (bytes)')
    c.add_argument('--bin', help='write the selected row as APM parameter records')
    c.add_argument('--m4', nargs=2, metavar=('NAME', 'FILE'),
                   help='write the selected row as a topology SectionData')
    a = ap.parse_args()
    db = Acdb(a.acdb)

    if a.cmd == 'chunks':
        for name, (off, size) in db.ch.items():
            print('%s  offset %#9x  size %9d' % (name, off - 8, size))
    elif a.cmd == 'graphs':
        want = {int(s, 16) for s in a.sg}
        for kvs, sgs in db.graphs():
            if not want or want & set(sgs):
                print(kv_str(kvs))
                print('    subgraphs: ' + ' '.join('%x' % s for s in sgs))
    elif a.cmd == 'modules':
        want = {int(s, 16) for s in a.sg}
        for sg, ms in sorted(db.module_lists().items()):
            if not want or sg in want:
                print('subgraph %#x' % sg)
                for mid, iid in ms:
                    print('    instance %#07x  module %#010x' % (iid, mid))
    else:
        sg = int(a.sg, 16)
        ckv = parse_kv(a.ckv)
        iids = {int(s, 16) for s in a.iid}
        remap = parse_kv(a.remap)
        rows = [(kvs, recs) for kvs, recs in db.cal_rows(sg)
                if all(dict(kvs).get(k) == v for k, v in ckv.items())]
        for kvs, recs in rows:
            print(kv_str(kvs))
            for iid, pid, data in recs:
                if not iids or iid in iids:
                    print('    instance %#07x  param %#010x  %6d bytes' % (iid, pid, len(data)))
        if a.bin or a.m4:
            if len(rows) != 1:
                sys.exit('%d rows match; narrow them with --ckv' % len(rows))
            recs = [r for r in rows[0][1] if (not iids or r[0] in iids)]
            big = [r for r in recs if a.max and len(r[2]) > a.max]
            for iid, pid, data in big:
                print('skipped: instance %#x param %#x, %d bytes' % (iid, pid, len(data)), file=sys.stderr)
            payload = param_records([r for r in recs if r not in big], remap)
            if a.bin:
                open(a.bin, 'wb').write(payload)
            if a.m4:
                blob = struct.pack('<IIII', len(payload), MODULE_CFG_TYPE, 0, 0) + payload
                lines = [','.join('0x%02x' % x for x in blob[i:i + 16]) for i in range(0, len(blob), 16)]
                with open(a.m4[1], 'w', newline='\n') as f:
                    f.write('SectionData."%s" {\n\tbytes "\n\t\t%s"\n}\n' % (a.m4[0], ',\n\t\t'.join(lines)))
            print('%d records, %d bytes' % (len(recs) - len(big), len(payload)), file=sys.stderr)


if __name__ == '__main__':
    main()
