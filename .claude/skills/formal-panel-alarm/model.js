"use strict"
const fs = require("node:fs")
const path = require("node:path")

const repo = path.resolve(__dirname, "../../..")
const PROPS = ["warningThreshold", "criticalThreshold", "pressure", "warning", "critical", "heatWarnW", "heatCriticalW"]
const FUNCTIONS = ["moveCursor", "levelColor", "stressColor"]

function extractProp(text, name) {
  const m = text.match(new RegExp("^  readonly property \\w+ " + name + ": (.*)$", "m"))
  if (!m) throw new Error("not found in Panel.qml: property " + name)
  return m[1]
}

function extractFunction(text, name) {
  const start = text.indexOf("\n  function " + name + "(")
  if (start < 0) throw new Error("not found in Panel.qml: function " + name)
  const end = text.indexOf("\n  }\n", start)
  return text.slice(start + 1, end + 4)
}

function extract(text) {
  const props = {}
  for (const name of PROPS) props[name] = extractProp(text, name)
  const fns = {}
  for (const name of FUNCTIONS) fns[name] = extractFunction(text, name)
  return { props, fns }
}

function instantiate(parts, settings, metrics) {
  const scope = {
    metrics, actionCount: 2, selectedIndex: 0,
    root: { muted: "muted", urgent: "urgent", warningColor: "warn", accent: "accent", foreground: "fg", stressCriticalColor: "scrit", stressWarningColor: "swarn" },
    setting: (key, fallback) => settings[key] !== undefined ? settings[key] : fallback
  }
  const getters = {}
  for (const [name, expr] of Object.entries(parts.props)) getters[name] = new Function("scope", "with (scope) { return (" + expr + ") }")
  const proxy = new Proxy(scope, {
    has: (target, key) => key in target || key in getters || FUNCTIONS.includes(key),
    get: (target, key) => {
      if (key === Symbol.unscopables) return undefined
      if (key in getters) return getters[key](proxy)
      if (key in target) return target[key]
      return fns[key]
    },
    set: (target, key, value) => { target[key] = value; return true }
  })
  const body = Object.values(parts.fns).join("\n") + "\nreturn {" + FUNCTIONS.join(",") + "}"
  const fns = new Function("scope", "with (scope) { " + body + " }")(proxy)
  return { proxy, scope, fns }
}

const SETTING_VALUES = [undefined, 0, 50, 60, 61, 70, 90, 100, 150, "80", "", "abc", null]
const PERCENTS = [-1, 0, 59, 60, 61, 69, 70, 89, 90, 99, 100]
const TEMPS = [-1, 30, 84, 85, 94, 95, 120]
const WATTS = [-1, 0, 14, 15, 24, 25, 40]

function check(parts, limit = 5) {
  const failures = []
  const fail = (msg) => { if (failures.length < limit) failures.push(msg) }
  let cases = 0
  for (const w of SETTING_VALUES) for (const c of SETTING_VALUES) {
    const settings = { warningPercent: w, criticalPercent: c }
    const label = "settings warningPercent=" + JSON.stringify(w) + " criticalPercent=" + JSON.stringify(c)
    const base = instantiate(parts, settings, {})
    const shared = instantiate(parts, settings, {})
    const warnT = base.proxy.warningThreshold, critT = base.proxy.criticalThreshold
    if (!(isFinite(warnT) && isFinite(critT) && warnT < critT && critT >= 61))
      fail(label + ": thresholds warn=" + warnT + " crit=" + critT + " are not finite with warn < crit and crit >= 61")
    for (const cpu of PERCENTS) for (const mem of PERCENTS) for (const temp of TEMPS) for (const watts of WATTS) for (const manual of [false, true]) {
      cases++
      Object.assign(shared.scope.metrics, { cpuPercent: cpu, memoryPercent: mem, cpuTemperature: temp, gpuTemperature: -1, hottestPlatformTemp: -1, heatpipeWatts: watts, fansManual: manual })
      const p = shared.proxy
      const where = label + " cpu=" + cpu + " mem=" + mem + " cpuTemperature=" + temp + " heatpipeWatts=" + watts + " fansManual=" + manual
      const warning = p.warning, critical = p.critical
      if (critical && !warning) fail(where + ": critical without warning")
      const hot = temp >= 95 || (temp < 0 && watts >= 25)
      if (hot && !critical) fail(where + ": a reading at its hard limit does not raise critical")
      if (manual && !warning) fail(where + ": manual fan mode does not raise warning")
      if (Math.max(cpu, mem) >= critT && isFinite(critT) && !critical) fail(where + ": pressure at the critical threshold does not raise critical")
      const quiet = Math.max(cpu, mem) < warnT && temp < 85 && !(temp < 0 && watts >= 15) && !manual
      if (quiet && warning) fail(where + ": a quiet machine raises warning")
    }
    const sc = (v) => base.fns.stressColor(v)
    for (const v of PERCENTS) {
      const expected = v < 0 ? "fg" : v >= critT ? "scrit" : v >= warnT ? "swarn" : "fg"
      if (sc(v) !== expected) fail(label + ": stressColor(" + v + ") is " + sc(v) + ", expected " + expected)
    }
  }
  const cursorFails = checkCursor(parts)
  for (const f of cursorFails) fail(f)
  return { failures, cases }
}

