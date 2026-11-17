import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

KeyboardPanel {
    id: panel
    required property var root
    required property var metrics
    property alias keyCatcher: keyCatcher
    property alias scrollArea: scrollArea
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(600 + metrics.extraFilesystems.length * 40 + (metrics.hasPlatformSensors ? metrics.platformSensors.length * 40 + (metrics.fanMode === "custom" ? 400 : 300) : 0)))

    function applyFanCurve() {
      metrics.runFanctl([
        "curve",
        String(loWField.field.value),
        String(hiWField.field.value),
        String(rpmMinField.field.value),
        String(rpmMaxField.field.value),
        String(floorField.field.value)
      ])
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx !== 0 ? dx : dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onTextKey: function(text) {
        if (text === "r" || text === "R") metrics.sample()
        else if (text === "b" || text === "B") root.launchBtop()
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(9)

          PanelHero {
            width: parent.width
            title: metrics.hostname !== "" ? metrics.hostname : "System Monitor"
            meta: "Up " + root.formatUptime(metrics.uptimeSeconds) + " · Load " + root.loadText()
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Text {
                text: root.heroGlyph
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }

            trailingControl: Component {
              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh (R)"
                foreground: root.foreground
                hoverColor: root.accent
                fontFamily: root.fontFamily
                onClicked: metrics.sample()
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Row {
            width: parent.width
            spacing: Style.space(8)

            StatTile {
              width: (parent.width - parent.spacing * 2) / 3
              title: "CPU"
              value: root.percent(metrics.cpuPercent)
              detail: metrics.perCore.length > 0 ? metrics.perCore.length + " threads" : "—"
              meter: metrics.cpuPercent
              meterColor: root.levelColor(metrics.cpuPercent, root.warningThreshold, root.criticalThreshold)
              alarming: metrics.cpuPercent >= root.criticalThreshold
            }

            StatTile {
              width: (parent.width - parent.spacing * 2) / 3
              title: "MEMORY"
              value: root.percent(metrics.memoryPercent)
              detail: root.formatPair(metrics.memoryUsed, metrics.memoryTotal)
              meter: metrics.memoryPercent
              meterColor: root.levelColor(metrics.memoryPercent, root.warningThreshold, root.criticalThreshold)
              alarming: metrics.memoryPercent >= root.criticalThreshold
            }

            StatTile {
              width: (parent.width - parent.spacing * 2) / 3
              title: root.thermalTileTitle()
              value: root.thermalTileValue()
              detail: root.thermalTileDetail()
              meter: root.thermalTileMeter()
              meterColor: root.thermalTileMeterColor()
              alarming: root.thermalTileAlarming()
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            visible: root.hasGpu

            StatTile {
              visible: root.hasGpuUsage
              width: root.gpuTileWidth(parent.width, parent.spacing)
              title: "GPU"
              value: root.percent(metrics.gpuPercent)
              detail: root.hasGpuVram ? "VRAM " + root.gpuVramDetail() : "—"
              meter: metrics.gpuPercent
              meterColor: root.levelColor(metrics.gpuPercent, root.warningThreshold, root.criticalThreshold)
              alarming: metrics.gpuPercent >= root.criticalThreshold
            }

            StatTile {
              visible: root.hasGpuTemperature
              width: root.gpuTileWidth(parent.width, parent.spacing)
              title: "GPU TEMP"
              value: root.gpuTemperatureText()
              detail: root.gpuTemperatureDetail()
              meter: root.gpuTemperatureMeter()
              meterColor: root.levelColor(metrics.gpuTemperature, 85, 95)
              alarming: metrics.gpuTemperature >= 95
            }

          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: metrics.hasPlatformSensors

            SectionHeading {
              title: "SENSORS"
              value: root.sensorSummaryText()
            }

            Item {
              width: parent.width
              height: Style.space(54)
              visible: metrics.thermalHistory.length > 1

              Sparkline {
                anchors.fill: parent
                points: metrics.thermalHistory
                lineColor: root.accent
                fillColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
                gridColor: root.chartGrid
                fixedMaximum: Math.max(metrics.thermalPeak, 0.001)
              }

              Text {
                anchors.left: parent.left
                anchors.top: parent.top
                text: metrics.thermalHeadline >= 0
                  ? metrics.thermalHeadline.toFixed(1) + " " + metrics.thermalHeadlineUnit
                  : ""
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                anchors.right: parent.right
                anchors.top: parent.top
                text: metrics.thermalPeak > 0
                  ? "peak " + (metrics.thermalPeak >= 100
                      ? Math.round(metrics.thermalPeak)
                      : metrics.thermalPeak.toFixed(1)) + " " + metrics.thermalHeadlineUnit
                  : ""
                textFormat: Text.PlainText
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Repeater {
              model: root.visiblePlatformSensors()

              SensorRow {
                required property var modelData
                label: modelData.label
                value: root.sensorValueText(modelData)
                meter: modelData.kind === "temp" ? root.temperatureBandMeter(modelData.value) : -1
                meterColor: root.levelColor(modelData.value, 85, 95)
              }
            }

            Button {
              visible: root.hiddenPlatformSensorCount() > 0 || root.showAllPlatformSensors
              width: parent.width
              text: root.showAllPlatformSensors
                ? "Show fewer sensors"
                : ("Show all sensors · " + root.hiddenPlatformSensorCount() + " more")
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: root.showAllPlatformSensors = !root.showAllPlatformSensors
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: metrics.hasPlatformSensors

            SectionHeading {
              title: "FANS"
              value: root.fansSummaryText()
            }

            Repeater {
              model: metrics.fans

              FanRow {
                root: panel.root
                required property var modelData
                label: modelData.label
                rpmText: root.fanRpmText(modelData)
                rangeText: (isFinite(modelData.min) && isFinite(modelData.max)
                  ? Math.round(modelData.min) + "–" + Math.round(modelData.max) + " RPM" : "")
                manual: metrics.fansManual
              }
            }

            Text {
              visible: metrics.fanCtlError !== ""
              width: parent.width
              text: metrics.fanCtlError
              textFormat: Text.PlainText
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              visible: !metrics.fanCtlAvailable
              width: parent.width
              text: "Fan control requires the asahi-fanctl helper (see README)"
              textFormat: Text.PlainText
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Button {
              visible: metrics.fanCtlAvailable && !metrics.fanControlUnlocked
              width: parent.width
              text: "Enable manual control"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: metrics.enableFanControl()
            }

            ButtonGroup {
              width: parent.width
              visible: metrics.fanCtlAvailable
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              options: [
                { value: "auto", label: "Auto" },
                { value: "quiet", label: "Quiet" },
                { value: "boost", label: "Boost" },
                { value: "full", label: "Full" },
                { value: "custom", label: "Custom" }
              ]
              value: metrics.fanMode
              onChanged: function(selected) { metrics.runFanctl(["mode", selected]) }
            }

            Column {
              id: curveEditor
              width: parent.width
              spacing: Style.space(4)
              visible: metrics.fanMode === "custom"

              Row {
                spacing: Style.space(8)

                NumberField {
                  id: loWField
                  label: "Low W"
                  from: 0
                  to: 60
                  stepSize: 1
                  value: Math.round(metrics.fanCurveLoW)
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                }

                NumberField {
                  id: hiWField
                  label: "High W"
                  from: 1
                  to: 100
                  stepSize: 1
                  value: Math.round(metrics.fanCurveHiW)
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                }

                NumberField {
                  id: floorField
                  label: "Floor RPM"
                  from: 0
                  to: 6400
                  stepSize: 50
                  value: Math.round(metrics.fanCurveFloorRpm)
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                }
              }

              Row {
                spacing: Style.space(8)

                NumberField {
                  id: rpmMinField
                  label: "Min RPM"
                  from: 1200
                  to: 6400
                  stepSize: 50
                  value: Math.round(metrics.fanCurveRpmMin)
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                }

                NumberField {
                  id: rpmMaxField
                  label: "Max RPM"
                  from: 1200
                  to: 6400
                  stepSize: 50
                  value: Math.round(metrics.fanCurveRpmMax)
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                }

                Button {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Apply"
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  onClicked: panel.applyFanCurve()
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(6)

            SectionHeading {
              title: root.hasGpuUsage ? "CPU, MEMORY & GPU" : "CPU & MEMORY"
              value: "2 MIN"
            }

            Item {
              width: parent.width
              height: Style.space(70)

              Sparkline {
                anchors.fill: parent
                points: metrics.cpuHistory
                lineColor: root.accent
                fillColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
                gridColor: root.chartGrid
                gridLevels: [0.25, 0.5, 0.75]
                fixedMaximum: 100
              }

              Sparkline {
                anchors.fill: parent
                points: metrics.memoryHistory
                lineColor: root.secondary
                fillColor: "transparent"
                dashed: true
                lineWidth: 1.2
                fixedMaximum: 100
              }

              Sparkline {
                anchors.fill: parent
                visible: root.hasGpuUsage
                points: metrics.gpuHistory
                lineColor: root.warningColor
                fillColor: "transparent"
                lineWidth: 1.2
                fixedMaximum: 100
              }

              Text {
                anchors.left: parent.left
                anchors.top: parent.top
                text: "100%"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Row {
                anchors.top: parent.top
                anchors.right: parent.right
                spacing: Style.space(8)
                LegendDot { colorValue: root.accent; label: "CPU" }
                LegendDot { colorValue: root.secondary; label: "RAM" }
                LegendDot { visible: root.hasGpuUsage; colorValue: root.warningColor; label: "GPU" }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: metrics.perCore.length > 0

            SectionHeading {
              title: "CORES"
              value: metrics.perCore.length + " threads · peak " + root.percent(metrics.coreMaximum)
            }

            Row {
              id: coreStrip
              width: parent.width
              height: Style.space(18)
              spacing: Style.space(3)

              readonly property real cellWidth: metrics.perCore.length > 0
                ? (width - spacing * (metrics.perCore.length - 1)) / metrics.perCore.length
                : 0
              readonly property bool showValues: cellWidth >= Style.space(30)

              Repeater {
                model: metrics.perCore

                Rectangle {
                  id: coreCell
                  required property var modelData

                  readonly property real load: Math.max(0, Math.min(100, modelData.percent)) / 100

                  width: coreStrip.cellWidth
                  height: coreStrip.height
                  radius: Style.cornerRadius
                  color: root.trackColor

                  Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: root.levelColor(coreCell.modelData.percent, root.warningThreshold, root.criticalThreshold)
                    opacity: 0.12 + 0.68 * coreCell.load
                  }

                  Text {
                    anchors.centerIn: parent
                    visible: coreStrip.showValues
                    text: root.percent(coreCell.modelData.percent)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(8)

            ActivityColumn {
              width: parent.width
              title: metrics.activeInterface !== "" ? "NET · " + metrics.activeInterface : "NET"
              downValue: metrics.networkDownBps
              upValue: metrics.networkUpBps
              downPoints: metrics.networkDownHistory
              upPoints: metrics.networkUpHistory
              peak: metrics.networkPeak
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(diskName.implicitHeight, diskRates.implicitHeight)

              PanelSectionHeader {
                id: diskName
                text: root.diskLabelText()
                foreground: root.foreground
                fontFamily: root.fontFamily
                elide: Text.ElideRight
                anchors.left: parent.left
                anchors.right: diskRates.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              Row {
                id: diskRates
                spacing: Style.space(14)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                RateLabel {
                  glyph: "W"
                  glyphColor: root.accent
                  value: metrics.diskWriteBps
                }

                RateLabel {
                  glyph: "R"
                  glyphColor: root.secondary
                  value: metrics.diskReadBps
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(6)

            SectionHeading { title: "CAPACITY" }

            CapacityRow {
              label: "Root filesystem"
              value: root.formatPair(metrics.filesystemUsed, metrics.filesystemTotal)
              percentValue: metrics.filesystemPercent
            }

            CapacityRow {
              visible: metrics.swapTotal > 0
              label: "Swap"
              value: root.formatPair(metrics.swapUsed, metrics.swapTotal)
              percentValue: metrics.swapPercent
            }

            Repeater {
              model: metrics.extraFilesystems

              CapacityRow {
                required property var modelData
                label: root.mountLabel(modelData.mount)
                value: root.formatPair(modelData.used, modelData.total)
                percentValue: modelData.percent
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Row {
            width: parent.width
            spacing: Style.space(8)

            ActionButton {
              root: panel.root
              width: (parent.width - parent.spacing) / 2
              index: 0
              iconText: "󰑖"
              text: "Bar · " + root.modeLabel()
              tooltipText: "Cycle bar display — also right-click the widget"
              onClicked: root.cycleBarMode()
            }

            ActionButton {
              root: panel.root
              width: (parent.width - parent.spacing) / 2
              index: 1
              iconText: "󰆍"
              text: "Open btop"
              tooltipText: "Open btop (B)"
              onClicked: root.launchBtop()
            }
          }
        }
      }
    }


  component SectionHeading: Item {
    property string title: ""
    property string value: ""

    width: parent ? parent.width : 0
    implicitHeight: Math.max(headingText.implicitHeight, valueText.implicitHeight)

    PanelSectionHeader {
      id: headingText
      text: title
      textFormat: Text.PlainText
      foreground: root.foreground
      fontFamily: root.fontFamily
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.right: valueText.visible ? valueText.left : parent.right
      anchors.rightMargin: valueText.visible ? Style.space(8) : 0
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: valueText
      text: value
      visible: text !== ""
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      elide: Text.ElideRight
      width: Math.min(implicitWidth, parent.width * 0.62)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
    }
  }

  component Meter: Rectangle {
    id: meter
    property real value: -1
    property real maximum: 100
    property color fillColor: root.accent

    height: Style.space(3)
    radius: height / 2
    color: root.trackColor

    Rectangle {
      width: meter.width * Math.max(0, Math.min(1, meter.value / meter.maximum))
      height: meter.height
      radius: meter.radius
      color: meter.fillColor

      Behavior on width {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
      }
    }
  }

  component StatTile: BorderSurface {
    id: tile
    property string title: ""
    property string value: "—"
    property string detail: ""
    property real meter: -1
    property color meterColor: root.accent
    property bool alarming: false

    height: Style.space(80)
    radius: Style.cornerRadius
    color: Style.normalFillFor(root.foreground, root.accent)
    borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(9)
      spacing: Style.space(2)

      Text {
        text: tile.title
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }

      Text {
        text: tile.value
        color: tile.alarming ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Text {
        width: parent.width
        text: tile.detail
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Meter {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: Style.space(9)
      value: tile.meter
      fillColor: tile.meterColor
    }
  }

  component LegendDot: Row {
    property color colorValue: "white"
    property string label: ""
    spacing: Style.space(4)

    Rectangle {
      width: Style.space(6)
      height: width
      radius: width / 2
      color: parent.colorValue
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      text: parent.label
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  component ActivityColumn: Column {
    id: activity
    property string title: ""
    property real downValue: -1
    property real upValue: -1
    property var downPoints: []
    property var upPoints: []
    property real peak: 0

    spacing: Style.space(4)

    SectionHeading {
      title: activity.title
      value: activity.peak > 0 ? "±" + root.formatRate(activity.peak) : ""
    }

    Item {
      width: parent.width
      implicitHeight: Math.max(upRate.implicitHeight, downRate.implicitHeight)

      RateLabel {
        id: upRate
        anchors.left: parent.left
        glyph: "↑"
        glyphColor: root.accent
        value: activity.upValue
      }

      RateLabel {
        id: downRate
        anchors.right: parent.right
        glyph: "↓"
        glyphColor: root.secondary
        value: activity.downValue
      }
    }

    Sparkline {
      width: parent.width
      height: Style.space(34)
      points: activity.upPoints
      mirrorPoints: activity.downPoints
      lineColor: root.accent
      mirrorLineColor: root.secondary
      gridColor: root.chartGrid
      fixedMaximum: activity.peak
    }
  }

  component RateLabel: Row {
    id: rate
    property string glyph: ""
    property color glyphColor: root.accent
    property real value: -1
    spacing: Style.space(4)

    Text {
      text: rate.glyph
      color: rate.glyphColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Text {
      text: root.formatRate(rate.value)
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  component SensorRow: Column {
    id: sensorRow
    property string label: ""
    property string value: "—"
    property real meter: -1
    property color meterColor: root.accent

    width: parent ? parent.width : 0
    spacing: Style.space(3)

    Item {
      width: parent.width
      implicitHeight: Math.max(sensorLabel.implicitHeight, sensorValue.implicitHeight)

      Text {
        id: sensorLabel
        text: sensorRow.label
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: sensorValue
        text: sensorRow.value
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Meter {
      width: parent.width
      visible: sensorRow.meter >= 0
      value: sensorRow.meter
      fillColor: sensorRow.meterColor
    }
  }

  component CapacityRow: Column {
    id: capacity
    property string label: ""
    property string value: "—"
    property real percentValue: -1

    width: parent ? parent.width : 0
    spacing: Style.space(3)

    Item {
      width: parent.width
      implicitHeight: Math.max(capacityLabel.implicitHeight, capacityValue.implicitHeight)

      Text {
        id: capacityLabel
        text: capacity.label
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: capacityValue
        text: capacity.value
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Meter {
      width: parent.width
      value: capacity.percentValue
      fillColor: root.levelColor(capacity.percentValue, root.warningThreshold, root.criticalThreshold)
    }
  }

}
