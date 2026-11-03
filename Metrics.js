function finiteNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value))
}

var DEFAULT_WARNING_PERCENT = 70
var DEFAULT_CRITICAL_PERCENT = 90
var MINIMUM_CRITICAL_PERCENT = 61

function percentSetting(value, fallback) {
  if (value === null || value === undefined || String(value).trim() === "") return fallback
  return finiteNumber(value, fallback)
}

function alarmThresholds(warningSetting, criticalSetting) {
  var critical = Math.max(percentSetting(criticalSetting, DEFAULT_CRITICAL_PERCENT), MINIMUM_CRITICAL_PERCENT)
  var warning = Math.min(percentSetting(warningSetting, DEFAULT_WARNING_PERCENT), critical - 1)
  return { warning: warning, critical: critical }
}

function escapeMarkup(value) {
  return String(value === undefined || value === null ? "" : value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}

function parseCpu(raw, previous) {
  var lines = String(raw || "").split("\n")
  var snapshots = ({})
  var usages = ({})

  for (var i = 0; i < lines.length; i++) {
    var fields = lines[i].trim().split(/\s+/)
    if (!/^cpu\d*$/.test(fields[0] || "")) continue

    var values = []
    for (var field = 1; field <= 8; field++) values.push(finiteNumber(fields[field], 0))
    var total = 0
    for (var value = 0; value < values.length; value++) total += values[value]
    var idle = values[3] + values[4]
    snapshots[fields[0]] = { total: total, idle: idle }

    var before = previous ? previous[fields[0]] : null
    if (!before) continue
    var totalDelta = total - before.total
    var idleDelta = idle - before.idle
    if (totalDelta <= 0 || idleDelta < 0) continue
    usages[fields[0]] = clamp((totalDelta - idleDelta) * 100 / totalDelta, 0, 100)
  }

  var cores = []
  var labels = Object.keys(usages).filter(function(label) { return label !== "cpu" })
  labels.sort(function(a, b) { return Number(a.slice(3)) - Number(b.slice(3)) })
  for (var core = 0; core < labels.length; core++) {
    cores.push({ name: labels[core].toUpperCase(), percent: usages[labels[core]] })
  }

  return {
    snapshot: snapshots,
    overall: usages.cpu === undefined ? -1 : usages.cpu,
    cores: cores
  }
}

function parseMemory(raw) {
  var values = ({})
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^([A-Za-z_()]+):\s+(\d+)/)
    if (match) values[match[1]] = Number(match[2]) * 1024
  }

  var total = values.MemTotal || 0
  var available = values.MemAvailable || 0
  var used = total > 0 ? Math.max(0, total - available) : 0
  var swapTotal = values.SwapTotal || 0
  var swapUsed = Math.max(0, swapTotal - (values.SwapFree || 0))
  return {
    total: total,
    used: used,
    percent: total > 0 ? clamp(used * 100 / total, 0, 100) : -1,
    swapTotal: swapTotal,
    swapUsed: swapUsed,
    swapPercent: swapTotal > 0 ? clamp(swapUsed * 100 / swapTotal, 0, 100) : -1
  }
}

function parseLoad(raw) {
  var fields = String(raw || "").trim().split(/\s+/)
  return {
    one: finiteNumber(fields[0], -1),
    five: finiteNumber(fields[1], -1),
    fifteen: finiteNumber(fields[2], -1)
  }
}

function parseUptime(raw) {
  return Math.max(0, finiteNumber(String(raw || "").trim().split(/\s+/)[0], 0))
}

function parseDefaultInterface(raw) {
  var lines = String(raw || "").split("\n")
  for (var i = 1; i < lines.length; i++) {
    var fields = lines[i].trim().split(/\s+/)
    if (fields.length < 4 || fields[1] !== "00000000") continue
    var flags = parseInt(fields[3], 16)
    if (isFinite(flags) && (flags & 2) !== 0) return fields[0]
  }
  return ""
}

function parseNetwork(raw, interfaceName) {
  if (!interfaceName) return null
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var separator = lines[i].indexOf(":")
    if (separator < 0) continue
    var name = lines[i].slice(0, separator).trim()
    if (name !== interfaceName) continue
    var fields = lines[i].slice(separator + 1).trim().split(/\s+/)
    if (fields.length < 9) return null
    return { rx: finiteNumber(fields[0], 0), tx: finiteNumber(fields[8], 0) }
  }
  return null
}

function parseDisk(raw, devices) {
  var wanted = ({})
  for (var i = 0; i < devices.length; i++) wanted[String(devices[i])] = true
  var readSectors = 0
  var writeSectors = 0
  var found = false
  var lines = String(raw || "").split("\n")

  for (var line = 0; line < lines.length; line++) {
    var fields = lines[line].trim().split(/\s+/)
    if (fields.length < 10 || !wanted[fields[2]]) continue
    readSectors += finiteNumber(fields[5], 0)
    writeSectors += finiteNumber(fields[9], 0)
    found = true
  }

  return found ? { readBytes: readSectors * 512, writeBytes: writeSectors * 512 } : null
}

