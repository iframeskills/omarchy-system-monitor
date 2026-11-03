# Sensor discovery

`discover-sensors.sh` finds the CPU temperature input, physical disks, the best GPU and, on Asahi, the labelled platform sensors and fans; the panel shows a tile only for what it finds.

## Sub-features

- `cpu-temp` coretemp, k10temp or zenpower package input.
- `gpu` busy, temp and VRAM paths, ranked by utilization then VRAM.
- `disks` physical block devices, without loop, ram, zram, floppy or optical.
- `platform` Asahi `macsmc_hwmon` temps and power rails (fixtures only on x86).

## How to get to it (user POV)

- Open the dashboard: the temperature, GPU and disk sections appear when sensors exist.

## Driving it with sample.sh

Preconditions:

- Doctor passes.

- **Live.** Run `sample.sh /tmp/vsm-disc`. `/tmp/vsm-disc/discovery.tsv` lists `cpu_temp`, `disk` and, on blade, `gpu_busy` for `card1`.
- **Parsed.** `jq .discovery /tmp/vsm-disc/model.json` holds the same paths.
- **Vendor matrix.** Run `bash tests/discovery.test.sh`. Every line is `ok`.

## Gotchas

- The `OMARCHY_SYSMON_HWMON_ROOT` and `OMARCHY_SYSMON_DRM_ROOT` variables point the script at fixture trees; leave them unset for the live run.
