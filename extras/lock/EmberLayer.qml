import QtQuick
import QtQuick.Particles

// Ambient ember layer for the Afterburn lock screen.
//
// Pure QtQuick + QtQuick.Particles, no video, no image assets. Input-transparent:
// there is no MouseArea, so clicks and keys fall through to the password field.
// The caller sets `anchors.fill: parent` (lock-embers.sh does this).
//
// Everything that costs CPU is gated on `active`, which follows `visible`, so the
// emitter, the timers and the breathing animation all stop while the layer is hidden.
//
// RadialGradient is not used: in Qt 6 it lives in Qt5Compat.GraphicalEffects, which
// would add a module. Soft edges come from stacked translucent circles instead.
Item {
  id: root

  readonly property bool active: root.visible

  // Bottom glow: a faint orange light built from three stacked translucent ellipses.
  Item {
    id: glow

    width: root.width * 0.9
    height: root.height * 0.42
    anchors.horizontalCenter: root.horizontalCenter
    anchors.bottom: root.bottom
    anchors.bottomMargin: -height * 0.25
    transformOrigin: Item.Bottom
    opacity: 0.2

    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: "#14ff5a1f"
    }
    Rectangle {
      anchors.centerIn: parent
      width: parent.width * 0.7
      height: parent.height * 0.7
      radius: height / 2
      color: "#1cff5a1f"
    }
    Rectangle {
      anchors.centerIn: parent
      width: parent.width * 0.4
      height: parent.height * 0.4
      radius: height / 2
      color: "#24ff5a1f"
    }

    // Own scale only, never a parent or sibling: a slow inhale and exhale.
    SequentialAnimation on scale {
      running: root.active
      loops: Animation.Infinite
      NumberAnimation { to: 1.04; duration: 5200; easing.type: Easing.InOutSine }
      NumberAnimation { to: 0.97; duration: 5200; easing.type: Easing.InOutSine }
    }

    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
  }

  // Irregular flicker: a new glow strength every 110 to 370 ms.
  Timer {
    running: root.active
    repeat: true
    interval: 150
    triggeredOnStart: true
    onTriggered: {
      interval = 110 + Math.floor(Math.random() * 260)
      glow.opacity = 0.14 + Math.random() * 0.14
    }
  }

  ParticleSystem {
    id: emberSystem
    running: root.active

    // About 12 embers a second, each living ~9 s, so roughly 110 alive at steady state.
    // maximumEmitted is the hard ceiling at 150.
    Emitter {
      id: embers
      group: "ember"
      enabled: root.active
      x: 0
      y: root.height - 6
      width: root.width
      height: 6
      emitRate: 12
      lifeSpan: 9000
      lifeSpanVariation: 1000
      maximumEmitted: 150
      velocity: AngleDirection {
        angle: -90
        angleVariation: 12
        magnitude: 26
        magnitudeVariation: 12
      }
    }

    // Each ember is a small QML item: a halo and a bright core, both circles.
    // The colour ramps #ffc48a -> #ff5a1f -> #7a3e16 over the first ~9 s of life.
    // `fade` handles the alpha in and out, so no blur or image asset is needed.
    ItemParticle {
      system: emberSystem
      groups: ["ember"]
      fade: true

      delegate: Component {
        Item {
          id: ember

          property color tint

          width: 12
          height: 12
          scale: 0.5 + Math.random() * 0.8

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.alpha(ember.tint, 0.25)
          }
          Rectangle {
            anchors.centerIn: parent
            width: 5
            height: 5
            radius: width / 2
            color: ember.tint
          }

          SequentialAnimation on tint {
            ColorAnimation { from: "#ffc48a"; to: "#ff5a1f"; duration: 3500; easing.type: Easing.InOutSine }
            ColorAnimation { to: "#7a3e16"; duration: 5500; easing.type: Easing.InOutSine }
          }
        }
      }
    }
  }
}
