import QtQuick
import qs.Commons
import qs.Ui

Button {
    id: actionButton
    property int index: -1

    bordered: true
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    iconSize: Style.font.icon
    hasCursor: root.cursorActive && root.selectedIndex === actionButton.index
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(actionButton)
    onHovered: function(isHovered) {
      if (!isHovered) return
      root.cursorActive = true
      root.selectedIndex = actionButton.index
    }
    property var root
}
