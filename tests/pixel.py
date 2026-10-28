#!/usr/bin/env python3
"""Pixel assertions for the headless shell tests (qs-harness.sh takes the pictures).

Used as a module by tests/shell.sh and by the overview UI's tests:

    sys.path.insert(0, "tests"); import pixel
    shot = pixel.Shot("bar.png")
    pixel.assert_width(shot.bbox_of_non_bg((0, 0, 1920, 30)), 380, tol=1)

or as a tool:  pixel.py count|bbox|dominant|size <png> ... (see main()).

PIL is used when importable; otherwise ImageMagick's raw RGB dump, so a machine with
only `magick` (this one) works. Boxes are (x0, y0, x1, y1), half-open like Python slices.
"""
import subprocess
import sys
from collections import Counter


def _hex(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _load(path):
    try:
        from PIL import Image
        im = Image.open(path).convert("RGB")
        return im.width, im.height, im.tobytes()
    except ImportError:
        pass
    size = subprocess.run(["magick", "identify", "-format", "%w %h", path + "[0]"],
                          capture_output=True, text=True, check=True).stdout.split()
    w, h = int(size[0]), int(size[1])
    raw = subprocess.run(["magick", path + "[0]", "-alpha", "off", "-depth", "8", "rgb:-"],
                         capture_output=True, check=True).stdout
    if len(raw) != w * h * 3:
        raise ValueError(f"{path}: expected {w * h * 3} bytes, got {len(raw)}")
    return w, h, raw


class Shot:
    def __init__(self, path):
        self.path = path
        self.w, self.h, self.data = _load(path)

    # -- single pixels and boxes ---------------------------------------
    def pixel(self, x, y):
        i = (y * self.w + x) * 3
        return (self.data[i], self.data[i + 1], self.data[i + 2])

    def box(self, box=None):
        x0, y0, x1, y1 = box or (0, 0, self.w, self.h)
        return max(0, x0), max(0, y0), min(self.w, x1), min(self.h, y1)

    def pixels(self, box=None):
        x0, y0, x1, y1 = self.box(box)
        for y in range(y0, y1):
            base = y * self.w * 3
            for x in range(x0, x1):
                i = base + x * 3
                yield x, y, (self.data[i], self.data[i + 1], self.data[i + 2])

    def crop(self, box):
        """A new Shot holding just the box."""
        x0, y0, x1, y1 = self.box(box)
        out = Shot.__new__(Shot)
        out.path, out.w, out.h = self.path, x1 - x0, y1 - y0
        rows = [self.data[(y * self.w + x0) * 3:(y * self.w + x1) * 3] for y in range(y0, y1)]
        out.data = b"".join(rows)
        return out

    # -- colour questions ----------------------------------------------
    def dominant(self, box=None):
        return Counter(p for _, _, p in self.pixels(box)).most_common(1)[0][0]

    @staticmethod
    def near(a, b, tol):
        return max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2])) <= tol

    def count_colour(self, hexcolour, box=None, tol=12):
        want = _hex(hexcolour)
        return sum(1 for _, _, p in self.pixels(box) if self.near(p, want, tol))

    def has_colour(self, box, hexcolour, tol=12, min_count=1):
        return self.count_colour(hexcolour, box, tol) >= min_count

    # -- shape questions -----------------------------------------------
    def bbox_of_non_bg(self, box=None, bg=None, tol=6):
        """Smallest box holding every pixel that differs from bg (default: the box's
        dominant colour). None when the box is all background."""
        bg = bg or self.dominant(box)
        xs, ys = [], []
        for x, y, p in self.pixels(box):
            if not self.near(p, bg, tol):
                xs.append(x)
                ys.append(y)
        if not xs:
            return None
        return min(xs), min(ys), max(xs) + 1, max(ys) + 1

    def col_runs(self, box, bg=None, tol=6, merge=4):
        """Horizontal runs of columns holding any non-bg pixel, runs closer than `merge`
        px joined. This is how 'three slabs, not ten' is counted."""
        x0, y0, x1, y1 = self.box(box)
        bg = bg or self.dominant(box)
        live = [False] * (x1 - x0)
        for x, y, p in self.pixels(box):
            if not self.near(p, bg, tol):
                live[x - x0] = True
        runs, start, gap = [], None, 0
        for i, on in enumerate(live):
            if on:
                if start is None:
                    start = i
                gap = 0
                last = i
            elif start is not None:
                gap += 1
                if gap >= merge:
                    runs.append((x0 + start, x0 + last + 1))
                    start = None
        if start is not None:
            runs.append((x0 + start, x0 + last + 1))
        return runs

    def rows_with_non_bg(self, box, bg=None, tol=6):
        x0, y0, x1, y1 = self.box(box)
        bg = bg or self.dominant(box)
        rows = set()
        for x, y, p in self.pixels(box):
            if not self.near(p, bg, tol):
                rows.add(y)
        return sorted(rows)

    def thin_verticals(self, box, min_rows, tol=3):
        """Columns holding a run of at least min_rows consecutive rows where the pixel is
        one steady colour that differs from BOTH neighbouring columns: a 1 px line.
        Returns [(x, colour)]."""
        x0, y0, x1, y1 = self.box(box)
        out = []
        for x in range(max(1, x0), min(self.w - 1, x1)):
            best, run, prev = 0, 0, None
            for y in range(y0, y1):
                c = self.pixel(x, y)
                alone = (not self.near(c, self.pixel(x - 1, y), tol)
                         and not self.near(c, self.pixel(x + 1, y), tol))
                if alone and (prev is None or self.near(c, prev, 1)):
                    run += 1
                else:
                    run = 1 if alone else 0
                prev = c if alone else None
                best = max(best, run)
            if best >= min_rows:
                out.append((x, self.pixel(x, (y0 + y1) // 2)))
        return out


def assert_width(box, want, tol=1, what="box"):
    """box is a bbox (x0, y0, x1, y1) or a (start, end) run."""
    if box is None:
        raise AssertionError(f"{what}: nothing drawn")
    w = (box[2] - box[0]) if len(box) == 4 else (box[1] - box[0])
    if abs(w - want) > tol:
        raise AssertionError(f"{what}: width {w}, want {want} +-{tol}")
    return w


def main(argv):
    if len(argv) < 3:
        print("usage: pixel.py size|dominant|bbox|count|runs <png> [x0 y0 x1 y1] [hex] [tol]", file=sys.stderr)
        return 2
    cmd, path = argv[1], argv[2]
    s = Shot(path)
    nums = [int(a) for a in argv[3:7]] if len(argv) >= 7 else None
    box = tuple(nums) if nums else None
    if cmd == "size":
        print(s.w, s.h)
    elif cmd == "dominant":
        print("#%02x%02x%02x" % s.dominant(box))
    elif cmd == "bbox":
        print(s.bbox_of_non_bg(box))
    elif cmd == "runs":
        print(s.col_runs(box or (0, 0, s.w, s.h)))
    elif cmd == "count":
        print(s.count_colour(argv[7], box, int(argv[8]) if len(argv) > 8 else 12))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
