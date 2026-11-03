---
name: verify-system-monitor
description: "Verify omarchy-system-monitor, an Omarchy shell bar-widget plugin (QML + Metrics.js + discover-sensors.sh). Runs the manifest validation, live sensor discovery, the Metrics.js parsers over this machine's /proc and sysfs, and qmllint, and saves the evidence. Use to prove that a change keeps the behaviour, for example in a gate run."
---

# Verify System Monitor

The plugin is a bar widget that the Omarchy shell (Quickshell) loads from `Panel.qml`.
`Metrics.qml` reads `/proc` and sysfs with `FileView`, runs `discover-sensors.sh` and
`df -P -k -l -T`, and parses all text with `Metrics.js`. A script can drive every part except the
rendered widget: that part needs the real shell (see Gotchas).

## Launch

Nothing to start. Each run is read-only and works from the checkout, never from the installed copy
in `~/.config/omarchy/plugins/harshith.system-monitor`, which is the user's own instance.

Needs `omarchy`, `node` 18.1+, `jq`, `make` and `/usr/lib/qt6/bin/qmllint`.

## Doctor

```sh
git rev-parse HEAD && omarchy plugin validate . && node -e 'require("./Metrics.js")'
```

All three exit 0 from the repo root, so the checkout is the build you mean to prove.

## Drive

1. `make test` from the repo root: the manifest JSON, `tests/model.test.js` and the
   discovery fixtures in `tests/discovery.test.sh`. This is what CI runs.
2. `.claude/skills/verify-system-monitor/sample.sh [evidence-dir]` drives the same paths that the
   widget uses, on the live machine:
   - `omarchy plugin validate .`
   - `bash discover-sensors.sh` against the real `/sys` (TSV lines such as `cpu_temp`, `disk`,
     `gpu_busy`).
   - `Metrics.js` parsers over the real `/proc/stat` (two samples 0.5 s apart), `/proc/meminfo`,
     `/proc/loadavg`, `/proc/uptime`, `/proc/net/route`, `/proc/net/dev`, the discovery output
     and the `df` output, written as `model.json`.
   - `qmllint` over the three QML files, with the count of `Warning:` lines.
3. For a behaviour-neutral change, run `sample.sh` on the base commit and on the change, and
   compare. `discovery.tsv` must be identical, `model.json` must have the same keys and the same
   discovery paths (live numbers differ), and the qmllint warning count must not rise.
   Make a base checkout with `git worktree add /tmp/vsm-base <base-sha>`, run
   `/tmp/vsm-base/.claude/skills/verify-system-monitor/sample.sh` only if the base has the
   skill; otherwise copy `sample.sh` into it first.

Feature recipes: [features/README.md](features/README.md).

## Evidence

`sample.sh` writes to the folder that you give it (default `/tmp/verify-system-monitor-<epoch>`):
`revision.txt`, `summary.txt`, `validate.txt`, `discovery.tsv`, `df.txt`, `model.json`,
`qmllint.txt`. Keep the `make test` output next to it. Quote `summary.txt` in the report.

## Cleanup

`sample.sh` starts no process. Remove a base worktree with `git worktree remove /tmp/vsm-base`.
Keep the evidence folder.

## Gotchas

- `qmllint` reports about 200 warnings at commit 9e9aac2, because it cannot resolve the
  `qs.Commons` and `qs.Ui` imports of the Omarchy shell. Compare counts; do not demand zero.
- The rendered widget, clicks and the `R`/`B` keys are not driven. Open question: can a second
  Quickshell instance load this plugin in isolation, without the user's running shell? Until
  someone proves that, a UI change needs a manual check by the user after
  `omarchy restart shell` with the plugin linked.
- Fan control (`sudo -n /usr/local/bin/asahi-fanctl`) and the `macsmc_hwmon` platform sensors
  exist only on Apple Silicon under Asahi. On blade (x86, AMD GPU) only the fixtures in
  `tests/discovery.test.sh` cover them. Never run `asahi-fanctl` with a mode argument.
- Live numbers change between runs; compare structure and paths, not values.
