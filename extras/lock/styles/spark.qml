import QtQuick
import QtQuick.Particles

// Afterburn lock-screen embers, style "spark" (Voltage): quick, snappy crackle.
//
// Same rules as ../EmberLayer.qml (the "rise" style): pure QtQuick + QtQuick.Particles, input-transparent,
// everything gated on `active`. The three colours (#ffc48a, #ff5a1f, #7a3e16) are the base orange: the
// theme-set hook rewrites them to the theme's colours through lock-embers.sh recolor.
//
// Motion: about 30 short streaks a second, each living under a second, fired up in a +-35 degree fan at
// 70 to 190 px/s with a lateral jitter that changes constantly. The glow does not breathe: it flickers
// every 40 to 160 ms, hard. About 25 alive at a time, a fraction of the rise style's 110.
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

    // Almost no easing: the flicker should snap.
    Behavior on opacity { NumberAnimation { duration: 40; easing.type: Easing.OutQuad } }
  }

  // Irregular, hard flicker: a new glow strength every 40 to 160 ms.
  Timer {
    running: root.active
    repeat: true
    interval: 60
    triggeredOnStart: true
    onTriggered: {
      interval = 40 + Math.floor(Math.random() * 120)
      glow.opacity = 0.06 + Math.random() * 0.3
    }
  }

  ParticleSystem {
    id: sparkSystem
    running: root.active

    // 30 a second x ~0.8 s = about 25 alive. 80 is the hard ceiling.
    Emitter {
      id: sparks
      group: "ember"
      enabled: root.active
      x: 0
      y: root.height - 6
      width: root.width
      height: 6
      emitRate: 30
      lifeSpan: 800
      lifeSpanVariation: 300
      maximumEmitted: 80
      velocity: AngleDirection {
        angle: -90
        angleVariation: 35
        magnitude: 130
        magnitudeVariation: 60
      }
    }

    // The jitter: a sideways kick to each spark's velocity, many times a second.
    Wander {
      groups: ["ember"]
      affectedParameter: Wander.Velocity
      pace: 400
      xVariance: 70
      yVariance: 0
    }

    // Each spark is a thin streak. The colour goes flare -> ember -> rust within its short life.
    ItemParticle {
      system: sparkSystem
      groups: ["ember"]
      fade: true

      delegate: Component {
        Item {
          id: spark

          property color tint

          width: 4
          height: 12
          scale: 0.6 + Math.random() * 0.8

          Rectangle {
            x: 1
            width: 2
            height: parent.height
            radius: 1
            color: spark.tint
          }

          SequentialAnimation on tint {
            ColorAnimation { from: "#ffc48a"; to: "#ff5a1f"; duration: 320; easing.type: Easing.OutQuad }
            ColorAnimation { to: "#7a3e16"; duration: 480; easing.type: Easing.InQuad }
          }
        }
      }
    }
  }
}
