import QtQuick
import QtQuick.Shapes
import qs.Commons

// The big fingerprint of Omarchy's fingerprint panel (omarchy.fingerprint,
// Omarchy 4.6, MIT), drawn the same way: five ridges that light up from the
// core outward as `progress` grows, and, while `noise` is above 0, the
// scratchy transmission (the print torn into bands under a scatter of
// scratches). The view that holds it drives `noise` and `frame`.
Item {
  id: stage

  // How much of the print is lit, 0 to 1.
  property real progress: 0
  property color tone: "white"
  property real noise: 0
  property int frame: 0

  readonly property int bandCount: 14

  Item {
    id: whorl

    // The print as five ridges on a 24-unit grid, core first, each one the
    // centre line of a ridge of the Material Design fingerprint icon (Apache
    // 2.0), drawn one unit wide, with its length in those units.
    readonly property var ridges: [
      { length: 8.82, path: "M11.94 14.66C11.94 16.25 12.75 17.7 14.1 18.63C14.9 19.17 15.85 19.44 16.92 19.44C17.2 19.44 17.6 19.4 18.05 19.33" },
      { length: 23.25, path: "M9.75 21.29C8.9 20.4 8.45 19.9 7.83 18.8C7.2 17.65 6.84 16.2 6.84 14.66C6.84 11.96 9.15 9.77 12 9.77C14.85 9.77 17.16 11.96 17.16 14.66" },
      { length: 52.72, path: "M14.91 21.5C13.4 21.08 12.4 20.5 11.4 19.5C10.1 18.2 9.39 16.5 9.39 14.66C9.39 13.3 10.55 12.22 11.97 12.22C13.39 12.22 14.55 13.3 14.55 14.66C14.55 16 15.7 17.1 17.13 17.1C18.56 17.1 19.71 16 19.71 14.66C19.71 10.6 16.25 7.33 12 7.33C8.95 7.33 6.2 9.03 4.94 11.65C4.5 12.55 4.3 13.55 4.3 14.66C4.3 15.5 4.4 16.8 5 18.4" },
      { length: 19.81, path: "M3.5 9.22C4.45 7.9 5.65 6.85 7.07 6.1C10.1 4.55 14 4.55 17 6.1C18.4 6.85 19.6 7.9 20.5 9.22" },
      { length: 12.11, path: "M6.2 3.97C7.9 3 9.9 2.5 12.01 2.5C14.1 2.5 15.9 2.95 17.81 3.97" }
    ]
    readonly property real ridgeTotal: {
      var total = 0
      for (var i = 0; i < ridges.length; i++) total += ridges[i].length
      return total
    }
    // Every accepted touch lights the same length of ridge, however many
    // touches this reader asks for.
    property real filled: stage.progress

    Behavior on filled {
      NumberAnimation { duration: Style.duration(280); easing.type: Easing.OutCubic }
    }

    anchors.fill: parent

    Repeater {
      model: whorl.ridges

      Shape {
        id: ridge
        required property var modelData
        required property int index
        // The length of ridge before this one, and how much of this one is lit.
        readonly property real before: {
          var sum = 0
          for (var i = 0; i < index; i++) sum += whorl.ridges[i].length
          return sum
        }
        readonly property real lit: Math.max(0, Math.min(modelData.length, whorl.filled * whorl.ridgeTotal - before))

        // Drawn on the 24-unit grid and scaled up, stroke and all.
        width: 24
        height: 24
        transform: Scale { xScale: whorl.width / 24; yScale: whorl.height / 24 }
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          strokeWidth: 1
          strokeColor: Qt.rgba(1, 1, 1, 0.3)
          fillColor: "transparent"
          capStyle: ShapePath.RoundCap
          PathSvg { path: ridge.modelData.path }
        }
        // The lit length, as the first dash of a pattern whose gap outruns
        // the ridge. Dashes are measured in stroke widths, here one unit.
        ShapePath {
          strokeWidth: 1
          strokeColor: ridge.lit > 0.01 ? stage.tone : "transparent"
          fillColor: "transparent"
          capStyle: ShapePath.RoundCap
          strokeStyle: ShapePath.DashLine
          dashPattern: [Math.max(0.01, ridge.lit), 1000]
          PathSvg { path: ridge.modelData.path }
        }
      }
    }
  }

  // The transmission: while it settles, the print is shown as bands torn
  // sideways, dropping out and coming back, under a scatter of scratches.
  Repeater {
    model: stage.noise > 0 ? stage.bandCount : 0

    ShaderEffectSource {
      required property int index
      readonly property real band: stage.height / stage.bandCount

      sourceItem: whorl
      hideSource: true
      sourceRect: Qt.rect(0, index * band, stage.width, band)
      y: index * band
      width: stage.width
      height: band
      x: { stage.frame; return (Math.random() - 0.5) * (Math.random() < 0.35 ? 2.4 : 0.5) * Style.space(70) * stage.noise }
      opacity: { stage.frame; return Math.random() < stage.noise * 0.5 ? 0.15 : 1 }
    }
  }

  Repeater {
    model: stage.noise > 0 ? 18 : 0

    Rectangle {
      x: { stage.frame; return -Style.space(120) + Math.random() * (stage.width + Style.space(160)) }
      y: { stage.frame; return Math.random() * stage.height }
      width: { stage.frame; return Style.space(6) + Math.random() * Style.space(90) }
      height: Math.max(1, Style.space(1))
      color: "white"
      opacity: { stage.frame; return Math.random() * 0.5 * stage.noise }
    }
  }
}
