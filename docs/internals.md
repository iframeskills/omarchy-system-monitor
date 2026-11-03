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

## Sparkline

`Sparkline.qml` draws a rolling time series in one of two shapes:

- Single: `points` as a line over a fill, which grows up from the bottom
  edge. `gridLevels` draws faint rules at fractions of full scale, so a
  chart that is mostly idle shows its headroom and does not look empty.
- Mirror: `points` above a center axis and `mirrorPoints` below it, on one
  shared scale. The network send and receive pair uses it, so the direction
  stays visible and the two values are not summed.

`fixedMaximum` pins the vertical scale, so the caller can label the chart
with the number that it draws against. A value of `0` or less scales to the
window peak. `growsUpFromAxis` and `growsDownFromAxis` give the direction of
each half.

## Metrics.qml

`Metrics.qml` holds the state and does all sampling.

### Sampling cadence

- VRAM use is read only while the panel is open. The value is only seen
  then, and the closed cadence would cost two sysfs reads for nothing.
  Total VRAM does not change for the life of the card, so discovery reads it
  once.
- Fan speeds follow the shared cadence also while the panel is closed,
  because the history chart needs them and the sysfs reads are cheap.
- The thermal history records one point per sample of the value that the
  HEAT tile shows: package temperature, else heatpipe watts, else the
  warmest platform temperature. A change of unit clears the history.
- The two halves of a mirrored chart share one scale, so `networkPeak` is
  the peak of the pair. The panel prints the number that it draws against.

### Platform sensors and fans

- Each discovered sensor and fan gets its own `FileView` in an
  `Instantiator` with zero-size `Item` delegates, which keeps them out of
  the visual tree. The shell's own agents plugin uses the same pattern.
- The specs arrays (`platformSensorSpecs`, `fanSpecs`) are the
  `Instantiator` models and change only at discovery. The value arrays are
  separate and change on every sample. If a value update changed the model,
  every `FileView` would be destroyed and made again.
- Discovery assigns new specs only if `sensorSetChanged` or `fanSetChanged`
  is true, for the same reason. A driver rebind moves the sysfs paths and
  makes a new set.
- `platformSensors` and `fans` zip the specs with their latest values for the
  panel `Repeater`s.
- `hottestPlatformTemp` sets the bar warning tint and the tooltip peak on a
  machine with no package sensor. `hottestPlatformSensor` lets the
  temperature tile name its source.
- `heatpipeWatts` is the SMC heatpipe power reading (PHPC): an estimate of
  the heat that the SoC dissipates through its heatpipes. With no die
  temperature on Asahi, it is the nearest value to a CPU thermal load, and
  the fan curves use the same input.

### Fan control

Fan control uses the `asahi-fanctl` helper and its `asahi-fand` daemon.

- The daemon writes `/etc/asahi-fand.conf` on every mode change. A watched
  `FileView` keeps the active preset and the manual-mode bar tint live with
  no polling. If the file is missing, the helper is not installed and the
  fan section stays hidden.
- The `macsmc_hwmon` `fan_control` module parameter gates manual control.
  A watched `FileView` updates the Enable button when control unlocks, also
  when the daemon unlocks it. That unlock rebinds the driver and moves the
  sysfs paths, so a change from locked to unlocked starts a new discovery.
- `fanStatusProc` runs `sudo -n asahi-fanctl status` once per panel open,
  after every action, and after a discovery that finds SMC sensors. It gives
  the daemon state only. RPMs and targets come from sysfs.
- `fanctlProc` runs the mode, curve and enable commands. On exit it reloads
  the parameter view and the daemon state. After `enable` it also starts a
  new discovery, because the driver rebind moves the hwmon paths.

## Panel.qml: colors, thresholds and labels

- `secondary` is a darker accent: charted values stay in the accent family
  and do not look like body text, but separate from the primary line.
- Omarchy themes have no warning color (they ship foreground, accent,
  urgent and muted), so `warningColor` blends accent and urgent. A fixed
  orange clashes with many themes.
- In Both mode, `stressWarningColor` and `stressCriticalColor` use the
  `yellow` and `red` of the theme `colors.toml`. If a theme has none, they
  fall back to `warningColor` and `urgent`.
- Icon mode shows only the plugin glyph. It still tints at warning and
  critical pressure, and the tooltip and dashboard do not change.
- On a machine without a package sensor (Apple Silicon), `warning` and
  `critical` also follow heatpipe watts, the hottest platform temperature,
  and a fan mode other than auto. In that mode the SMC curve is off, so the
  software is the safety net.
