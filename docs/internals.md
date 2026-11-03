# Internals

This page explains the design choices in the code. The README describes what
the plugin does for a user.

## Missing readings

Every parser in `Metrics.js` returns `-1` for a reading that is missing,
blank or not a number. The panel prints an em dash for `-1`. A blank sysfs
read never becomes `0`, because `0%` GPU load claims that the GPU is idle,
and `0 W` claims that a power rail is at rest. A real `0` stays `0`.

## Discovery records

`discover-sensors.sh` prints one tab-separated record per line. The first
field is the key. `parseDiscovery` in `Metrics.js` reads the records:

| Key | Fields after the key | Rule |
| --- | --- | --- |
| `platform_sensor` | path, kind, label | Kind is `temp` or `power`, other kinds are dropped. The label is everything after the kind, so a tab in a label stays. |
| `fan` | input path, index, label, min, max | The bounds are the last two fields, so a tab in a label stays. A record with bounds that are not numbers is dropped whole. The target path is the input path with `_input` changed to `_target`. |

## Units

Platform sensors follow the hwmon ABI: temperatures in milli-degrees Celsius
and power in micro-watts. `parseSensorValue` scales them to °C and W. The
`amdgpu` busy counter is an integer percentage, and the VRAM counters are
byte totals.

## Filesystem capacity

`parseFilesystems` reads `df -P -k -l -T`: POSIX columns, 1K blocks, local
filesystems only, with a type column. The `-l` flag also keeps a stale
network mount from hanging `df`.

- A row must have a type in `ON_DISK_FILESYSTEM_ALLOWLIST`. An allowlist
  keeps out the growing set of pseudo filesystems (tmpfs, overlay, squashfs,
  cgroup) without a name for each one.
- The root filesystem always gets a row, so its meter cannot break.
- Rows on one source device (btrfs subvolumes, bind mounts) report the same
  free space. They collapse to the shortest mount path.

## Tooltip markup

`WidgetButton` gives tooltip strings to a shared shell `Text` item that uses
Qt's automatic rich-text detection. `escapeMarkup` escapes the strings at
that point, so a label from the configuration cannot become HTML. For the
same reason, the capacity row label sets `textFormat: Text.PlainText`,
because a mount path from `df` can contain markup.

## Chart scale

`peakValue` gives the peak of a rolling history window. The panel pins the
sparkline scale to that peak, so the chart and its printed scale label show
the same number.

## Sensor discovery

`discover-sensors.sh` reads `OMARCHY_SYSMON_HWMON_ROOT` and `OMARCHY_SYSMON_DRM_ROOT` when they are set. `tests/discovery.test.sh` uses them to run the discovery against fixture sysfs trees for hardware that the machine does not have. Its exact-line checks compare in bash and do not pipe into `grep -q`: with `pipefail`, the early exit of `grep -q` kills the probe with SIGPIPE, and a match reports as a failure.

Apple Silicon (Asahi Linux) has no CPU package sensor, because the SoC die temperatures stay in the PMU. The `macsmc_hwmon` driver gives labelled platform temperatures, power rails and fans instead, and the script lists all of them. The script trims whitespace at the two ends of a sysfs label, because labels can carry padding. An input without a label gets a numbered name, such as `Temperature 3` or `Power 2`.

Each GPU vendor exposes a different set of sensors, so the script probes each sensor on its own:

| Driver | Readable in sysfs |
|---|---|
| amdgpu | `gpu_busy_percent`, hwmon `temp1_input`, `mem_info_vram_*` |
| i915 | hwmon `temp1_input` only; utilisation needs the PMU or per-client fdinfo |
| xe | hwmon `temp2_input` only; the xe hwmon ABI starts the package temperature at 2 |
| nouveau | hwmon `temp1_input` only |
| NVIDIA proprietary | nothing; every reading needs NVML, so a helper process per sample, which the plugin does not start |

The script tries `temp1_input` first and `temp2_input` second. It skips a card with no utilisation and no temperature, because that card would show only dashes. A card with utilisation wins, then the card with the most video memory. This keeps the discrete card on hybrid systems without device IDs, and still reports a card that has only a temperature.
