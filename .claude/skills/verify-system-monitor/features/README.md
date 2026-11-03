# System Monitor verification map

Each file is one user-facing feature of the bar widget, with the script path that proves it.

## Baseline preconditions

- Run from the repo checkout, never from `~/.config/omarchy/plugins/harshith.system-monitor`.
- `omarchy plugin validate .` exits 0.
- Evidence goes to a fresh folder given to `sample.sh`.

## Driving conventions

- The harness is `sample.sh` plus `make test`. The widget UI is not driven (see the skill's Gotchas).
- Compare base and change on the same machine in the same minute.

## Proof and skip reporting

- Proof is the command, its exit code and the evidence file.
- Report an Asahi-only path as covered by fixtures only, not as verified live.

## Feature entry contract

Each file has an H1, one paragraph, then `Sub-features`, `How to get to it (user POV)`,
`Driving it with sample.sh`, and `Gotchas`.

- [metrics.md](metrics.md): CPU, memory, load, uptime, network.
- [sensor-discovery.md](sensor-discovery.md): CPU temp, GPU, disks, platform sensors.
- [capacity.md](capacity.md): filesystem capacity section.
