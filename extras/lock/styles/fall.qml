import QtQuick
import QtQuick.Particles

// Afterburn lock-screen embers, style "fall" (Cyber): slow digital rain.
//
// Same rules as ../EmberLayer.qml (the "rise" style): pure QtQuick + QtQuick.Particles, input-transparent,
// everything gated on `active`. The three colours (#ffc48a, #ff5a1f, #7a3e16) are the base orange: the
// theme-set hook rewrites them to the theme's colours through lock-embers.sh recolor.
//
// Motion: streaks fall from the top edge at an even, unhurried pace (~70 px/s), with a few pixels of
// sideways wander, and each one blinks once or twice on the way down like a terminal glyph. About 7 new
// streaks a second living ~14 s, so roughly 100 alive (the rise style keeps about 110). The soft glow sits
// on the top edge, where the rain starts, and flickers slowly.
Item {
  id: root

  readonly property bool active: root.visible

  Item {
    id: glow

    width: root.width * 0.9
    height: root.height * 0.42
    anchors.horizontalCenter: root.horizontalCenter
    anchors.top: root.top
    anchors.topMargin: -height * 0.25
    transformOrigin: Item.Top
    opacity: 0.18

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

    // A slower, shallower breath than the rise style.
    SequentialAnimation on scale {
      running: root.active
      loops: Animation.Infinite
      NumberAnimation { to: 1.03; duration: 7600; easing.type: Easing.InOutSine }
      NumberAnimation { to: 0.98; duration: 7600; easing.type: Easing.InOutSine }
    }

    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutQuad } }
  }

  // Soft, slow flicker: a new glow strength every 0.4 to 1 s.
  Timer {
    running: root.active
    repeat: true
    interval: 400
    triggeredOnStart: true
    onTriggered: {
      interval = 400 + Math.floor(Math.random() * 600)
      glow.opacity = 0.12 + Math.random() * 0.1
    }
  }

  ParticleSystem {
    id: rainSystem
    running: root.active

    // ~7 a second, each living ~14 s: about 100 alive at steady state. 120 is the hard ceiling.
    Emitter {
      id: rain
      group: "ember"
      enabled: root.active
      x: 0
      y: -8
      width: root.width
      height: 6
      emitRate: 7
      lifeSpan: 14000
      lifeSpanVariation: 2000
      maximumEmitted: 120
      velocity: AngleDirection {
        angle: 90
        angleVariation: 2
        magnitude: 70
        magnitudeVariation: 25
      }
    }

    // A few pixels of sideways wander, like rain on a slightly uneven pane.
    Wander {
      groups: ["ember"]
      affectedParameter: Wander.Position
      pace: 20
      xVariance: 5
      yVariance: 0
    }

    // Each streak: a fading tail and a bright head. The colour ramps flare -> ember -> rust over its life.
    ItemParticle {
      system: rainSystem
      groups: ["ember"]
      fade: true

      delegate: Component {
        Item {
          id: drop

          property color tint

          width: 8
          height: 36
          scale: 0.7 + Math.random() * 0.7

          // The blink lives on an inner item, because the particle system owns the outer item's opacity.
          Item {
            anchors.fill: parent

            Rectangle {
              x: 3
              width: 2
              height: parent.height - 3
              radius: 1
              gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha(drop.tint, 0.0) }
                GradientStop { position: 1.0; color: Qt.alpha(drop.tint, 0.7) }
              }
            }
            Rectangle {
              x: 2
              y: parent.height - 4
              width: 4
              height: 4
              radius: 2
              color: drop.tint
            }

            SequentialAnimation on opacity {
              PauseAnimation { duration: Math.floor(Math.random() * 4000) }
              SequentialAnimation {
                loops: 1 + Math.floor(Math.random() * 2)
                NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
              }
            }
          }

          SequentialAnimation on tint {
            ColorAnimation { from: "#ffc48a"; to: "#ff5a1f"; duration: 5500; easing.type: Easing.InOutSine }
            ColorAnimation { to: "#7a3e16"; duration: 8500; easing.type: Easing.InOutSine }
          }
        }
      }
    }
  }
}
