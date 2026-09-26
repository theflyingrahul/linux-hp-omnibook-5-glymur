#!/usr/bin/env python3
"""Add one board-data entry to an ath12k board-2.bin container.

The ath12k container is the magic "QCA-ATH12K-BOARD\\0" (padded to 4 bytes)
followed by little-endian (id, length, data) IEs, each padded to 4 bytes.
A BOARD IE (id 0) holds one or more NAME sub-IEs (id 0) that share one DATA
sub-IE (id 1).

The output is for private, local testing. Board files extracted from a
Windows driver package are proprietary and must not be committed.
"""

import argparse
import hashlib
import struct
import sys
from pathlib import Path

MAGIC = b"QCA-ATH12K-BOARD\0"
IE_BOARD = 0
SUB_NAME = 0
SUB_DATA = 1


def pad4(data):
    return data + b"\0" * (-len(data) % 4)


def parse(container):
    if not container.startswith(MAGIC):
        raise ValueError("not an ath12k board-2.bin container")
    offset = len(pad4(MAGIC))
    ies = []
    while offset < len(container):
        if offset + 8 > len(container):
            raise ValueError("truncated IE header")
        ie_id, length = struct.unpack_from("<II", container, offset)
        body = container[offset + 8:offset + 8 + length]
        if len(body) != length:
            raise ValueError("truncated IE body")
        ies.append((ie_id, body))
        offset += 8 + length + (-length % 4)
    return ies


def board_names(body):
    names = []
    offset = 0
    while offset + 8 <= len(body):
        sub_id, length = struct.unpack_from("<II", body, offset)
        if sub_id == SUB_NAME:
            names.append(body[offset + 8:offset + 8 + length].decode("ascii"))
        offset += 8 + length + (-length % 4)
    return names


def all_names(ies):
    return [name for ie_id, body in ies if ie_id == IE_BOARD for name in board_names(body)]


def sub_ie(sub_id, data):
    return struct.pack("<II", sub_id, len(data)) + pad4(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("board2", type=Path, help="existing board-2.bin")
    parser.add_argument("data", type=Path, help="board data file (ELF)")
    parser.add_argument("name", help="exact ath12k board name string")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    container = args.board2.read_bytes()
    data = args.data.read_bytes()
    if not data.startswith(b"\x7fELF"):
        print("error: board data is not an ELF file", file=sys.stderr)
        return 1
    if not args.name.startswith("bus=pci,") or not args.name.isascii():
        print("error: unexpected board name format", file=sys.stderr)
        return 1
    if args.output.exists():
        print(f"error: refusing to overwrite {args.output}", file=sys.stderr)
        return 1

    ies = parse(container)
    names = all_names(ies)
    if args.name in names:
        print("error: board name already present", file=sys.stderr)
        return 1

    board = sub_ie(SUB_NAME, args.name.encode("ascii")) + sub_ie(SUB_DATA, data)
    out = bytearray(pad4(MAGIC))
    for ie_id, body in ies:
        out += struct.pack("<II", ie_id, len(body)) + pad4(body)
    out += struct.pack("<II", IE_BOARD, len(board)) + board

    # Round-trip check before writing.
    check = all_names(parse(bytes(out)))
    if check != names + [args.name]:
        print("error: round-trip check failed", file=sys.stderr)
        return 1

    args.output.write_bytes(out)
    for name in check:
        print(f"board: {name}")
    print(f"data sha256 {hashlib.sha256(data).hexdigest()}")
    print(f"output sha256 {hashlib.sha256(out).hexdigest()} ({len(out)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
