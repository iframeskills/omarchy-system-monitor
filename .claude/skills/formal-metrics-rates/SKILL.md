---
name: formal-metrics-rates
description: "Bounded exhaustive check of the network and disk rate logic and the history buffers in Metrics.qml (handleNetwork, handleDisk, onActiveInterfaceChanged, appendHistory). Use when a change touches Metrics.qml or the parsers it calls in Metrics.js, or when the gate runs the check."
metadata:
  covers: "Metrics.qml Metrics.js"
  sync: 2deaa50
  check: ".claude/skills/formal-metrics-rates/check"
---

# Formal check: Metrics.qml rates and histories

The promise: the bar never shows a negative, infinite or cross-interface network or disk rate, and the sparkline history never holds bad or stale points.
The harm if it breaks: after a counter reset, a suspend or a switch of the network interface, the widget shows nonsense such as `-10 kB/s` or a huge spike, and the sparkline scale is ruined for two minutes.

## How it works

`model.js` cuts the real source of `appendHistory`, `handleNetwork`, `handleDisk` and the `onActiveInterfaceChanged` body out of `Metrics.qml`, and runs it in node against the real `Metrics.js` parsers, with a fake `Date.now`.
It runs every sequence of up to 6 steps from this alphabet (55,986 sequences, under 1 s):

- a sample after 1 s, 0 ms or 40 s, with the counters going up;
- a counter reset to 0;
- a sample where the interface line is missing from `/proc/net/dev`;
- a switch of `activeInterface` between `A` and `B`.

After each sample it compares the four rates with an independent spec in `expectedRates`. A rate comes only from two samples of the same interface, 0 to 30 s apart, with non-negative deltas. Otherwise the previous rate stays, and a missing interface or a switch gives `-1`. It also checks that each history holds finite values of 0 or more, in time order, within `historyWindowMs`, at most 130 points, and is empty after a switch.

## Run it

- `.claude/skills/formal-metrics-rates/check` exits 0 if every property holds, 1 with a step list if one breaks, and 2 if node is missing or a function can no longer be found in `Metrics.qml`.
- `DEPTH=7 .claude/skills/formal-metrics-rates/check` runs 335,922 sequences in about 13 s.
- `.claude/skills/formal-metrics-rates/check --mutants` breaks 8 guards in the extracted code (negative delta, same interface, 30 s gap, zero elapsed, snapshot and history reset on switch, missing interface, window trim). Each must print `killed`. Run it after you change the model.

Tool: plain node (the repo already needs it for `make test`), because QML has no verifier and the logic is plain JavaScript. This is bounded exhaustive testing of the real code, not a proof.

## Read a failure

A `VIOLATION` prints the steps in order. Replay them by hand against `handleNetwork` or `handleDisk`.

- If the code computes a rate from data that the promise forbids, it is a real bug. Report it; do not change the spec to pass.
- If exit 2 says that a block is not found, a function was renamed or reindented. Update `FUNCTIONS`, `HANDLERS` or `extractBlock` in `model.js`.
- If the code is right and the spec is wrong (for example an intended new rule), change `expectedRates` and say why in the commit body. Then run `--mutants`.

## Scope

Verified: the rate and history state of network and disk under the step alphabet above, up to 6 steps, one disk device.
Not covered: `handleCpu`, memory, GPU, fans, sensor discovery, `parseFanConfig`, `filesystemProc`, timer cadence, `recordThermal`, and the real QML binding engine. The model calls `onActiveInterfaceChanged` itself; in QML it fires only when the bound value changes.

The same-interface test in `handleNetwork` is redundant while `onActiveInterfaceChanged` clears `networkSnapshot`. One mutant removes both, so that a removal of one stays safe and a removal of both fails.

## Open questions

- After a rejected pair (counter reset, gap over 30 s) the previous rate stays on screen for one more cycle. The check treats this as intended. If it is not, change the spec to `-1` and report the code.
- A counter that wraps at 2^32 or 2^64 is treated like a reset. Is this right on 32-bit counters?

## Sync

`sync` is the commit at which the model was last confirmed against `Metrics.qml`. Move it only after the check and `--mutants` both pass on the new code and the scope above is still true.
