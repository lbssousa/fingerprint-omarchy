import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The test area under the grid: one tile that starts a verification and
// shows how it went. Fingerprint.qml decides the message; this draws it.
BorderSurface {
  id: area

  property string title: ""
  property string message: ""
  // "idle", "info" (scanning), "success" or "error".
  property string tone: "idle"
  property bool running: false
  property bool hasCursor: false
  property bool interactive: true

  property string fontFamily: Style.font.menuFamily
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent

  readonly property color toneColor: tone === "error" ? urgent : tone === "success" || running ? accent : foreground

  signal activated()
  signal hovered()

  implicitHeight: Math.max(Style.space(64), content.implicitHeight + Style.spacing.lg * 2 + contentTopInset + contentBottomInset)
  radius: Style.cornerRadius
  opacity: interactive || running ? 1 : 0.6
  color: mouse.pressed ? Style.pressedFillFor(foreground, accent)
    : (hasCursor || mouse.containsMouse) && interactive ? Style.hoverFillFor(foreground, accent)
    : "transparent"
  borderSpec: hasCursor ? Border.controlSpec("hover-cursor", foreground, accent)
    : Border.controlSpec("normal", foreground, accent)

  Behavior on color { ColorAnimation { duration: Style.duration(120) } }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: area.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
    onContainsMouseChanged: if (containsMouse) area.hovered()
    onClicked: if (area.interactive) area.activated()
  }

  Row {
    id: content
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: area.contentLeftInset + Style.spacing.controlPaddingX
    anchors.rightMargin: area.contentRightInset + Style.spacing.controlPaddingX
    spacing: Style.spacing.xxl

    Text {
      id: glyph
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: area.tone === "success" ? "󰄬" : area.tone === "error" ? "󰀦" : "󰈷"
      color: area.toneColor
      font.family: area.fontFamily
      font.pixelSize: Style.font.display

      SequentialAnimation on opacity {
        running: area.running && !Style.reduceMotion
        loops: Animation.Infinite
        onRunningChanged: if (!running) glyph.opacity = 1
        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - glyph.width - parent.spacing
      spacing: Style.spacing.xs

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: area.title
        horizontalAlignment: Text.AlignLeft
        color: area.foreground
        font.family: area.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: area.hasCursor
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: area.message
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignLeft
        color: area.tone === "error" || area.tone === "success" ? area.toneColor : area.foreground
        opacity: area.tone === "idle" ? 0.7 : 1
        font.family: area.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
