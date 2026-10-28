#!/usr/bin/env python3
"""Stub Theme vs the real theme/Tokens.qml, for tests/overview-ui.sh.

  agree.py render <palette.yaml> <Palette.qml.tmpl> <out Palette.qml>
  agree.py check  <palette.yaml> <agree.log>

render fills the real palette template from the same palette.yaml chezmoi uses.
check parses the `AGREE {json}` line Agree.qml printed and compares, key for key:
the stub palette against the yaml, then every colour / alpha / radius / space / font /
bar / motion token the real Tokens defines against the stub's. Tokens only the stub
has (a key the overview needs that T2 has not shipped yet) are listed, not failed.
"""
import json
import re
import sys


def palette(path):
    out, inside = {}, False
    for line in open(path):
        if re.match(r"^palette:\s*$", line):
            inside = True
            continue
        if inside:
            m = re.match(r'^  ([a-z]+): "(#[0-9a-fA-F]{6})"', line)
            if m:
                out[m.group(1)] = m.group(2).lower()
            elif re.match(r"^\S", line) or re.match(r"^  [a-z]+:\s*$", line):
                break
    return out


def render(yaml, tmpl, dest):
    p = palette(yaml)
    text = re.sub(r"\{\{\s*\.palette\.(\w+)\s*\}\}", lambda m: p[m.group(1)], open(tmpl).read())
    open(dest, "w").write(text)


def check(yaml, log):
    line = next(l for l in open(log) if "AGREE " in l)
    d = json.loads(line.split("AGREE ", 1)[1])
    stub, real, fails, compared, extra = d["stub"], d["real"], [], 0, []
    yp = palette(yaml)
    for k, v in yp.items():
        if stub["palette"].get(k, "").lower() != v:
            fails.append("palette.%s: stub %s, palette.yaml %s" % (k, stub["palette"].get(k), v))
    for group in ("color", "alpha", "radius", "space", "bar", "motion"):
        for k, v in real[group].items():
            if k in ("easeIn", "easeOut"):
                continue          # real carries curve names, the stub the Easing enum
            compared += 1
            sv = stub[group].get(k)
            if isinstance(v, str) and isinstance(sv, str):
                same = v.lower() == sv.lower()
            else:
                same = v == sv
            if not same:
                fails.append("%s.%s: stub %s, real %s" % (group, k, sv, v))
        extra += ["%s.%s" % (group, k) for k in stub[group] if k not in real[group]]
    for k, v in real["font"].items():
        if k == "size":
            for kk, vv in v.items():
                compared += 1
                if stub["font"]["size"].get(kk) != vv:
                    fails.append("font.size.%s: stub %s, real %s" % (kk, stub["font"]["size"].get(kk), vv))
        else:
            compared += 1
            if stub["font"].get(k) != v:
                fails.append("font.%s: stub %s, real %s" % (k, stub["font"].get(k), v))
    for f in fails:
        print("  " + f)
    if extra:
        print("  stub-only tokens (not in the real Tokens yet): " + ", ".join(extra))
    print("%s stub Theme agrees with the real Tokens on %d keys" % ("PASS" if not fails else "FAIL", compared)
          if not fails else "FAIL stub Theme disagrees with the real Tokens on %d of %d keys" % (len(fails), compared))
    return 1 if fails else 0


if __name__ == "__main__":
    if sys.argv[1] == "render":
        render(*sys.argv[2:5])
    else:
        sys.exit(check(*sys.argv[2:4]))
