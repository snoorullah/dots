"""Half-open [start,end) datetime-span set algebra used by aggregation + reconciliation."""

def merge(spans):
    spans = sorted((s for s in spans if s[0] < s[1]))
    out = []
    for s, e in spans:
        if out and s <= out[-1][1]:
            out[-1] = (out[-1][0], max(out[-1][1], e))
        else:
            out.append((s, e))
    return out

def overlap(a, b):
    a, b = merge(a), merge(b)
    total = 0.0
    for s, e in a:
        for bs, be in b:
            lo, hi = max(s, bs), min(e, be)
            if lo < hi:
                total += (hi - lo).total_seconds()
    return total

def subtract(a, b):
    b = merge(b)
    out = []
    for s, e in merge(a):
        cur = s
        for bs, be in b:
            if be <= cur or bs >= e:
                continue
            if bs > cur:
                out.append((cur, bs))
            cur = max(cur, be)
            if cur >= e:
                break
        if cur < e:
            out.append((cur, e))
    return out
