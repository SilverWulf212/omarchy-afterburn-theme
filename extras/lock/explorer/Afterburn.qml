// afterburn:lock-explorer  (written by Afterburn's lock-embers.sh; uninstall.sh removes it. Edits are overwritten.)
// The Afterburn lock for Lock Screen Explorer (io.github.sirjul1337.lock-explorer): the blurred wallpaper,
// Afterburn's ember layer from ./afterburn/ (recoloured with the theme), a clock and the password field.
import QtQuick
import qs.Commons
import qs.Commons as Commons
import "../plugins/io.github.sirjul1337.lock-explorer/designs"
import "afterburn"

DesignBase {
  id: lock
  inputItem: field.input

  Wallpaper { anchors.fill: parent; lock: lock; blur: 0.8; dim: 0.1 }

  // Input-transparent: it has no MouseArea, so clicks and keys reach the field.
  EmberLayer { anchors.fill: parent }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onClicked: { lock.wakeRequested(); lock.forcePasswordFocus() }
    onPositionChanged: lock.wakeRequested()
  }

  Column {
    anchors.centerIn: parent
    spacing: 28

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: lock.clock("HH:mm")
      color: Commons.Color.lock.text
      font.family: Style.font.family
      font.pixelSize: Math.round(Style.font.baseSize * 8)
      font.weight: Font.DemiBold
    }

    PasswordField {
      id: field
      lock: lock
      anchors.horizontalCenter: parent.horizontalCenter
      width: 380
      height: 56
      placeholder: lock.tr("Enter Password")
    }
  }
}
