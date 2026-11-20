"""Tiny PNG reader/writer (stdlib only) for tests/bar-ui.sh: decode 8-bit RGB/RGBA, crop, scale."""
import struct
import zlib


def read(path):
    d = open(path, "rb").read()
    assert d[:8] == b"\x89PNG\r\n\x1a\n", "not a png"
    pos, idat, w, h, ct = 8, b"", 0, 0, 6
    while pos < len(d):
        n, t = struct.unpack(">I4s", d[pos:pos + 8])
        body = d[pos + 8:pos + 8 + n]
        if t == b"IHDR":
            w, h, depth, ct, _, _, il = struct.unpack(">IIBBBBB", body)
            assert depth == 8 and il == 0 and ct in (2, 6), "unsupported png"
        elif t == b"IDAT":
            idat += body
        pos += 12 + n
    bpp = 4 if ct == 6 else 3
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev = [], bytearray(stride)
    p = 0
    for _ in range(h):
        f = raw[p]
        line = bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        rows.append(line)
        prev = line
    return w, h, bpp, rows


def pixel(img, x, y):
    w, h, bpp, rows = img
    r = rows[y]
    return r[x * bpp], r[x * bpp + 1], r[x * bpp + 2]


def write(path, w, h, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    def chunk(t, dd):
        return struct.pack(">I", len(dd)) + t + dd + struct.pack(">I", zlib.crc32(t + dd) & 0xFFFFFFFF)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def crop(src, dst, x0, y0, x1, y1, scale=1):
    w, h, bpp, rows = read(src)
    out = []
    for y in range(y0, min(y1, h)):
        line = bytearray()
        for x in range(x0, min(x1, w)):
            px = rows[y][x * bpp:x * bpp + 3]
            line += px * scale
        out += [line] * scale
    write(dst, (min(x1, w) - x0) * scale, len(out), out)


if __name__ == "__main__":
    import sys
    a = sys.argv
    crop(a[1], a[2], int(a[3]), int(a[4]), int(a[5]), int(a[6]), int(a[7]) if len(a) > 7 else 1)