function parseDiscovery(raw) {
  var result = {
    cpuTempPath: "",
    gpuBusyPath: "",
    gpuTempPath: "",
    gpuVramUsedPath: "",
    gpuVramTotalPath: "",
    devices: [],
    platformSensors: [],
    fans: []
  }
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var separator = lines[i].indexOf("\t")
    if (separator < 0) continue
    var key = lines[i].slice(0, separator)
    var value = lines[i].slice(separator + 1).trim()
    if (key === "cpu_temp") result.cpuTempPath = value
    else if (key === "gpu_busy") result.gpuBusyPath = value
    else if (key === "gpu_temp") result.gpuTempPath = value
    else if (key === "gpu_vram_used") result.gpuVramUsedPath = value
    else if (key === "gpu_vram_total") result.gpuVramTotalPath = value
    else if (key === "disk" && value !== "") result.devices.push(value)
    else if (key === "platform_sensor" && value !== "") {
      var fields = value.split("\t")
      if (fields.length >= 3 && (fields[1] === "temp" || fields[1] === "power")) {
        result.platformSensors.push({
          path: fields[0],
          kind: fields[1],
          label: fields.slice(2).join("\t")
        })
      }
    } else if (key === "fan" && value !== "") {
      var parts = value.split("\t")
      var fanIndex = Number(parts[1])
      var fanMin = Number(parts[parts.length - 2])
      var fanMax = Number(parts[parts.length - 1])
      if (parts.length >= 5 && isFinite(fanIndex) && fanIndex > 0
        && isFinite(fanMin) && isFinite(fanMax)) {
        result.fans.push({
          path: parts[0],
          targetPath: parts[0].replace(/_input$/, "_target"),
          index: fanIndex,
          label: parts.slice(2, parts.length - 2).join("\t") || ("Fan " + fanIndex),
          min: fanMin,
          max: fanMax
        })
      }
    }
  }
  return result
}

function parseGpuPercent(raw) {
  var text = String(raw === undefined || raw === null ? "" : raw).trim()
  if (text === "") return -1
  var value = Number(text)
  return isFinite(value) && value >= 0 ? clamp(value, 0, 100) : -1
}

function parseByteCount(raw) {
  var text = String(raw === undefined || raw === null ? "" : raw).trim()
  if (text === "") return -1
  var value = Number(text)
  return isFinite(value) && value >= 0 ? value : -1
}

function parseSensorValue(raw, kind) {
  var text = String(raw === undefined || raw === null ? "" : raw).trim()
  if (text === "") return -1
  var value = Number(text)
  if (!isFinite(value) || value < 0) return -1
  return kind === "power" ? value / 1000000 : value / 1000
}

var ON_DISK_FILESYSTEM_ALLOWLIST = {
  ext2: true, ext3: true, ext4: true, btrfs: true, xfs: true, f2fs: true,
  zfs: true, jfs: true, reiserfs: true, nilfs2: true, bcachefs: true,
  vfat: true, exfat: true, ntfs: true, ntfs3: true, hfsplus: true, ufs: true
}

function parseFilesystems(raw) {
  var lines = String(raw || "").trim().split("\n")
  var byDevice = ({})
  var order = []

  for (var i = 1; i < lines.length; i++) {
    var fields = lines[i].trim().split(/\s+/)
    if (fields.length < 7) continue
    var device = fields[0]
    var type = fields[1]
    var mount = fields.slice(6).join(" ")
    var isRootMount = mount === "/"
    if (!isRootMount && !ON_DISK_FILESYSTEM_ALLOWLIST[type]) continue

    var total = finiteNumber(fields[2], 0) * 1024
    var used = finiteNumber(fields[3], 0) * 1024
    var entry = {
      mount: mount,
      total: total,
      used: used,
      percent: total > 0 ? clamp(used * 100 / total, 0, 100) : -1
    }

    var sameDeviceEntry = byDevice[device]
    if (!sameDeviceEntry) {
      byDevice[device] = entry
      order.push(device)
    } else if (mount.length < sameDeviceEntry.mount.length) {
      byDevice[device] = entry
    }
  }

  var result = []
  for (var d = 0; d < order.length; d++) result.push(byDevice[order[d]])
  return result
}

function peakValue(history) {
  var peak = 0
  if (!history) return peak
  for (var i = 0; i < history.length; i++) {
    var value = Number(history[i].value)
    if (isFinite(value) && value > peak) peak = value
  }
  return peak
}

function maximumPercent(cores) {
  var peak = -1
  if (!cores) return peak
  for (var i = 0; i < cores.length; i++) {
    var value = Number(cores[i].percent)
    if (isFinite(value) && value > peak) peak = value
  }
  return peak
}

function parseThemeColors(raw) {
  var colors = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^\s*([A-Za-z0-9_]+)\s*=\s*"(#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?)"/)
    if (match) colors[match[1]] = match[2]
  }
  return colors
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    parseCpu: parseCpu,
    parseMemory: parseMemory,
    parseLoad: parseLoad,
    parseUptime: parseUptime,
    parseDefaultInterface: parseDefaultInterface,
    parseNetwork: parseNetwork,
    parseDisk: parseDisk,
    parseDiscovery: parseDiscovery,
    parseGpuPercent: parseGpuPercent,
    parseByteCount: parseByteCount,
    parseSensorValue: parseSensorValue,
    parseFilesystems: parseFilesystems,
    peakValue: peakValue,
    maximumPercent: maximumPercent,
    escapeMarkup: escapeMarkup,
    parseThemeColors: parseThemeColors,
    alarmThresholds: alarmThresholds
  }
}
