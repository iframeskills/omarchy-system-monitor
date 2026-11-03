"use strict"
const fs = require("node:fs")
const path = require("node:path")

const repo = path.resolve(__dirname, "../../..")
const Model = require(path.join(repo, "Metrics.js"))

const FUNCTIONS = ["appendHistory", "handleNetwork", "handleDisk"]
const HANDLERS = ["onActiveInterfaceChanged"]
const STATE = {
  historyWindowMs: 120000, activeInterface: "A", diskDevices: ["sda"],
  networkSnapshot: null, diskSnapshot: null,
  networkDownBps: -1, networkUpBps: -1, diskReadBps: -1, diskWriteBps: -1,
  networkDownHistory: [], networkUpHistory: []
}

function extractBlock(text, header) {
  const start = text.indexOf("\n  " + header)
  if (start < 0) throw new Error("not found in Metrics.qml: " + header)
  const end = text.indexOf("\n  }\n", start)
  return text.slice(start + 1, end + 4)
}

function extract(text) {
  const parts = {}
  for (const name of FUNCTIONS) parts[name] = extractBlock(text, "function " + name + "(")
  for (const name of HANDLERS) {
    const block = extractBlock(text, name + ": {")
    parts[name] = "function " + name + "() " + block.slice(block.indexOf("{"))
  }
  return parts
}

function instantiate(parts) {
  const clock = { now: 0 }
  const scope = Object.assign({}, JSON.parse(JSON.stringify(STATE)))
  const proxy = new Proxy(scope, {
    has: (target, key) => key in target || FUNCTIONS.includes(key) || HANDLERS.includes(key) || key === "Model" || key === "Date",
    get: (target, key) => key === "Model" ? Model : key === "Date" ? { now: () => clock.now } : key === Symbol.unscopables ? undefined : target[key] !== undefined ? target[key] : fns[key],
    set: (target, key, value) => { target[key] = value; return true }
  })
  const body = Object.values(parts).join("\n") +
    "\nreturn {" + FUNCTIONS.concat(HANDLERS).join(",") + "}"
  const fns = new Function("scope", "with (scope) { " + body + " }")(proxy)
  return { scope, fns, clock }
}

function netText(iface, rx, tx) {
  if (iface === null) return "lo: 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0"
  return iface + ": " + rx + " 0 0 0 0 0 0 0 " + tx + " 0 0 0 0 0 0 0"
}
function diskText(r, w) { return "   8       0 sda 0 0 " + r + " 0 0 0 " + w + " 0 0 0 0" }

const STEPS = [
  { name: "sample after 1s, counters +1000", dt: 1000, inc: 1000 },
  { name: "sample after 0ms, counters +1000", dt: 0, inc: 1000 },
  { name: "sample after 40s (suspend), counters +1000", dt: 40000, inc: 1000 },
  { name: "counters reset to 0, sample after 1s", dt: 1000, reset: true },
  { name: "interface line missing, sample after 1s", dt: 1000, missing: true },
  { name: "switch interface A<->B", swap: true }
]

function run(parts, sequence) {
  const { scope, fns, clock } = instantiate(parts)
  const counters = { A: 5000, B: 900000, disk: 100 }
  let accepted = null
  let previous = { down: -1, read: -1 }
  for (let s = 0; s < sequence.length; s++) {
    const step = STEPS[sequence[s]]
    if (step.swap) {
      scope.activeInterface = scope.activeInterface === "A" ? "B" : "A"
      fns.onActiveInterfaceChanged()
      if (accepted) accepted.net = null
      previous.down = -1
    } else {
      clock.now += step.dt
      const iface = scope.activeInterface
      if (step.reset) { counters[iface] = 0; counters.disk = 0 }
      else if (!step.missing) { counters[iface] += step.inc; counters.disk += step.inc }
      fns.handleNetwork(netText(step.missing ? null : iface, counters[iface], counters[iface] * 2))
      fns.handleDisk(diskText(counters.disk, counters.disk))
      const current = { net: step.missing ? null : { iface, rx: counters[iface], time: clock.now }, disk: { bytes: counters.disk * 512, time: clock.now } }
      const expected = expectedRates(accepted, current, previous)
      const failure = checkInvariants(scope, expected)
      if (failure) return { sequence, failure }
      previous = { down: scope.networkDownBps, read: scope.diskReadBps }
      accepted = current
    }
    if (scope.activeInterface !== "A" && scope.activeInterface !== "B") return { sequence, failure: "bad interface" }
    if (step.swap) {
      if (scope.networkDownBps !== -1 || scope.networkUpBps !== -1) return { sequence, failure: "rate survives an interface switch" }
      if (scope.networkDownHistory.length || scope.networkUpHistory.length) return { sequence, failure: "history survives an interface switch" }
    }
  }
  return null
}

