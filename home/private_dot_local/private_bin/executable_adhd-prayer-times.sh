#!/usr/bin/env bash
# adhd-prayer-times.sh — regenerate ~/.config/adhd/prayer-times.conf OFFLINE.
#
# Calculated adhan times: Hyderabad · Hanafi · University of Islamic Sciences
# (Karachi) method, computed locally with adhanpy (no network, no location sent).
# IQAMAH (congregation) times — when you actually pray — are derived from
# ~/.config/adhd/iqamah.conf (user-edited ~monthly from the masjid timetable).
# The focus daemon scaffolds blocks around IQAMAH; calculated adhan is kept as a
# reference comment. Edit location constants below to change city/convention.
set -euo pipefail

LAT=17.3850
LON=78.4867
TZ="Asia/Kolkata"
METHOD=KARACHI      # CalculationMethod name (KARACHI = University of Islamic Sciences)
MADHAB=HANAFI       # HANAFI (later Asr) or SHAFI

VDIR="$HOME/.local/share/adhd/venv"
CONF="$HOME/.config/adhd/prayer-times.conf"
IQCONF="$HOME/.config/adhd/iqamah.conf"
mkdir -p "$(dirname "$CONF")"

# one-time bootstrap (needs network once); fully offline thereafter
if [ ! -x "$VDIR/bin/python" ]; then
    /usr/bin/python3 -m venv "$VDIR"
    "$VDIR/bin/pip" install -q --disable-pip-version-check adhanpy
fi

"$VDIR/bin/python" - "$LAT" "$LON" "$TZ" "$METHOD" "$MADHAB" "$CONF" "$IQCONF" <<'PY'
import sys, re
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
from adhanpy.PrayerTimes import PrayerTimes
from adhanpy.calculation.CalculationMethod import CalculationMethod
from adhanpy.calculation.CalculationParameters import CalculationParameters
from adhanpy.calculation.Madhab import Madhab

lat, lon, tzname, method, madhab, conf, iqconf = (
    float(sys.argv[1]), float(sys.argv[2]), sys.argv[3], sys.argv[4],
    sys.argv[5], sys.argv[6], sys.argv[7])
tz = ZoneInfo(tzname)
now = datetime.now(tz)
params = CalculationParameters(method=getattr(CalculationMethod, method))
params.madhab = getattr(Madhab, madhab)
pt = PrayerTimes((lat, lon), now, calculation_parameters=params, time_zone=tz)
adhan = {"Fajr": pt.fajr, "Dhuhr": pt.dhuhr, "Asr": pt.asr,
         "Maghrib": pt.maghrib, "Isha": pt.isha}

# Parse iqamah.conf: "<Prayer> HH:MM" (absolute) or "<Prayer> +N"/"N" (offset min).
iq_cfg = {}
try:
    for line in open(iqconf):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 1)
        if len(parts) == 2:
            iq_cfg[parts[0].capitalize()] = parts[1].strip()
except FileNotFoundError:
    pass

def resolve(name, a):
    v = iq_cfg.get(name)
    if not v:
        return a, "(= adhan; set in iqamah.conf)"
    if re.fullmatch(r"\d{1,2}:\d{2}", v):                      # absolute HH:MM
        h, m = map(int, v.split(":"))
        return a.replace(hour=h, minute=m, second=0, microsecond=0), "absolute"
    m = re.fullmatch(r"\+?(-?\d+)", v)                          # +N offset minutes
    if m:
        return a + timedelta(minutes=int(m.group(1))), f"adhan+{m.group(1)}m"
    return a, "(unparsed; = adhan)"

hdr = [
    f"# auto-generated {now:%Y-%m-%d} — {tzname} · {madhab.title()} · {method.title()} method",
    "# Values below are IQAMAH (congregation) times the focus daemon uses.",
    "# Edit ~/.config/adhd/iqamah.conf to adjust; regenerated daily by the timer.",
]
rows = []
for n in ("Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"):
    iq, how = resolve(n, adhan[n])
    rows.append(f"{n} {iq:%H:%M}    # adhan {adhan[n]:%H:%M} · {how}")
open(conf, "w").write("\n".join(hdr + rows) + "\n")
print("wrote", conf)
PY
