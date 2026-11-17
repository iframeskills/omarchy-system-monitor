import QtQuick
import Quickshell

ShellRoot {
  id: shell

  readonly property var curveInputs: ({ "Low W": 12, "High W": 40, "Min RPM": 1500, "Max RPM": 4000, "Floor RPM": 800 })

  function walk(node, depth, visit) {
    if (!node || depth > 80) return
    visit(node)
    var lists = [node.children, node.data, node.resources, node.contentItem ? [node.contentItem] : []]
    for (var l = 0; l < lists.length; l++) {
      var list = lists[l]
      if (!list) continue
      for (var i = 0; i < list.length; i++) walk(list[i], depth + 1, visit)
    }
  }

  function report(line) {
    console.log("SMOKE " + line)
    Qt.quit()
  }

  Loader {
    id: loader
    source: "file://" + Quickshell.env("SMOKE_PLUGIN_DIR") + "/Panel.qml"
    onStatusChanged: if (status === Loader.Error) shell.report("load-error")
  }

  Timer {
    interval: 1000
    running: true
    onTriggered: {
      if (!loader.item) { shell.report("load-error"); return }
      var apply = null
      var filled = 0
      shell.walk(loader.item, 0, function(node) {
        if (node.text === "Apply" && typeof node.clicked === "function") apply = node
        if (node.field && shell.curveInputs[node.label] !== undefined && node.field.value !== shell.curveInputs[node.label]) {
          node.field.value = shell.curveInputs[node.label]
          filled++
        }
      })
      if (!apply) { shell.report("no-apply-button"); return }
      if (filled !== 5) { shell.report("curve-fields " + filled); return }
      apply.clicked()
      Qt.callLater(function() { shell.report("clicked") })
    }
  }
}
