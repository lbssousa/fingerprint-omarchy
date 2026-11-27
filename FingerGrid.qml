import QtQuick
import qs.Commons
import qs.Commons as Commons
import "FingerprintModel.js" as Model

// The six fingers under the print, on the panel's dark scrim: left hand in
// the first column, right hand in the second (mirrored in right-to-left
// languages), thumb to middle finger from the top. A dot says which are
// enrolled. The keyboard cursor lives in Fingerprint.qml; this only draws it
// and reports clicks and hovers.
Item {
  id: grid

  property var strings: null
  property var enrolled: []
  property int cursor: -1
  property int pendingDelete: -1
  property string matchedFinger: ""
  property bool interactive: true

  // The scrim is near-black whatever the theme, so this palette is fixed, as
  // on Omarchy's own fingerprint panel.
  property color ink: "white"
  property color dim: Qt.rgba(1, 1, 1, 0.6)
  property color accent: Commons.Color.accent
  property color urgent: "#ff6b6b"

  readonly property int rowHeight: Math.max(Style.space(40), Style.font.heading + Style.space(16))
  readonly property int headerHeight: Style.font.body + Style.space(14)
  readonly property int columnWidth: Style.space(220)

  signal activated(int index)
  signal deleteRequested(int index)
  signal hovered(int index)

  implicitWidth: columnWidth * 2 + Style.space(32)
  implicitHeight: headerHeight + rowHeight * 3 + Style.space(4) * 2

  function t(key) { return grid.strings ? grid.strings.t(key) : key }
  function isEnrolled(index) { return grid.enrolled.indexOf(Model.FINGERS[index].id) >= 0 }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.space(32)

    Repeater {
      model: ["left", "right"]

      Column {
        id: hand
        required property string modelData
        required property int index

        width: grid.columnWidth
        spacing: Style.space(4)

        Text {
          width: parent.width
          height: grid.headerHeight
          textFormat: Text.PlainText
          text: grid.t(hand.modelData === "left" ? "fingerprint.leftHand" : "fingerprint.rightHand")
          horizontalAlignment: Text.AlignLeft
          verticalAlignment: Text.AlignTop
          color: grid.dim
          opacity: 0.7
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Repeater {
          model: 3

          Rectangle {
            id: row
            required property int index
            readonly property int fingerIndex: hand.index * 3 + index
            readonly property var finger: Model.FINGERS[fingerIndex]
            readonly property bool enrolled: grid.isEnrolled(fingerIndex)
            readonly property bool hasCursor: grid.cursor === fingerIndex
            readonly property bool confirming: grid.pendingDelete === fingerIndex
            readonly property bool matched: grid.matchedFinger === finger.id

            width: hand.width
            height: grid.rowHeight
            radius: Style.cornerRadius
            color: rowMouse.containsMouse || hasCursor ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
            border.width: hasCursor ? 1 : 0
            border.color: confirming ? grid.urgent : grid.ink
            opacity: grid.interactive || hasCursor ? 1 : 0.5

            Behavior on color { ColorAnimation { duration: Style.duration(120) } }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: grid.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
              onContainsMouseChanged: if (containsMouse) grid.hovered(row.fingerIndex)
              onClicked: if (grid.interactive) grid.activated(row.fingerIndex)
            }

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(12)

              Text {
                id: digit
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: Commons.I18n.formatNumber(row.fingerIndex + 1)
                color: grid.dim
                opacity: 0.6
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              // Enrolled: a lit dot in the print's colour.
              Rectangle {
                id: dot
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(8)
                height: width
                radius: width / 2
                color: row.confirming ? grid.urgent : row.enrolled ? grid.accent : "transparent"
                border.width: row.enrolled || row.confirming ? 0 : 1
                border.color: grid.dim
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - digit.width - dot.width - trash.width - parent.spacing * 3
                textFormat: Text.PlainText
                text: grid.t("fingerprint." + row.finger.kind)
                horizontalAlignment: Text.AlignLeft
                color: row.confirming ? grid.urgent : row.matched ? grid.accent : row.hasCursor ? grid.ink : grid.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.heading
                elide: Text.ElideRight
              }

              // Delete, for the mouse; the keyboard has Delete.
              Text {
                id: trash
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(24)
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: "󰆴"
                visible: row.enrolled && grid.interactive && (rowMouse.containsMouse || trashMouse.containsMouse || row.hasCursor || row.confirming)
                color: row.confirming || trashMouse.containsMouse ? grid.urgent : grid.dim
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.heading

                MouseArea {
                  id: trashMouse
                  anchors.fill: parent
                  anchors.margins: -Style.space(6)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: grid.deleteRequested(row.fingerIndex)
                }
              }
            }
          }
        }
      }
    }
  }
}
