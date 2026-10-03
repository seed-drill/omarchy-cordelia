import QtQuick
import QtQuick.Effects

// The Cordelia mark (assets/cordelia-mark.svg), in one colour. The file is
// stroked in currentColor, which Qt draws black, so an effect gives it the
// colour asked for: the way the bar's tray recolours symbolic icons. Whatever
// is at that path is what is drawn.
Item {
  id: root

  property color color: "white"

  Image {
    id: image
    anchors.fill: parent
    fillMode: Image.PreserveAspectFit
    source: Qt.resolvedUrl("assets/cordelia-mark.svg")
    // Drawn at the pixels it is shown at, so it stays sharp at any scale.
    sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
    sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
    // Hidden: the effect samples it as a texture.
    visible: false
    layer.enabled: true
  }

  MultiEffect {
    anchors.fill: image
    source: image
    colorization: 1.0
    colorizationColor: root.color
  }
}
