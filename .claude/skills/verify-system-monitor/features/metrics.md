# Live metrics

The bar and dashboard show CPU (overall and per core), memory and swap, load, uptime and network throughput, parsed from `/proc` by `Metrics.js`.

## Sub-features

- `cpu` overall and per-core percent from two `/proc/stat` samples.
- `memory` used, total and swap from `/proc/meminfo`.
- `load-uptime` from `/proc/loadavg` and `/proc/uptime`.
- `network` default interface from `/proc/net/route`, counters from `/proc/net/dev`.

## How to get to it (user POV)

- The bar widget text (Both mode by default); left-click opens the dashboard.

## Driving it with sample.sh

Preconditions:

- Doctor passes.

- **Sample.** Run `sample.sh /tmp/vsm-metrics`. `summary.txt` has `model exit 0`.
- **Proof.** `jq '{cpuOverall,cores,memory,load,defaultInterface}' /tmp/vsm-metrics/model.json` shows a `cpuOverall` from 0 to 100, `cores` equal to `nproc`, and a non-empty `defaultInterface`.

## Gotchas

- `cpuOverall` is `-1` when there is no previous sample; `sample.sh` takes two.
- A machine without a default route gives an empty `defaultInterface`; that is correct.