function checkCursor(parts) {
  const out = []
  const deltas = [-2, -1, 0, 1, 2]
  const walk = (inst, seq, depth) => {
    const i = inst.scope.selectedIndex
    if (!(Number.isInteger(i) && i >= 0 && i < 2)) { out.push("cursor steps " + JSON.stringify(seq) + " give selectedIndex " + i + ", outside 0..1"); return }
    if (depth === 0) return
    for (const d of deltas) {
      const next = instantiate(parts, {}, {})
      next.scope.selectedIndex = i
      next.fns.moveCursor(d)
      walk(next, seq.concat(d), depth - 1)
    }
  }
  walk(instantiate(parts, {}, {}), [], 5)
  return out
}

const MUTANTS = [
  ["drop the critical floor of 61", (p) => { p.props.criticalThreshold = p.props.criticalThreshold.replace(", 61)", ", 0)") }],
  ["drop warn < crit clamp", (p) => { p.props.warningThreshold = p.props.warningThreshold.replace("criticalThreshold - 1", "1000") }],
  ["drop the 95 C critical limit", (p) => { p.props.critical = p.props.critical.replace("metrics.cpuTemperature >= 95 ||", "") }],
  ["drop heatpipe critical", (p) => { p.props.critical = p.props.critical.replace(/\|\| \(metrics\.cpuTemperature < 0 && metrics\.heatpipeWatts >= heatCriticalW\)/, "") }],
  ["drop fansManual warning", (p) => { p.props.warning = p.props.warning.replace(" || metrics.fansManual", "") }],
  ["heat warn above heat critical", (p) => { p.props.heatWarnW = "30" }],
  ["cursor without clamp", (p) => { p.fns.moveCursor = p.fns.moveCursor.replace(/Math\.max\(0, Math\.min\(actionCount - 1, (selectedIndex \+ delta)\)\)/, "$1") }],
  ["stressColor swaps levels", (p) => { p.fns.stressColor = p.fns.stressColor.replace("value >= criticalThreshold", "value >= warningThreshold") }]
]

function main() {
  let parts
  try { parts = extract(fs.readFileSync(path.join(repo, "Panel.qml"), "utf8")) }
  catch (e) { console.log("error: " + e.message); process.exit(2) }
  if (process.argv[2] === "--mutants") {
    const baseline = new Set(check(parts, Infinity).failures)
    let survived = 0
    for (const [name, mutate] of MUTANTS) {
      const copy = JSON.parse(JSON.stringify(parts))
      mutate(copy)
      if (JSON.stringify(copy) === JSON.stringify(parts)) { console.log("error: mutant did not apply: " + name); process.exit(2) }
      const killed = check(copy, Infinity).failures.some((f) => !baseline.has(f))
      console.log((killed ? "killed   " : "SURVIVED ") + name)
      if (!killed) survived++
    }
    process.exit(survived ? 1 : 0)
  }
  const r = check(parts)
  if (r.failures.length) {
    for (const f of r.failures) console.log("VIOLATION: " + f)
    process.exit(1)
  }
  console.log("ok: " + r.cases + " alarm cases and every cursor sequence of up to 5 steps hold")
}
main()
