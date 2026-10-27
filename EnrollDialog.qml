import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The enrollment card: the fingerprint inside a square frame that fills as
// the scans pass, the reader's feedback, and Cancel / Try again / Done.
// Keys are handled by Fingerprint.qml (Escape cancels, Enter finishes or
// retries) so they keep working whatever has focus.
BorderSurface {
  id: dialog

  property var strings: null
  property string title: ""
  property string message: ""
  // "info" while scanning, "success" once enrolled, "error" when it ended without a print.
  property string tone: "info"
  property string stagesText: ""
  property real progress: 0
  readonly property bool finished: tone === "success"
  readonly property bool failed: tone === "error"

  property string fontFamily: Style.font.menuFamily
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent

  readonly property color frameColor: failed ? urgent : accent
  readonly property int frameSize: Style.space(148)

  signal cancelRequested()
  signal doneRequested()
  signal retryRequested()

  onProgressChanged: if (progress > 0) pop.restart()

  function t(key) { return dialog.strings ? dialog.strings.t(key) : key }

  radius: Style.cornerRadius
  padding: Style.spacing.panelPadding
  height: content.implicitHeight + contentTopInset + contentBottomInset

  MouseArea { anchors.fill: parent }

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: dialog.contentTopInset
    anchors.leftMargin: dialog.contentLeftInset
    anchors.rightMargin: dialog.contentRightInset
    spacing: Style.spacing.xxl

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: dialog.title
      horizontalAlignment: Text.AlignHCenter
      color: dialog.foreground
      font.family: dialog.fontFamily
      font.pixelSize: Style.font.heading
      elide: Text.ElideRight
    }

    Item {
      width: parent.width
      height: dialog.frameSize

      SquareProgress {
        id: frame
        anchors.centerIn: parent
        width: dialog.frameSize
        height: dialog.frameSize
        progress: dialog.failed ? 1 : dialog.progress
        lineWidth: Style.space(6)
        cornerRadius: Math.max(Style.cornerRadius, Style.space(22))
        trackColor: Util.alpha(dialog.foreground, 0.14)
        strokeColor: dialog.frameColor
      }

      Text {
        id: glyph
        anchors.centerIn: frame
        textFormat: Text.PlainText
        text: dialog.finished ? "󰄬" : dialog.failed ? "󰀦" : "󰈷"
        color: dialog.finished || dialog.failed ? dialog.frameColor : dialog.foreground
        font.family: dialog.fontFamily
        font.pixelSize: Math.round(dialog.frameSize * 0.46)

        // A small pop each time a scan is accepted.
        SequentialAnimation {
          id: pop
          NumberAnimation { target: glyph; property: "scale"; to: 0.85; duration: Style.duration(90) }
          NumberAnimation { target: glyph; property: "scale"; to: 1; duration: Style.duration(180); easing.type: Easing.OutBack }
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.spacing.sm

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: dialog.message
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        color: dialog.failed ? dialog.urgent : dialog.foreground
        font.family: dialog.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        width: parent.width
        visible: dialog.stagesText !== ""
        textFormat: Text.PlainText
        text: dialog.stagesText
        horizontalAlignment: Text.AlignHCenter
        color: dialog.foreground
        opacity: 0.6
        font.family: dialog.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.spacing.controlGap

      Button {
        visible: !dialog.finished
        text: dialog.t("fingerprint.cancel")
        bordered: true
        onClicked: dialog.cancelRequested()
      }
      Button {
        visible: dialog.failed
        text: dialog.t("fingerprint.tryAgain")
        bordered: true
        selected: true
        onClicked: dialog.retryRequested()
      }
      Button {
        visible: dialog.finished
        text: dialog.t("fingerprint.done")
        bordered: true
        selected: true
        onClicked: dialog.doneRequested()
      }
    }
  }
}
