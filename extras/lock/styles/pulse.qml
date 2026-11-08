pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Particles

// Afterburn lock-screen embers, style "pulse" (Overdrive): smooth glides, pulsing like a beat.
//
// Same rules as ../EmberLayer.qml (the "rise" style): pure QtQuick + QtQuick.Particles, input-transparent,
// everything gated on `active`. The three colours (#ffc48a, #ff5a1f, #7a3e16) are the base orange: the
// theme-set hook rewrites them to the theme's colours through lock-embers.sh recolor.
//
// Motion: a steady beat at 110 BPM (one every 545 ms). On each beat the glow swells and settles (sharp
// attack, smooth release) and a row of 5 embers is let go from the bottom edge, so they rise in even
// waves. They glide up straight and slowly (~40 px/s) and each one swells slightly with every beat.
// 5 per beat x 8 s = about 73 alive, fewer than the rise style's 110. The swell is gentle on purpose.
Item {
  id: root

  readonly property bool active: root.visible

  // 0 to 1: the beat. Fast up, slower down. The glow and every ember follow it.
  property real beat: 0

  Item {
    id: glow

    width: root.width * 0.9
    height: root.height * 0.42
    anchors.horizontalCenter: root.horizontalCenter
    anchors.bottom: root.bottom
    anchors.bottomMargin: -height * 0.25
    transformOrigin: Item.Bottom
    opacity: 0.12 + 0.16 * root.beat
    scale: 0.98 + 0.05 * root.beat

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
  }

  SequentialAnimation {
    id: beatAnim
    NumberAnimation { target: root; property: "beat"; to: 1; duration: 60; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "beat"; to: 0; duration: 460; easing.type: Easing.InQuad }
  }

  // 60000 / 110 BPM = 545 ms.
  Timer {
    running: root.active
    repeat: true
    interval: 545
    onTriggered: {
      beatAnim.restart()
      pulses.burst(5)
    }
  }

  ParticleSystem {
    id: pulseSystem
    running: root.active

    // emitRate 0: a row of embers comes from burst() on every beat. 120 is the hard ceiling.
    Emitter {
      id: pulses
      group: "ember"
      enabled: root.active
      x: 0
      y: root.height - 6
      width: root.width
      height: 6
      emitRate: 0
      lifeSpan: 8000
      lifeSpanVariation: 600
      maximumEmitted: 120
      velocity: AngleDirection {
        angle: -90
        angleVariation: 5
        magnitude: 40
        magnitudeVariation: 5
      }
    }

    // Same two circles as the rise style. The colour ramps flare -> ember -> rust over ~8 s.
    ItemParticle {
      system: pulseSystem
      groups: ["ember"]
      fade: true

      delegate: Component {
        Item {
          id: ember

          property color tint
          property real size: 0.5 + Math.random() * 0.8

          width: 12
          height: 12
          scale: size * (1 + 0.25 * root.beat)

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
            ColorAnimation { from: "#ffc48a"; to: "#ff5a1f"; duration: 3000; easing.type: Easing.InOutSine }
            ColorAnimation { to: "#7a3e16"; duration: 5000; easing.type: Easing.InOutSine }
          }
        }
      }
    }
  }
}
