// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// argv builders for the picker. Every call is `python3 <wp.py> <verb> ...`; the verbs are a
// whitelist, paths and names are validated here as well as in wp.py. No shell anywhere.
.pragma library

var VERBS = ["scan", "palette", "apply", "preview", "restore", "revert", "fav", "folder", "state", "shuffle-tick", "next"]

function pathOk(p) { return typeof p === "string" && p.length > 0 && p.charAt(0) === "/" && p.indexOf("\0") < 0 && p.charAt(0) !== "-" }
function outputOk(o) { return /^[A-Za-z0-9_.:-]{1,40}$/.test(String(o)) }

function wp(script, args) {
  if (!args || !args.length || VERBS.indexOf(args[0]) < 0) return null
  var out = ["python3", script]
  for (var i = 0; i < args.length; i++) out.push(String(args[i]))
  return out
}

// set a wallpaper: the image for one display or all, and which palette to follow
function apply(script, path, output, palette) {
  if (!pathOk(path)) return null
  var a = ["apply", path]
  if (output) {
    if (!outputOk(output)) return null
    a.push("--output", output)
  }
  if (palette === "wallpaper" || palette === "current" || palette === "mode") a.push("--palette", palette)
  return wp(script, a)
}

function preview(script, path) { return pathOk(path) ? wp(script, ["preview", path]) : null }
