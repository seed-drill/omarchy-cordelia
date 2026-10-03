import QtQuick
import Quickshell.Io

// The Cordelia mark (assets/cordelia-mark.svg), in one colour. The file is
// stroked in currentColor, which Qt draws black. So the file's text is given
// to Qt with the colour asked for in that word's place: whatever is at that
// path is what is drawn, in the colour of the bar around it.
Item {
  id: root

  property color color: "white"
  property string drawing: ""

  function hex(c) {
    function two(v) {
      var s = Math.round(v * 255).toString(16)
      return s.length < 2 ? "0" + s : s
    }
    return "#" + two(c.r) + two(c.g) + two(c.b)
  }

  FileView {
    path: Qt.resolvedUrl("assets/cordelia-mark.svg")
    watchChanges: true
    printErrors: false
    onLoaded: root.drawing = text()
    onFileChanged: reload()
  }

  Image {
    anchors.fill: parent
    fillMode: Image.PreserveAspectFit
    visible: root.drawing !== ""
    opacity: root.color.a
    source: root.drawing === "" ? ""
      : "data:image/svg+xml;utf8," + encodeURIComponent(root.drawing.replace(/currentColor/g, root.hex(root.color)))
    // Drawn at the pixels it is shown at, so it stays sharp at any scale.
    sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
    sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
  }
}