function rate(prior, now, field, extra) {
  if (!prior) return null
  const elapsed = (now.time - prior.time) / 1000
  if (!(elapsed > 0 && elapsed < 30) || !extra || now[field] - prior[field] < 0) return null
  return (now[field] - prior[field]) / elapsed
}

function expectedRates(prior, current, previous) {
  const p = prior || { net: null, disk: null }
  const down = current.net ? rate(p.net, current.net, "rx", p.net && p.net.iface === current.net.iface) : -1
  const read = rate(p.disk, current.disk, "bytes", true)
  return { down: down === null ? previous.down : down, read: read === null ? previous.read : read }
}

function checkInvariants(scope, expected) {
  for (const key of ["networkDownBps", "networkUpBps", "diskReadBps", "diskWriteBps"]) {
    const v = scope[key]
    if (!(v === -1 || (Number.isFinite(v) && v >= 0))) return key + " is " + v
  }
  if (scope.networkDownBps !== expected.down) return "networkDownBps is " + scope.networkDownBps + ", spec says " + expected.down
  if (scope.diskReadBps !== expected.read) return "diskReadBps is " + scope.diskReadBps + ", spec says " + expected.read
  for (const h of [scope.networkDownHistory, scope.networkUpHistory]) {
    if (h.length > 130) return "history longer than 130"
    for (let i = 0; i < h.length; i++) {
      if (!(Number.isFinite(h[i].value) && h[i].value >= 0)) return "history holds " + h[i].value
      if (i && h[i].time < h[i - 1].time) return "history out of order"
      if (h[h.length - 1].time - h[i].time > scope.historyWindowMs) return "history older than the window"
    }
  }
  return null
}

function explore(parts, depth) {
  let count = 0
  const seq = []
  function walk() {
    if (seq.length) {
      count++
      const bad = run(parts, seq)
      if (bad) return bad
    }
    if (seq.length === depth) return null
    for (let i = 0; i < STEPS.length; i++) {
      seq.push(i)
      const bad = walk()
      if (bad) return bad
      seq.pop()
    }
    return null
  }
  return { bad: walk(), count }
}

const MUTANTS = [
  ["no negative-delta guard (counter reset)", "handleNetwork", "&& rxDelta >= 0 && txDelta >= 0", ""],
  ["no same-interface guard and switch keeps the snapshot", "handleNetwork", "networkSnapshot && networkSnapshot.interfaceName === activeInterface", "networkSnapshot", "onActiveInterfaceChanged", "networkSnapshot = null", "networkSnapshot = networkSnapshot"],
  ["no 30 s gap guard", "handleNetwork", "&& elapsed < 30", ""],
  ["no zero-elapsed guard", "handleDisk", "elapsed > 0 && ", ""],
  ["switch keeps the old snapshot", "onActiveInterfaceChanged", "networkSnapshot = null", "networkSnapshot = networkSnapshot"],
  ["switch keeps the history", "onActiveInterfaceChanged", "networkDownHistory = []", "networkDownHistory = networkDownHistory"],
  ["missing interface keeps the rate", "handleNetwork", "networkDownBps = -1\n", ""],
  ["history window not trimmed", "appendHistory", "current[i].time >= cutoff", "true"]
]

function main() {
  const depth = Number(process.env.DEPTH || 6)
  let text
  try {
    text = fs.readFileSync(path.join(repo, "Metrics.qml"), "utf8")
  } catch (e) { console.log("error: cannot read Metrics.qml: " + e.message); process.exit(2) }
  let parts
  try { parts = extract(text) } catch (e) { console.log("error: " + e.message + "; the model needs updating"); process.exit(2) }

  if (process.argv.includes("--mutants")) {
    let survived = 0
    for (const [label, ...edits] of MUTANTS) {
      const mutated = Object.assign({}, parts)
      for (let e = 0; e < edits.length; e += 3) {
        const [part, from, to] = edits.slice(e, e + 3)
        if (!mutated[part].includes(from)) { console.log("error: mutant text gone: " + label); process.exit(2) }
        mutated[part] = mutated[part].replace(from, to)
      }
      const { bad } = explore(mutated, depth)
      console.log((bad ? "killed  " : "SURVIVED") + "  " + label + (bad ? "  (" + bad.failure + ")" : ""))
      if (!bad) survived++
    }
    process.exit(survived ? 1 : 0)
  }

  const { bad, count } = explore(parts, depth)
  if (!bad) { console.log("ok: rate and history properties hold for all " + count + " step sequences up to length " + depth); process.exit(0) }
  console.log("VIOLATION: " + bad.failure)
  bad.sequence.forEach((i, n) => console.log("  " + (n + 1) + ". " + STEPS[i].name))
  process.exit(1)
}

main()