- Temperature meters start at `temperatureFloor` (30°C). A meter from 0
  shows a cold 57°C chip as half loaded. GPU temperature uses the same band.
- The keyboard and mouse cursor over the action row drives one highlight
  through `hasCursor`, never `containsMouse`, so only one highlight shows.
- Every horizontal bar label has a fixed character count (`padPercent`,
  `padThermalBarValue`), so the widget keeps its width when a value crosses
  10 or 100. A vertical bar shows the number only.
- `formatPair` prints used and total with one unit (`3.6 / 7.3 GiB`), so
  the pair lines up and fits a third of the panel.
- Adaptive mode compares CPU and memory only. Temp mode is opt-in.
- In Both mode, `barSegments` splits the label so each reading has its own
  color. Separators have value `-1` and keep the bar color. The plain label
  stays, transparent, so the widget keeps its size and click area.
- A separator on the left divides the widget from the workspaces.

## Panel.qml: thermal headline and sensors

- With a package sensor, the HEAT tile shows that temperature. Apple
  Silicon has no die temperature, and the warmest exposed sensor is a
  peripheral that can read mild while the SoC is hot. There the tile shows
  heatpipe watts, the same input that the fan curves use. Without heatpipe
  power, the tile shows the warmest temperature labelled with its source.
- The tile caption stays short, because the three-tile row clips long text.
  It has no cool, warm or hot labels for watts, because those depend on the
  chassis and are not calibrated.
- The tooltip headline uses the same order: package sensor, heatpipe watts,
  then the warmest temperature. The tooltip escapes markup (see
  "Tooltip markup") and skips the GPU line when no GPU reading exists.
- Each GPU tile depends on its own sensor, so a card with only a
  temperature still gets a section. `gpuTileWidth` divides by the number of
  visible tiles, because `Row` skips invisible children.
- The default SENSORS list shows heatpipe, battery and charge temperatures
  and total system power. "Show all" shows the rest. If no label matches
  (`noLabelMatchedSmcNaming`), the list shows all sensors.
- A fan target shows only in manual mode. Under SMC control the target is
  the request of the SMC.
- The disk row shows combined throughput, so after the first device the
  label gives a count. `shortDiskName` turns `nvme0n1` into `nvme0` and
  `mmcblk0` into `mmc0`.
- A mount label is the last path segment (`/mnt/data` gives `data`). If two
  mounts share that name, they show the full path.
- The panel height has a cap that grows with the extra disks, sensors,
  charts and fan section. `fittedContentHeight` still shrinks to the screen
  and the content.

## Panel.qml: layout and components

- The GPU row is hidden when no card has a reading, so those machines keep
  the three-tile layout.
- On Asahi, the SENSORS section lists the labelled SMC temperatures and
  power rails, and charts the HEAT value over time with a peak scale, as the
  network chart does.
- The FANS section shows live RPMs and the preset selector, and is hidden
  without the SMC hwmon device. Auto gives the fans back to the SMC curve.
  The other presets run in the `asahi-fand` daemon on heatpipe power. If the
  helper is missing, the section points to the README. If the module
  parameter locks control, one button unlocks it. The presets are far apart
  so that each one sounds different (see the README table). The custom
  curve scales RPM between two bounds as heatpipe power crosses a watt
  window, with a floor that is the minimum RPM.
- The CPU and memory chart prints its fixed 100% scale, so an idle machine
  does not look like an empty box.
- Per-thread load uses a tint, not a bar: a bar for a core at 5% is a 1 px
  line that looks like a rendering fault. The numbers show only when a cell
  has room for about four characters.
- Disk throughput gets one line. Its history is the least watched value,
  and without a disk chart the network chart gets the full width.
- `SectionHeading` puts the label on the left and its live summary on the
  right, as the shell does, so a header does not use a line of its own.
- `ActivityColumn` draws up above the axis and down below it on one shared
  scale, and never sums them. The scale label is in the header, because on
  the chart it covers the spikes.
- `RateLabel` gives the arrow the color of its series, so no second legend
  is needed.
- `SensorRow` shows the anchored temperature meter for temperatures only.
  Watts have no natural maximum.
- `FanRow` shows the driver RPM window below the live RPM. The RPM value
  changes color under manual control, so the row shows who controls the
  fan.
- Sensor labels from sysfs and mount paths from `df` render with
  `Text.PlainText`, so a crafted label cannot become rich text.
