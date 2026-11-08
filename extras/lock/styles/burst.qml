import QtQuick
import QtQuick.Particles

// Afterburn lock-screen embers, style "burst" (Redline): sharp, sudden bursts, then stillness.
//
// Same rules as ../EmberLayer.qml (the "rise" style): pure QtQuick + QtQuick.Particles, input-transparent,
// everything gated on `active`. The three colours (#ffc48a, #ff5a1f, #7a3e16) are the base orange: the
// theme-set hook rewrites them to the theme's colours through lock-embers.sh recolor.
//
// Motion: nothing moves for 2 to 5 s. Then a burst of 8 to 15 sparks shoots up from one stretch of the
// bottom edge at 220 to 460 px/s, arcs over under gravity and cools to nothing in under a second, while
// the glow flashes and snaps back. At most about 15 particles exist at a time, and none between bursts.
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
    opacity: 0.1

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

  // The flash: up in 40 ms, back to the resting glow in 0.8 s.
  SequentialAnimation {
    id: flash
    NumberAnimation { target: glow; property: "opacity"; to: 0.42; duration: 40; easing.type: Easing.OutQuad }
    NumberAnimation { target: glow; property: "opacity"; to: 0.1; duration: 800; easing.type: Easing.OutQuad }
  }

  // A burst every 2 to 5 s, from a different stretch of the bottom edge each time. The first one comes
  // 1.5 s after the layer shows, so the lock screen does not open on a still frame for long.
  Timer {
    running: root.active
    repeat: true
    interval: 1500
    onTriggered: {
      interval = 2000 + Math.floor(Math.random() * 3000)
      sparks.x = root.width * (0.08 + Math.random() * 0.64)
      sparks.burst(8 + Math.floor(Math.random() * 8))
      flash.restart()
    }
  }

  ParticleSystem {
    id: sparkSystem
    running: root.active

    // emitRate 0: sparks only come from burst(). 40 is the hard ceiling.
    Emitter {
      id: sparks
      group: "ember"
      enabled: root.active
      x: 0
      y: root.height - 6
      width: root.width * 0.2
      height: 6
      emitRate: 0
      lifeSpan: 900
      lifeSpanVariation: 300
      maximumEmitted: 40
      velocity: AngleDirection {
        angle: -90
        angleVariation: 40
        magnitude: 340
        magnitudeVariation: 120
      }
    }

    // They arc up and fall back.
    Gravity {
      groups: ["ember"]
      angle: 90
      magnitude: 520
    }

    // Each spark is a small hot dot with a faint halo; the colour goes flare -> ember -> rust.
    ItemParticle {
      system: sparkSystem
      groups: ["ember"]
      fade: true

      delegate: Component {
        Item {
          id: spark

          property color tint

          width: 8
          height: 8
          scale: 0.6 + Math.random() * 0.6

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.alpha(spark.tint, 0.2)
          }
          Rectangle {
            anchors.centerIn: parent
            width: 3
            height: 3
            radius: width / 2
            color: spark.tint
          }

          SequentialAnimation on tint {
            ColorAnimation { from: "#ffc48a"; to: "#ff5a1f"; duration: 250; easing.type: Easing.OutQuad }
            ColorAnimation { to: "#7a3e16"; duration: 650; easing.type: Easing.InQuad }
          }
        }
      }
    }
  }
}
