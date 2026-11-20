#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""launcher_math.py query <text>: the launcher's "=" mode. Prints one JSON object {rows, hint, error}.

Arithmetic (safe AST walk, no eval), unit conversion ("3 GiB in MiB"), clock sums ("18:40 + 7h 40m"),
date sums ("today + 2w") and date gaps. Anything else falls through to `qalc` if it is installed.
Local only: no network. Argv only: qalc is run as a list, never through a shell.
"""
import ast
import datetime as dt
import json
import math
import operator
import re
import shutil
import subprocess
import sys

HINT = "Type a sum, a conversion (3 GiB in MiB) or a date (today + 2w)."
BODY = "Also units and dates: 3 GiB in MiB, 18:40 + 7h 40m."

# ---- units ---------------------------------------------------------------------------------
UNITS = {
    "data": {"b": 1, "B": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12, "PB": 1e15,
             "KiB": 1024, "MiB": 1024 ** 2, "GiB": 1024 ** 3, "TiB": 1024 ** 4, "PiB": 1024 ** 5,
             "bit": 1 / 8, "kbit": 1e3 / 8, "Mbit": 1e6 / 8, "Gbit": 1e9 / 8},
    "time": {"ms": 0.001, "s": 1, "sec": 1, "min": 60, "h": 3600, "hr": 3600, "d": 86400, "day": 86400,
             "days": 86400, "w": 604800, "week": 604800, "weeks": 604800, "hours": 3600, "minutes": 60,
             "seconds": 1},
    "length": {"mm": 0.001, "cm": 0.01, "m": 1, "km": 1000, "in": 0.0254, "ft": 0.3048, "yd": 0.9144,
               "mi": 1609.344},
    "mass": {"mg": 1e-6, "g": 0.001, "kg": 1, "t": 1000, "oz": 0.028349523125, "lb": 0.45359237},
}
TEMPS = {"C", "F", "K"}
NUM = r"[-+]?\d[\d_,]*(?:\.\d+)?(?:e[-+]?\d+)?"


def find_unit(name):
    """-> {category: factor} for every category that knows `name` (exact case first, then folded)."""
    hit = {c: t[name] for c, t in UNITS.items() if name in t}
    if hit:
        return hit
    low = name.lower()
    return {c: v for c, t in UNITS.items() for k, v in t.items() if k.lower() == low}


def fmt(x):
    if isinstance(x, bool):
        return str(x)
    if isinstance(x, int):
        return str(x)
    if x != x or x in (math.inf, -math.inf):
        raise ValueError("not finite")
    if float(x).is_integer() and abs(x) < 1e15:
        return str(int(x))
    s = "%.10g" % x
    return s


def to_num(s):
    s = s.replace("_", "").replace(",", "")
    return int(s) if re.fullmatch(r"[-+]?\d+", s) else float(s)


def temperature(text):
    m = re.fullmatch(r"\s*(%s)\s*°?\s*([CFK])\s+(?:in|to|as|->)\s+°?([CFK])\s*" % NUM, text, re.I)
    if not m:
        return None
    v, a, b = to_num(m.group(1)), m.group(2).upper(), m.group(3).upper()
    k = v if a == "K" else (v + 273.15 if a == "C" else (v - 32) * 5 / 9 + 273.15)
    out = k if b == "K" else (k - 273.15 if b == "C" else (k - 273.15) * 9 / 5 + 32)
    return "%s %s" % (fmt(round(out, 6)), "K" if b == "K" else "°" + b)


def convert(text):
    t = temperature(text)
    if t:
        return t
    m = re.fullmatch(r"\s*(%s)\s*([A-Za-z]+)\s+(?:in|to|as|->)\s+([A-Za-z]+)\s*" % NUM, text, re.I)
    if not m:
        return None
    v, a, b = to_num(m.group(1)), m.group(2), m.group(3)
    fa, fb = find_unit(a), find_unit(b)
    for cat in fa:
        if cat in fb:
            out = v * fa[cat] / fb[cat]
            return "%s %s" % (fmt(round(out, 9)) if isinstance(out, float) else fmt(out), b)
    return None


# ---- clock and calendar --------------------------------------------------------------------
DUR = re.compile(r"(\d+(?:\.\d+)?)\s*(weeks?|w|days?|d|hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b", re.I)
SECS = {"w": 604800, "d": 86400, "h": 3600, "m": 60, "s": 1}


def durations(s):
    s = s.strip()
    pos, total = 0, 0.0
    for m in DUR.finditer(s):
        if s[pos:m.start()].strip():
            return None
        total += float(m.group(1)) * SECS[m.group(2)[0].lower()]
        pos = m.end()
    return total if pos and not s[pos:].strip() else None


def hm(sec):
    sec = int(round(sec))
    h, m = divmod(abs(sec) // 60, 60)
    return "%dh %02dm" % (h, m) if h else "%dm" % m


def clock(text, now):
    m = re.fullmatch(r"\s*(\d{1,2}):(\d{2})\s*([+-])\s*(.+?)\s*", text)
    if m:
        h, mi = int(m.group(1)), int(m.group(2))
        if h > 23 or mi > 59:
            return None
        base = h * 3600 + mi * 60
        d = durations(m.group(4))
        if d is not None:
            t = base + d if m.group(3) == "+" else base - d
            day, rem = divmod(int(t), 86400)
            out = "%02d:%02d" % (rem // 3600, rem % 3600 // 60)
            if day:
                out += " (%+d day%s)" % (day, "" if abs(day) == 1 else "s")
            return out
        m2 = re.fullmatch(r"(\d{1,2}):(\d{2})", m.group(4))
        if m.group(3) == "-" and m2:
            gap = base - (int(m2.group(1)) * 3600 + int(m2.group(2)) * 60)
            return ("-" if gap < 0 else "") + hm(gap)
    return None


def parse_day(s, now):
    s = s.strip().lower()
    if s in ("today", "now"):
        return now.date()
    if s == "tomorrow":
        return now.date() + dt.timedelta(days=1)
    if s == "yesterday":
        return now.date() - dt.timedelta(days=1)
    try:
        return dt.date.fromisoformat(s)
    except ValueError:
        return None


def calendar(text, now):
    m = re.fullmatch(r"\s*(\S+)\s*([+-])\s*(.+?)\s*", text)
    if not m:
        return None
    a = parse_day(m.group(1), now)
    if a is None:
        return None
    other = parse_day(m.group(3), now)
    if other is not None and m.group(2) == "-":
        n = (a - other).days
        return "%d day%s" % (n, "" if abs(n) == 1 else "s")
    d = durations(m.group(3))
    if d is None:
        return None
    days = int(d // 86400)
    r = a + dt.timedelta(days=days if m.group(2) == "+" else -days)
    return "%s (%s)" % (r.isoformat(), r.strftime("%a"))


# ---- arithmetic ----------------------------------------------------------------------------
FUNCS = {"sqrt": math.sqrt, "sin": math.sin, "cos": math.cos, "tan": math.tan, "ln": math.log, "log": math.log10,
         "log10": math.log10, "log2": math.log2, "exp": math.exp, "abs": abs, "round": round,
         "floor": math.floor, "ceil": math.ceil}
CONST = {"pi": math.pi, "e": math.e, "tau": math.tau}
BIN = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul, ast.Div: operator.truediv,
       ast.FloorDiv: operator.floordiv, ast.Mod: operator.mod}


def walk(n):
    if isinstance(n, ast.Expression):
        return walk(n.body)
    if isinstance(n, ast.Constant) and isinstance(n.value, (int, float)) and not isinstance(n.value, bool):
        return n.value
    if isinstance(n, ast.UnaryOp) and isinstance(n.op, (ast.UAdd, ast.USub)):
        v = walk(n.operand)
        return -v if isinstance(n.op, ast.USub) else v
    if isinstance(n, ast.BinOp):
        a, b = walk(n.left), walk(n.right)
        if isinstance(n.op, ast.Pow):
            if abs(b) > 4096 or (isinstance(a, int) and isinstance(b, int) and abs(a) > 1 and abs(b) * math.log2(abs(a)) > 4096):
                raise ValueError("too large")
            return a ** b
        if type(n.op) in BIN:
            return BIN[type(n.op)](a, b)
    if isinstance(n, ast.Name) and n.id in CONST:
        return CONST[n.id]
    if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id in FUNCS and not n.keywords:
        return FUNCS[n.func.id](*[walk(x) for x in n.args])
    raise ValueError("unsupported")


def arithmetic(text):
    s = text.replace("×", "*").replace("÷", "/").replace("^", "**").replace(",", "")
    s = re.sub(r"(\d+(?:\.\d+)?)\s*%\s*of\s+", r"(\1/100)*", s)
    s = re.sub(r"(?<=\d)_(?=\d)", "", s)
    s = re.sub(r"\b(\d+(?:\.\d+)?)\s*([kKmMgG])\b", lambda m: "(%s*%s)" % (m.group(1), {"k": 1e3, "m": 1e6, "g": 1e9}[m.group(2).lower()]), s)
    if len(s) > 200 or not re.search(r"[\d]", s) and not re.search(r"\b(pi|e|tau)\b", s):
        return None
    try:
        return fmt(walk(ast.parse(s.strip(), mode="eval")))
    except (ValueError, SyntaxError, ZeroDivisionError, OverflowError, TypeError, RecursionError):
        return None


def qalc(text):
    exe = shutil.which("qalc")
    if not exe or not re.search(r"[A-Za-z]", text) or len(text) > 200:
        return None
    # only what reads as a quantity or a conversion: "db-02" or "python3" must never reach qalc
    if not (re.match(r"\s*[-+]?[\d.]", text) or re.search(r"\s(?:in|to|as)\s|->|\(", text)):
        return None
    try:
        p = subprocess.run([exe, "-t", "--", re.sub(r"\s+(?:in|as|->)\s+", " to ", text)], capture_output=True, text=True, timeout=1.5)
    except (subprocess.TimeoutExpired, OSError):
        return None
    out = p.stdout.strip()
    lines = [x for x in out.splitlines() if x.strip()]
    if p.returncode != 0 or len(lines) != 1 or re.search(r"error|warning|unknown|^\s*$", lines[0], re.I):
        return None
    if lines[0].strip().lower() == text.strip().lower():
        return None
    if re.search(r"[()]|range|[A-Za-z]{2,}\s*/\s*0\b", lines[0]) or not re.match(r"\s*[-+−]?[\d.]", lines[0]):
        return None             # qalc echoing a half-parsed expression back is not an answer
    return lines[0].strip()


def evaluate(text, now=None):
    text = (text or "").strip()
    if not text or re.fullmatch(r"[\d.,_\s]+", text):
        return None
    now = now or dt.datetime.now()
    for fn in (convert, lambda t: clock(t, now), lambda t: calendar(t, now), arithmetic):
        r = fn(text)
        if r is not None:
            return r
    return qalc(text)


def build(text, now=None):
    r = evaluate(text, now)
    if r is None:
        return {"rows": [], "hint": HINT}
    return {"rows": [{"key": "math", "title": r, "sub": text.strip(), "icon": "calculator", "score": 0.9,
                      "preview": {"head": r, "body": BODY},
                      "actions": [{"label": "Copy result", "primary": True}]}], "hint": HINT}


def main(argv):
    if len(argv) >= 2 and argv[0] == "query":
        print(json.dumps(build(" ".join(argv[1:]))))
        return 0
    print(json.dumps({"rows": [], "error": "usage: launcher_math.py query <text>"}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
