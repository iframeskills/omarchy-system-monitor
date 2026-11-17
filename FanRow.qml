import QtQuick
import qs.Commons
import qs.Ui

Column {
    id: fanRow
    property string label: ""
    property string rpmText: "—"
    property string rangeText: ""
    property bool manual: false

    width: parent ? parent.width : 0
    spacing: Style.space(3)

    Item {
      width: parent.width
      implicitHeight: Math.max(fanLabel.implicitHeight, fanRpm.implicitHeight)

      Text {
        id: fanLabel
        text: fanRow.label
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: fanRpm
        text: fanRow.rpmText
        textFormat: Text.PlainText
        color: fanRow.manual ? root.warningColor : root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Text {
      visible: fanRow.rangeText !== ""
      text: fanRow.rangeText
      textFormat: Text.PlainText
      color: root.muted
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    property var root
}
