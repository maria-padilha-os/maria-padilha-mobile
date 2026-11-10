#!/usr/bin/env python3
"""Minimal stdlib PNG check: dimensions and a non-blank colour sample."""

from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path


def paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def read_png(path: Path) -> tuple[int, int, int]:
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"{path}: not a PNG"
    pos = 8
    width = height = bit_depth = colour_type = None
    idat = bytearray()
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, bit_depth, colour_type, _, _, interlace = struct.unpack(">IIBBBBB", payload)
            assert bit_depth == 8, f"{path}: expected 8-bit PNG"
            assert interlace == 0, f"{path}: interlaced PNG is not supported"
        elif kind == b"IDAT":
            idat.extend(payload)
        elif kind == b"IEND":
            break
    assert width is not None and height is not None, f"{path}: missing IHDR"
    assert colour_type in (2, 6), f"{path}: expected RGB/RGBA, got colour type {colour_type}"

    bpp = 3 if colour_type == 2 else 4
    stride = width * bpp
    raw = zlib.decompress(bytes(idat))
    assert len(raw) == height * (stride + 1), f"{path}: unexpected decompressed size"

    previous = bytearray(stride)
    rows = []
    offset = 0
    for _ in range(height):
        filter_type = raw[offset]
        offset += 1
        row = bytearray(raw[offset:offset + stride])
        offset += stride
        for i in range(stride):
            left = row[i - bpp] if i >= bpp else 0
            up = previous[i]
            up_left = previous[i - bpp] if i >= bpp else 0
            if filter_type == 1:
                row[i] = (row[i] + left) & 0xFF
            elif filter_type == 2:
                row[i] = (row[i] + up) & 0xFF
            elif filter_type == 3:
                row[i] = (row[i] + ((left + up) // 2)) & 0xFF
            elif filter_type == 4:
                row[i] = (row[i] + paeth(left, up, up_left)) & 0xFF
            elif filter_type != 0:
                raise AssertionError(f"{path}: bad filter {filter_type}")
        rows.append(bytes(row))
        previous = row

    colours = set()
    for y in range(0, height, max(1, height // 24)):
        row = rows[y]
        for x in range(0, width, max(1, width // 24)):
            colours.add(row[x * bpp:(x + 1) * bpp])
    return width, height, len(colours)


def main() -> int:
    if len(sys.argv) not in (4, 5):
        print("usage: check_png.py IMAGE WIDTH HEIGHT [MIN_COLOURS]", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    expected_width, expected_height = int(sys.argv[2]), int(sys.argv[3])
    minimum = int(sys.argv[4]) if len(sys.argv) == 5 else 8
    width, height, colours = read_png(path)
    assert (width, height) == (expected_width, expected_height), \
        f"{path}: {width}x{height}, expected {expected_width}x{expected_height}"
    assert colours >= minimum, f"{path}: only {colours} sampled colours; surface looks blank"
    print(f"ok {path.name} {width}x{height}, {colours} sampled colours")
    return 0


if __name__ == "__main__":
    sys.exit(main())
