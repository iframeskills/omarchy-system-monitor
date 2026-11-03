#!/usr/bin/env bash
set -uo pipefail
repo="${2:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null)}"
if [ -z "$repo" ] || [ ! -f "$repo/Metrics.js" ]; then
  echo "error: no checkout found; pass it: sample.sh <evidence-dir> <repo>" >&2
  exit 2
fi
repo="$(cd "$repo" && pwd)"
out="${1:-${TMPDIR:-/tmp}/verify-system-monitor-$(date +%s)}"
mkdir -p "$out"
cd "$repo" || exit 1
git rev-parse HEAD >"$out/revision.txt"
omarchy plugin validate . >"$out/validate.txt" 2>&1; echo "validate exit $?" | tee -a "$out/summary.txt"
bash discover-sensors.sh >"$out/discovery.tsv" 2>"$out/discovery.err"; echo "discovery exit $?" | tee -a "$out/summary.txt"
df -P -k -l -T >"$out/df.txt"
node - "$repo" "$out" <<'JS' >"$out/model.json" 2>"$out/model.err"
const fs = require("fs"), path = require("path")
const [repo, out] = process.argv.slice(2)
const M = require(path.join(repo, "Metrics.js"))
const r = p => fs.readFileSync(p, "utf8")
const stat1 = r("/proc/stat")
const t0 = Date.now(); while (Date.now() - t0 < 500) {}
const cpu = M.parseCpu(r("/proc/stat"), M.parseCpu(stat1, null).snapshot)
const discovery = M.parseDiscovery(r(path.join(out, "discovery.tsv")))
const iface = M.parseDefaultInterface(r("/proc/net/route"))
console.log(JSON.stringify({
  cpuOverall: cpu.overall, cores: cpu.cores.length,
  memory: M.parseMemory(r("/proc/meminfo")),
  load: M.parseLoad(r("/proc/loadavg")),
  uptime: M.parseUptime(r("/proc/uptime")),
  defaultInterface: iface,
  network: M.parseNetwork(r("/proc/net/dev"), iface),
  discovery,
  filesystems: M.parseFilesystems(r(path.join(out, "df.txt")))
}, null, 2))
JS
echo "model exit $?" | tee -a "$out/summary.txt"
/usr/lib/qt6/bin/qmllint Metrics.qml Panel.qml Sparkline.qml >"$out/qmllint.txt" 2>&1
echo "qmllint warnings $(grep -c '^Warning:' "$out/qmllint.txt")" | tee -a "$out/summary.txt"
echo "evidence $out"
