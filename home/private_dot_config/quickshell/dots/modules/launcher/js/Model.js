// SPDX-License-Identifier: MIT
.pragma library

// Pure logic of the launcher core: prefix matching, mode cycling, the All merge and ranking, Recents
// rows, selection that survives a re-query, and key routing. No QML types, so it runs under
// qmltestrunner. Contract: docs/shell/specs/launcher-contract.md

var WEEK = 7 * 24 * 3600;
var K = { Escape: 0x01000000, Tab: 0x01000001, Backtab: 0x01000002, Backspace: 0x01000003, Return: 0x01000004,
          Enter: 0x01000005, Up: 0x01000013, Down: 0x01000015, PageUp: 0x01000016, PageDown: 0x01000017,
          J: 0x4a, K: 0x4b, N: 0x4e, P: 0x50, D1: 0x31, D9: 0x39 };

// text starts with a provider prefix -> { pid, prefix, rest }; longest prefix wins; All has none
function matchPrefix(text, providers) {
  var best = null;
  for (var i = 0; i < providers.length; i++) {
    var p = providers[i].prefix || "";
    if (p && text.indexOf(p) === 0 && (!best || p.length > best.prefix.length))
      best = { pid: providers[i].providerId, prefix: p, rest: text.substring(p.length) };
  }
  return best;
}

function cycle(ids, cur, dir) {
  if (ids.length === 0) return cur;
  var i = ids.indexOf(cur);
  return ids[((i < 0 ? 0 : i) + dir + ids.length) % ids.length];
}

// The All merge. groups: [{ pid, weight, limit, rows }]; recents: { "pid\0key": unixSeconds }
// rank = (score ?? 0.5) * weight (+0.2 when activated in the last 7 days); stable on ties.
function rankAll(groups, recents, now) {
  var out = [], n = 0;
  for (var g = 0; g < groups.length; g++) {
    var G = groups[g], lim = G.limit === undefined ? 3 : G.limit, w = G.weight === undefined ? 1 : G.weight;
    var rows = G.rows || [];
    for (var i = 0; i < rows.length && i < lim; i++) {
      var r = rows[i], s = (r.score === undefined || r.score === null) ? 0.5 : r.score;
      var ts = recents ? recents[G.pid + "\u0000" + r.key] : 0;
      var rank = s * w + ((ts && now - ts <= WEEK) ? 0.2 : 0);
      out.push({ rank: rank, n: n++, pid: G.pid, i: i, row: r });
    }
  }
  out.sort(function (a, b) { return b.rank - a.rank || a.n - b.n; });
  return out.map(function (e) {
    var c = {};
    for (var k in e.row) c[k] = e.row[k];
    c._p = e.pid; c._i = e.i; c._k = e.row.key; c._rank = e.rank;
    return c;
  });
}

// Recents snapshot ({p,key,title,sub,icon,q}) -> a list row; Enter re-queries its provider and runs action 0
function recentRows(recents) {
  var out = [];
  for (var i = 0; i < recents.length && out.length < 8; i++) {
    var r = recents[i];
    out.push({ key: r.p + "\u0000" + r.key, title: r.title || r.key, sub: r.sub || "Recent", icon: r.icon || "clock",
               preview: { head: r.title || r.key, body: "Used before. Enter runs it again." },
               actions: [{ label: "Run again", primary: true }],
               _recent: true, _p: r.p, _k: r.key, _q: r.q || r.title || "" });
  }
  return out;
}

function recentMap(recents) {
  var m = {};
  for (var i = 0; i < recents.length; i++) m[recents[i].p + "\u0000" + recents[i].key] = recents[i].ts || 0;
  return m;
}

// after rows change: keep the selected row by key, else clamp the old index
function reselect(rows, selKey, oldIndex) {
  if (rows.length === 0) return 0;
  if (selKey) for (var i = 0; i < rows.length; i++) if (rows[i].key === selKey) return i;
  return Math.max(0, Math.min(oldIndex, rows.length - 1));
}

function move(sel, n, d) { return n === 0 ? 0 : Math.max(0, Math.min(n - 1, sel + d)); }   // wraps off

// secondary action cycling: actions[1..]; 0 = none
function nextSecondary(sec, nActions, d) {
  if (nActions < 2) return 0;
  var n = nActions - 1, i = sec < 1 ? (d > 0 ? 0 : 1) : sec;
  return ((i - 1 + d + n) % n) + 1;
}

// Esc: close the confirm card, else clear the field, else close the launcher
function escapeStep(st) { return st.confirm ? "confirm" : (st.query !== "" ? "clear" : "close"); }

// key -> action or null. st: { confirm, queryEmpty, modeIsAll, nActions }
function route(ev, st) {
  var k = ev.key, ctrl = !!ev.ctrl, shift = !!ev.shift;
  if (k === K.Escape) return { t: "escape" };
  if (k === K.Tab) return { t: shift ? "modePrev" : "modeNext" };
  if (k === K.Backtab) return { t: "modePrev" };
  if (k === K.Down || (ctrl && k === K.N)) return { t: "move", d: 1 };
  if (k === K.Up || (ctrl && k === K.P)) return { t: "move", d: -1 };
  if (k === K.PageDown) return { t: "move", d: 5 };
  if (k === K.PageUp) return { t: "move", d: -5 };
  if (k === K.Return || k === K.Enter) {
    if (st.confirm) return { t: "confirm" };
    return ctrl ? { t: "runSecondary" } : { t: "activate", a: 0 };
  }
  if (st.confirm) return null;
  if (ctrl && k >= K.D1 && k <= K.D9) return { t: "activate", a: k - K.D1 };
  if (ctrl && k === K.J) return { t: "secondary", d: 1 };
  if (ctrl && k === K.K) return { t: "secondary", d: -1 };
  if (k === K.Backspace && st.queryEmpty && !st.modeIsAll) return { t: "backMode" };
  return null;
}

function statusLine(toast, busy, rowsEmpty, hint) {
  if (toast) return toast;
  if (busy) return "Searching.";
  if (rowsEmpty && hint) return hint;
  return "Type a prefix, or press Tab to change mode.";
}

// 0..1: 1 exact, .9 prefix, .75 substring, up to .6 ordered subsequence, 0 no match. Same scale as the Python helpers.
function fuzzy(q, s) {
  q = String(q || "").toLowerCase().trim(); s = String(s || "").toLowerCase();
  if (q === "") return 0.5;
  if (s === q) return 1;
  if (s.indexOf(q) === 0) return 0.9;
  if (s.indexOf(q) >= 0) return 0.75;
  var i = 0;
  for (var j = 0; j < s.length && i < q.length; j++) if (s.charAt(j) === q.charAt(i)) i++;
  return i === q.length ? 0.3 + 0.3 * q.length / Math.max(s.length, 1) : 0;
}

// The `Math` provider type shadows the JS Math object in the providers directory and Launcher.qml,
// so those files take these two from here.
function nowSec() { return Math.floor(Date.now() / 1000); }
function maxOf() { return Math.max.apply(null, arguments); }
function centred(outer, inner) { return Math.max(0, (outer - inner) / 2); }
