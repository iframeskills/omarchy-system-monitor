import QtQuick

Item {
  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property bool open: false
  property Item focusTarget: null
  property int contentWidth: 0
  property int contentHeight: 0
  default property alias contentItem: contentHolder.children

  function fittedContentWidth(width, cap) { return Math.round(Number(width) || 1) }
  function fittedContentHeight(implicitHeight, cap) { return Math.round(Number(implicitHeight) || 0) }

  Item {
    id: contentHolder
    anchors.fill: parent
  }
}
