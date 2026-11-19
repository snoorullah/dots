#!/usr/bin/env bash
# icons: every icon name the shell passes to Icon/Glyph resolves in the dots-icon-font
# registry, and the generated PhosphorIcons.qml has not drifted from its generator.
#   0  generator input: codepoints.tsv exists and lists names
#   1  migrated files: every name resolves in PhosphorIcons.qml's table (strict)
#   2  other files: unresolved names are listed as WARN (legacy, owned by later units)
#   3  PhosphorIcons.qml is byte-identical to a fresh tools/gen-phosphor-qml.py run
#   4  PhosphorIcons.qml uses hex literals only (no plane-16 char, no \u escape)
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
mod="$root/home/private_dot_config/quickshell/dots/modules"
tsv="$root/nix/pkgs/dots-icon-font/codepoints.tsv"
gen="$root/tools/gen-phosphor-qml.py"
out="$mod/common/PhosphorIcons.qml"
fails=0
ok()   { echo "PASS $*"; }
bad()  { echo "FAIL $*"; fails=$((fails + 1)); }

# Files whose call sites are fully migrated to Phosphor names.
STRICT="quick/QuickPanel.qml osd/Osd.qml bar/items/Volume.qml calendar/CalendarPopout.qml
notif/NotifCard.qml media/MediaPopout.qml overview/OverviewCard.qml overview/pages/Item.qml
overview/pages/Focus.qml overview/pages/Today.qml"

if [ -s "$tsv" ] && grep -qv '^#' "$tsv"; then ok "codepoints.tsv present (generator input)"; else bad "codepoints.tsv missing or empty"; fi

res="$(STRICT="$STRICT" python3 -I - "$mod" "$out" <<'PY'
import os, re, sys
mod, qml = sys.argv[1], sys.argv[2]
strict = set(os.environ["STRICT"].split())
# Resolve against the generated table the shell actually reads, not the TSV.
names = set(re.findall(r'^\s*"([a-z][a-z0-9_-]*)"\s*:\s*\[', open(qml).read() if os.path.isfile(qml) else "", re.M))
if not names:
    print("BAD " + os.path.relpath(qml, mod) + " <no icon table found>")
lit0 = re.compile(r'"([a-z][a-z0-9_-]*)"')
class lit:
    @staticmethod
    def findall(s): return lit0.findall(re.sub(r'[!=]==?\s*"[^"]*"', "", s))
for dp, dn, fn in os.walk(mod):
    dn[:] = [d for d in dn if d != "tst"]
    for f in fn:
        if not f.endswith(".qml"): continue
        p = os.path.join(dp, f); rel = os.path.relpath(p, mod)
        src = open(p).read(); found = []
        for m in re.finditer(r'\b(?:Icon|Glyph)\s*\{', src):
            i, d = m.end(), 1
            while i < len(src) and d:
                d += (src[i] == "{") - (src[i] == "}"); i += 1
            for ln in src[m.end():i].splitlines():
                if re.match(r'\s*(name|text)\s*:', ln): found += lit.findall(ln)
        for ln in src.splitlines():
            if re.match(r'\s*(?:\{\s*)?icon\s*:', ln) or re.search(r'[{,;]\s*icon\s*:', ln):
                found += lit.findall(re.split(r',\s*[a-z]+\s*:', ln.split("icon:", 1)[1])[0])
        for n in sorted(set(found)):
            if n in names: continue
            print(("BAD " if rel in strict else "WARN ") + rel + " " + n)
PY
)"
bads="$(printf '%s\n' "$res" | grep '^BAD ' || true)"
warns="$(printf '%s\n' "$res" | grep -c '^WARN ' || true)"
if [ -z "$bads" ]; then ok "migrated files: every icon name resolves"; else bad "unresolved icon names"; echo "$bads"; fi
echo "INFO $warns unresolved legacy names in files owned by later units"

if [ -f "$gen" ] && python3 -I "$gen" --stdout 2>/dev/null | cmp -s - "$out"; then ok "PhosphorIcons.qml matches generator"
else bad "PhosphorIcons.qml missing or drifted from tools/gen-phosphor-qml.py"; fi

if [ -f "$out" ] && ! LC_ALL=C.UTF-8 grep -qP '[\x{100000}-\x{10FFFD}]|\\u' "$out" && grep -q 'String.fromCodePoint' "$out"; then
  ok "PhosphorIcons.qml: hex literals via String.fromCodePoint only"
else bad "PhosphorIcons.qml has a literal plane-16 char or \\u escape"; fi

[ "$fails" -eq 0 ] && { echo "icons: OK"; exit 0; } || { echo "icons: $fails FAIL"; exit 1; }
