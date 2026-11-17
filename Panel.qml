import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Metrics.js" as Model

Panel {
  id: root

  moduleName: "harshith.system-monitor"
  ipcTarget: "harshith.system-monitor"
  manageIpc: false

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color muted: Qt.darker(foreground, 1.4)
  readonly property color trackColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
  readonly property color chartGrid: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)
  readonly property color secondary: Qt.darker(accent, 1.5)
  readonly property color warningColor: Qt.tint(accent, Qt.rgba(urgent.r, urgent.g, urgent.b, 0.6))
  property var themePalette: ({})
  readonly property color stressWarningColor: themePalette.yellow || warningColor
  readonly property color stressCriticalColor: themePalette.red || urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string barMode: String(setting("barMode", "Both"))
  readonly property bool iconOnly: barMode === "Icon"
  readonly property var alarmThresholds: Model.alarmThresholds(setting("warningPercent", 70), setting("criticalPercent", 90))
  readonly property real warningThreshold: alarmThresholds.warning
  readonly property real criticalThreshold: alarmThresholds.critical
  readonly property real pressure: Math.max(metrics.cpuPercent, metrics.memoryPercent)
  readonly property bool warning: pressure >= warningThreshold || metrics.cpuTemperature >= 85 || metrics.gpuTemperature >= 85 || metrics.hottestPlatformTemp >= 85 || (metrics.cpuTemperature < 0 && metrics.heatpipeWatts >= heatWarnW) || metrics.fansManual
  readonly property bool critical: pressure >= criticalThreshold || metrics.cpuTemperature >= 95 || metrics.gpuTemperature >= 95 || metrics.hottestPlatformTemp >= 95 || (metrics.cpuTemperature < 0 && metrics.heatpipeWatts >= heatCriticalW)

  readonly property string heroGlyph: "󰻠"

  readonly property real temperatureFloor: 30
  readonly property real temperatureCeiling: 100

  property bool cursorActive: false
  property int selectedIndex: 0
  readonly property int actionCount: 2

  function percent(value) {
    return isFinite(value) && value >= 0 ? Math.round(value) + "%" : "—"
  }

  function padPercent(value) {
    if (!isFinite(value) || value < 0) return "  —"
    var text = Math.round(value) + "%"
    while (text.length < 4) text = " " + text
    return text
  }

  function padThermalBarValue() {
    if (thermalTileIsWatts()) {
      var text = metrics.heatpipeWatts.toFixed(1) + "W"
      while (text.length < 5) text = " " + text
      return text
    }
    var t = metrics.cpuTemperature >= 0 ? metrics.cpuTemperature : metrics.hottestPlatformTemp
    if (!isFinite(t) || t < 0) return "  —"
    var deg = Math.round(t) + "°"
    while (deg.length < 4) deg = " " + deg
    return deg
  }

  function thermalBarName() {
    return thermalTileIsWatts() ? "HEAT" : "TEMP"
  }

  function formatBytes(value) {
    var amount = Number(value)
    if (!isFinite(amount) || amount < 0) return "—"
    var units = ["B", "KiB", "MiB", "GiB", "TiB"]
    var index = 0
    while (amount >= 1024 && index < units.length - 1) {
      amount /= 1024
      index++
    }
    var digits = index >= 3 ? 1 : (amount >= 100 ? 0 : 1)
    return amount.toFixed(digits) + " " + units[index]
  }

  function formatPair(used, total) {
    var totalBytes = Number(total)
    if (!isFinite(totalBytes) || totalBytes <= 0) return "—"
    var units = ["B", "KiB", "MiB", "GiB", "TiB"]
    var index = 0
    var scale = 1
    while (totalBytes / scale >= 1024 && index < units.length - 1) {
      scale *= 1024
      index++
    }
    var digits = index >= 3 ? 1 : 0
    return (Number(used) / scale).toFixed(digits) + " / " + (totalBytes / scale).toFixed(digits) + " " + units[index]
  }

  function formatRate(value) {
    return isFinite(value) && value >= 0 ? formatBytes(value) + "/s" : "—"
  }

  function formatUptime(seconds) {
    var totalMinutes = Math.floor(Number(seconds) / 60)
    if (!isFinite(totalMinutes) || totalMinutes < 0) return "—"
    var days = Math.floor(totalMinutes / 1440)
    var hours = Math.floor((totalMinutes % 1440) / 60)
    var minutes = totalMinutes % 60
    if (days > 0) return days + "d " + hours + "h"
    if (hours > 0) return hours + "h " + minutes + "m"
    return minutes + "m"
  }

  function loadText() {
    function one(value) { return value >= 0 ? value.toFixed(2) : "—" }
    return one(metrics.loadOne) + " / " + one(metrics.loadFive) + " / " + one(metrics.loadFifteen)
  }

  readonly property real heatWarnW: 15
  readonly property real heatCriticalW: 25
  readonly property real heatCeilingW: 30

  function thermalTileIsWatts() {
    return metrics.cpuTemperature < 0 && metrics.heatpipeWatts >= 0
  }

  function thermalTileTitle() {
    return thermalTileIsWatts() ? "HEAT" : "TEMP"
  }

  function thermalTileValue() {
    if (thermalTileIsWatts()) return metrics.heatpipeWatts.toFixed(1) + " W"
    if (metrics.cpuTemperature >= 0) return Math.round(metrics.cpuTemperature) + "°C"
    if (metrics.hottestPlatformTemp >= 0) return Math.round(metrics.hottestPlatformTemp) + "°C"
    return "—"
  }

  function thermalTileDetail() {
    if (thermalTileIsWatts()) return "heatpipe"
    if (metrics.cpuTemperature >= 0) {
      if (metrics.cpuTemperature >= 85) return "Warm"
      return "Normal"
    }
    var source = temperatureSourceLabel()
    if (source !== "") return "warmest: " + source
    return metrics.hasPlatformSensors ? "No SoC sensor" : "Unavailable"
  }

  function thermalTileMeter() {
    if (thermalTileIsWatts()) {
      return Math.max(0, Math.min(100, metrics.heatpipeWatts * 100 / heatCeilingW))
    }
    return temperatureBandMeter(metrics.cpuTemperature >= 0 ? metrics.cpuTemperature : metrics.hottestPlatformTemp)
  }

  function thermalTileMeterColor() {
    if (thermalTileIsWatts()) return levelColor(metrics.heatpipeWatts, heatWarnW, heatCriticalW)
    return levelColor(metrics.cpuTemperature >= 0 ? metrics.cpuTemperature : metrics.hottestPlatformTemp, 85, 95)
  }

  function thermalTileAlarming() {
    if (thermalTileIsWatts()) return metrics.heatpipeWatts >= heatCriticalW
    return (metrics.cpuTemperature >= 0 ? metrics.cpuTemperature : metrics.hottestPlatformTemp) >= 95
  }

  function headlineTempText() {
    if (metrics.cpuTemperature >= 0) return Math.round(metrics.cpuTemperature) + "°C"
    if (metrics.heatpipeWatts >= 0) return "heat " + metrics.heatpipeWatts.toFixed(1) + " W"
    if (metrics.hottestPlatformTemp >= 0) return "warmest " + Math.round(metrics.hottestPlatformTemp) + "°C"
    return "—"
  }

  function temperatureSourceLabel() {
    var sensor = metrics.hottestPlatformSensor
    if (!sensor || !isFinite(sensor.value) || sensor.value < 0) return ""
    return String(sensor.label)
      .replace(/ Temperature$/, "")
      .replace(/ Temp$/, "")
  }

  function temperatureBandMeter(value) {
    if (!isFinite(value) || value < 0) return -1
    var span = temperatureCeiling - temperatureFloor
    return Math.max(0, Math.min(100, (value - temperatureFloor) * 100 / span))
  }

  readonly property bool hasGpuUsage: metrics.gpuPercent >= 0
  readonly property bool hasGpuTemperature: metrics.gpuTemperature >= 0
  readonly property bool hasGpuVram: metrics.gpuVramTotal > 0 && metrics.gpuVramUsed >= 0
  readonly property bool hasGpu: hasGpuUsage || hasGpuTemperature
  readonly property int gpuTileCount: (hasGpuUsage ? 1 : 0) + (hasGpuTemperature ? 1 : 0)

  function gpuTemperatureText() {
    return metrics.gpuTemperature >= 0 ? Math.round(metrics.gpuTemperature) + "°C" : "—"
  }

  function gpuTemperatureDetail() {
    if (metrics.gpuTemperature < 0) return "Unavailable"
    if (metrics.gpuTemperature >= 85) return "Warm"
    return "Normal"
  }

  function gpuTemperatureMeter() {
    return temperatureBandMeter(metrics.gpuTemperature)
  }

  function sensorValueText(sensor) {
    if (!sensor || !isFinite(sensor.value) || sensor.value < 0) return "—"
    if (sensor.kind === "power") return sensor.value.toFixed(1) + " W"
    return Math.round(sensor.value) + "°C"
  }

  function sensorSummaryText() {
    if (metrics.hottestPlatformTemp >= 0) return "peak " + Math.round(metrics.hottestPlatformTemp) + "°C"
    return ""
  }

  property bool showAllPlatformSensors: false

  function isPrimaryPlatformSensor(sensor) {
    if (!sensor) return false
    var label = String(sensor.label || "").toLowerCase()
    if (label.indexOf("heatpipe") >= 0) return true
    if (label.indexOf("battery") >= 0) return true
    if (label.indexOf("charge") >= 0) return true
    if (label.indexOf("total system") >= 0) return true
    return false
  }

  function visiblePlatformSensors() {
    var all = metrics.platformSensors
    if (root.showAllPlatformSensors) return all
    var rows = []
    for (var i = 0; i < all.length; i++) {
      if (root.isPrimaryPlatformSensor(all[i])) rows.push(all[i])
    }
    var noLabelMatchedSmcNaming = rows.length === 0
    return noLabelMatchedSmcNaming ? all : rows
  }

  function hiddenPlatformSensorCount() {
    if (root.showAllPlatformSensors) return 0
    var all = metrics.platformSensors
    var visible = root.visiblePlatformSensors()
    if (visible.length === all.length) return 0
    return Math.max(0, all.length - visible.length)
  }


  function fanRpmText(fan) {
    if (!fan || !isFinite(fan.rpm) || fan.rpm < 0) return "—"
    var text = Math.round(fan.rpm) + " RPM"
    if (metrics.fansManual && isFinite(fan.target) && fan.target > 0) {
      text += " · tgt " + Math.round(fan.target)
    }
    return text
  }

  function fansSummaryText() {
    if (!metrics.fanCtlAvailable) return "monitor only"
    if (!metrics.fanControlUnlocked) return "locked · SMC auto"
    if (metrics.fanStatus && metrics.fanStatus.daemon && metrics.fanStatus.daemon.active !== true) return "daemon down"
    if (metrics.fanMode === "" || metrics.fanMode === "auto") return "SMC auto"
    return "manual · " + metrics.fanMode
  }

  function gpuTileWidth(rowWidth, spacing) {
    var count = Math.max(1, gpuTileCount)
    return (rowWidth - spacing * (count - 1)) / count
  }

  function gpuVramPercent() {
    if (metrics.gpuVramTotal <= 0 || metrics.gpuVramUsed < 0) return -1
    return Math.max(0, Math.min(100, metrics.gpuVramUsed * 100 / metrics.gpuVramTotal))
  }

  function gpuVramDetail() {
    if (metrics.gpuVramTotal <= 0 || metrics.gpuVramUsed < 0) return "—"
    return formatPair(metrics.gpuVramUsed, metrics.gpuVramTotal)
  }

  function shortDiskName(name) {
    var text = String(name || "")
    var nvme = text.match(/^nvme(\d+)n\d+$/)
    if (nvme) return "nvme" + nvme[1]
    var mmc = text.match(/^mmcblk(\d+)$/)
    if (mmc) return "mmc" + mmc[1]
    return text
  }

  function diskLabelText() {
    var devices = metrics.diskDevices
    if (!devices || devices.length === 0) return "DISK"
    if (devices.length === 1) return "DISK · " + shortDiskName(devices[0])
    return "DISK · " + shortDiskName(devices[0]) + " +" + (devices.length - 1)
  }

  function mountBasename(mount) {
    var segments = String(mount).split("/")
    return segments[segments.length - 1] || String(mount)
  }

  function mountLabel(mount) {
    var target = String(mount)
    var base = mountBasename(target)
    var mounts = metrics.extraFilesystems
    for (var i = 0; i < mounts.length; i++) {
      var other = String(mounts[i].mount)
      if (other !== target && mountBasename(other) === base) return target
    }
    return base
  }

  function levelColor(value, warn, crit) {
    if (!isFinite(value) || value < 0) return root.muted
    if (value >= crit) return root.urgent
    if (value >= warn) return root.warningColor
    return root.accent
  }

  function stressColor(value) {
    if (!isFinite(value) || value < 0) return root.foreground
    if (value >= criticalThreshold) return root.stressCriticalColor
    if (value >= warningThreshold) return root.stressWarningColor
    return root.foreground
  }

  function barSegments() {
    var parts = [
      { text: "CPU " + percent(metrics.cpuPercent), value: metrics.cpuPercent },
      { text: "MEM " + percent(metrics.memoryPercent), value: metrics.memoryPercent }
    ]
    if (hasGpuUsage) parts.push({ text: "GPU " + percent(metrics.gpuPercent), value: metrics.gpuPercent })
    if (hasGpuVram) parts.push({ text: "VRAM " + percent(gpuVramPercent()), value: gpuVramPercent() })
    var segments = []
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) segments.push({ text: " | ", value: -1 })
      segments.push(parts[i])
    }
    return segments
  }

  function modeLabel() {
    return barMode === "Memory" ? "RAM" : barMode
  }

  function barLabel() {
    if (button.vertical) {
      if (barMode === "Temp") {
        if (thermalTileIsWatts()) return metrics.heatpipeWatts.toFixed(0)
        var tv = metrics.cpuTemperature >= 0 ? metrics.cpuTemperature : metrics.hottestPlatformTemp
        return isFinite(tv) && tv >= 0 ? String(Math.round(tv)) : "—"
      }
      var value = barMode === "CPU" ? metrics.cpuPercent
        : barMode === "Memory" ? metrics.memoryPercent
        : barMode === "GPU" ? metrics.gpuPercent
        : Math.max(metrics.cpuPercent, metrics.memoryPercent)
      return isFinite(value) && value >= 0 ? String(Math.round(value)) : "—"
    }
    if (barMode === "CPU") return "CPU " + padPercent(metrics.cpuPercent)
    if (barMode === "Memory") return "RAM " + padPercent(metrics.memoryPercent)
    if (barMode === "GPU") return "GPU " + padPercent(metrics.gpuPercent)
    if (barMode === "Temp") return thermalBarName() + " " + padThermalBarValue()
    if (barMode === "Both")
      return barSegments().map(function(segment) { return segment.text }).join("")
    return metrics.cpuPercent >= metrics.memoryPercent
      ? "CPU " + padPercent(metrics.cpuPercent)
      : "RAM " + padPercent(metrics.memoryPercent)
  }

  function tooltipText() {
    var interfaceName = Model.escapeMarkup(metrics.activeInterface)
    var lines = [
      "CPU " + percent(metrics.cpuPercent) + " · RAM " + percent(metrics.memoryPercent) + " · " + headlineTempText()
    ]
    if (hasGpu) {
      var gpu = []
      if (hasGpuUsage) gpu.push("GPU " + percent(metrics.gpuPercent))
      if (hasGpuTemperature) gpu.push((hasGpuUsage ? "" : "GPU ") + gpuTemperatureText())
      if (hasGpuVram) gpu.push("VRAM " + gpuVramDetail())
      lines.push(gpu.join(" · "))
    }
    if (metrics.fans.length > 0) {
      var speeds = []
      for (var fanIndex = 0; fanIndex < metrics.fans.length; fanIndex++) {
        var fan = metrics.fans[fanIndex]
        speeds.push(isFinite(fan.rpm) && fan.rpm >= 0 ? Math.round(fan.rpm) + " RPM" : "—")
      }
      lines.push("Fans " + speeds.join(" / ") + (metrics.fansManual ? " · " + metrics.fanMode : " · SMC"))
    }
    lines.push("Load " + loadText() + (interfaceName !== "" ? " · " + interfaceName : ""))
    lines.push("Net ↓ " + formatRate(metrics.networkDownBps) + " ↑ " + formatRate(metrics.networkUpBps))
    lines.push("Disk R " + formatRate(metrics.diskReadBps) + " · W " + formatRate(metrics.diskWriteBps))
    lines.push("Right-click cycles display · Middle-click opens btop")
    return lines.join("\n")
  }

  function cycleBarMode() {
    var modes = hasGpuUsage
      ? ["Adaptive", "CPU", "Memory", "GPU", "Temp", "Both", "Icon"]
      : ["Adaptive", "CPU", "Memory", "Temp", "Both", "Icon"]
    var index = modes.indexOf(barMode)
    var next = modes[(index + 1) % modes.length]
    settings = Object.assign({}, settings, { barMode: next })
    if (bar && bar.shell) bar.shell.updateEntryInline(moduleName, settings)
  }

  function launchBtop() {
    if (bar) bar.run("omarchy-launch-or-focus-tui btop")
    close()
  }

  function moveCursor(delta) {
    if (delta === 0) return
    selectedIndex = Math.max(0, Math.min(actionCount - 1, selectedIndex + delta))
  }

  function activateCursor() {
    if (selectedIndex === 0) cycleBarMode()
    else launchBtop()
  }

  function ensureCursorVisible(item) {
    if (!item || !panel.scrollArea) return
    var flick = panel.scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var point = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = point.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = Style.space(6)
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin) flick.contentY = bottom + margin - flick.height
  }

  visible: true
  readonly property bool showSeparator: !button.vertical
  readonly property int separatorSpace: showSeparator ? Style.space(12) : 0
  implicitWidth: separatorSpace + (iconOnly ? iconButton.implicitWidth : button.implicitWidth)
  implicitHeight: iconOnly ? iconButton.implicitHeight : button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      selectedIndex = 0
      metrics.sample()
      Qt.callLater(function() { panel.keyCatcher.forceActiveFocus() })
    }
  }

  Metrics {
    id: metrics
    settings: root.settings
    panelOpen: root.opened
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { metrics.sample(); return "ok" }
  }

  function barPressed(buttonCode) {
    if (buttonCode === Qt.RightButton) cycleBarMode()
    else if (buttonCode === Qt.MiddleButton) launchBtop()
    else toggle()
  }

  Rectangle {
    id: separator
    visible: root.showSeparator
    anchors.left: parent.left
    anchors.leftMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    width: 1
    height: parent.height * 0.5
    color: root.chartGrid
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    anchors.leftMargin: root.separatorSpace
    visible: !root.iconOnly
    bar: root.bar
    readonly property bool segmented: root.barMode === "Both" && !vertical
    text: root.barLabel()
    fontSize: Style.font.caption
    horizontalMargin: 6
    foreground: segmented ? "transparent" : root.foreground
    active: !segmented && (root.warning || root.critical)
    activeColor: root.critical ? root.urgent : root.warningColor
    tooltipText: root.tooltipText()
    onPressed: function(buttonCode) { root.barPressed(buttonCode) }
  }

  Row {
    anchors.centerIn: button
    visible: button.visible && button.segmented

    Repeater {
      model: button.segmented ? root.barSegments() : []

      Text {
        required property var modelData
        text: modelData.text
        textFormat: Text.PlainText
        color: root.stressColor(modelData.value)
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering

        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }
    }
  }

  FileView {
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.themePalette = Model.parseThemeColors(text())
  }

  BarIconButton {
    id: iconButton
    anchors.fill: parent
    anchors.leftMargin: root.separatorSpace
    visible: root.iconOnly
    bar: root.bar
    text: root.heroGlyph
    active: root.warning || root.critical
    activeColor: root.critical ? root.urgent : root.warningColor
    tooltipText: root.tooltipText()
    onPressed: function(buttonCode) { root.barPressed(buttonCode) }
  }

  MonitorPopup {
    id: panel
    root: root
    metrics: metrics
    anchorItem: root.iconOnly ? iconButton : button
  }
}
