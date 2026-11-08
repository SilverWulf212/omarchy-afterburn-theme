import QtQuick
import QtQuick.Particles

// Afterburn lock-screen embers, style "drift" (Phantom): barely there.
//
// Same rules as ../EmberLayer.qml (the "rise" style): pure QtQuick + QtQuick.Particles, input-transparent,
// everything gated on `active`. The three colours (#ffc48a, #ff5a1f, #7a3e16) are the base orange: the
// theme-set hook rewrites them to the theme's colours through lock-embers.sh recolor.
//
// Motion: about 6 wisps a second, each living a fixed 12 s, rising at only ~14 px/s while swaying
// 18 to 30 px sideways on a slow sine (4 to 7 s a swing). Each fades in over 1.5 s and out over its
// last 3 s, so nothing ever pops. The glow does not flicker: its strength wanders slowly. About 72 alive.
Item {
  id: root

  readonly property bool active: root.visible

  Item {
    id: glow

    width: root.width * 0.9
    height: root.height * 0.42
    anchors.horizontalCenter: root.horizontalCenter
    anchors.bottom: root.bottom
    anchors.bottomMargin: -height * 0.25
    transformOrigin: Item.Bottom
    opacity: 0.16

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

    SequentialAnimation on scale {
      running: root.active
      loops: Animation.Infinite
      NumberAnimation { to: 1.04; duration: 9000; easing.type: Easing.InOutSine }
      NumberAnimation { to: 0.97; duration: 9000; easing.type: Easing.InOutSine }
    }

    // The long ease turns each new strength into a slow swell.
    Behavior on opacity { NumberAnimation { duration: 2200; easing.type: Easing.InOutSine } }
  }

  // A new glow strength every 2.5 to 5 s, eased in over 2.2 s.
  Timer {
    running: root.active
    repeat: true
    interval: 150
    triggeredOnStart: true
    onTriggered: {
      interval = 2500 + Math.floor(Math.random() * 2500)
      glow.opacity = 0.1 + Math.random() * 0.1
    }
  }

  ParticleSystem {
    id: wispSystem
    running: root.active

    // 6 a second x 12 s = about 72 alive. 100 is the hard ceiling. lifeSpanVariation is 0 on purpose:
    // the fade-out in the delegate is timed to exactly 12 s.
    Emitter {
      id: wisps
      group: "ember"
      enabled: root.active
      x: 0
      y: root.height - 6
      width: root.width
      height: 6
      emitRate: 6
      lifeSpan: 12000
      lifeSpanVariation: 0
      maximumEmitted: 100
      velocity: AngleDirection {
        angle: -90
        angleVariation: 6
        magnitude: 14
        magnitudeVariation: 6
      }
    }

    // The colour ramps flare -> ember -> rust over the 12 s. The envelope is the delegate's own, so the
    // particle system's `fade` stays off.
    ItemParticle {
      system: wispSystem
      groups: ["ember"]
      fade: false

      delegate: Component {
        Item {
          id: wisp

          property color tint

          width: 12
          height: 12
          scale: 0.5 + Math.random() * 0.7

          // The sway and the fade live on an inner item, because the particle system owns the outer one.
          Item {
            id: body

            property real amp: 18 + Math.random() * 12
            property real swing: 2000 + Math.random() * 1500

            width: 12
            height: 12
            x: -amp

            Rectangle {
              anchors.fill: parent
              radius: width / 2
              color: Qt.alpha(wisp.tint, 0.15)
            }
            Rectangle {
              anchors.centerIn: parent
              width: 5
              height: 5
              radius: width / 2
              color: wisp.tint
            }

            SequentialAnimation on x {
              loops: Animation.Infinite
              NumberAnimation { to: body.amp; duration: body.swing; easing.type: Easing.InOutSine }
              NumberAnimation { to: -body.amp; duration: body.swing; easing.type: Easing.InOutSine }
            }
            SequentialAnimation on opacity {
              NumberAnimation { from: 0.0; to: 0.9; duration: 1500; easing.type: Easing.InQuad }
              PauseAnimation { duration: 7500 }
              NumberAnimation { to: 0.0; duration: 3000; easing.type: Easing.OutQuad }
            }
          }

          SequentialAnimation on tint {
            ColorAnimation { from: "#ffc48a"; to: "#ff5a1f"; duration: 4000; easing.type: Easing.InOutSine }
            ColorAnimation { to: "#7a3e16"; duration: 8000; easing.type: Easing.InOutSine }
          }
        }
      }
    }
  }
}
