import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "FingerprintModel.js" as Model

// The six finger tiles: left hand in the first column, right hand in the
// second (mirrored in right-to-left languages), thumb to middle finger from
// the top. The keyboard cursor lives in Fingerprint.qml; this only draws it
// and reports clicks and hovers.
Item {
  id: grid

  property var strings: null
  property var enrolled: []
  property int cursor: -1
  property int pendingDelete: -1
  property string matchedFinger: ""
  property bool interactive: true

  property string fontFamily: Style.font.menuFamily
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent

  readonly property int tileHeight: Math.max(Style.space(54), Style.font.body + Style.font.caption + Style.space(26))
  readonly property int headerHeight: Style.font.bodySmall + Style.spacing.sm * 2

  signal activated(int index)
  signal deleteRequested(int index)
  signal hovered(int index)

  implicitHeight: headerHeight + tileHeight * 3 + Style.spacing.md * 2

  function t(key) { return grid.strings ? grid.strings.t(key) : key }
  function isEnrolled(index) { return grid.enrolled.indexOf(Model.FINGERS[index].id) >= 0 }

  Row {
    anchors.fill: parent
    spacing: Style.spacing.panelGap

    Repeater {
      model: ["left", "right"]

      Column {
        id: hand
        required property string modelData
        required property int index
        readonly property int column: index

        width: (grid.width - Style.spacing.panelGap) / 2
        spacing: Style.spacing.md

        Text {
          width: parent.width
          height: grid.headerHeight - Style.spacing.md
          textFormat: Text.PlainText
          text: grid.t(hand.modelData === "left" ? "fingerprint.leftHand" : "fingerprint.rightHand")
          horizontalAlignment: Text.AlignLeft
          verticalAlignment: Text.AlignBottom
          color: grid.foreground
          opacity: 0.7
          font.family: grid.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Repeater {
          model: 3

          BorderSurface {
            id: tile
            required property int index
            readonly property int fingerIndex: hand.column * 3 + index
            readonly property var finger: Model.FINGERS[fingerIndex]
            readonly property bool enrolled: grid.isEnrolled(fingerIndex)
            readonly property bool hasCursor: grid.cursor === fingerIndex
            readonly property bool confirming: grid.pendingDelete === fingerIndex
            readonly property bool matched: grid.matchedFinger === finger.id
            readonly property color tint: confirming ? grid.urgent : grid.accent

            width: hand.width
            height: grid.tileHeight
            radius: Style.cornerRadius
            opacity: grid.interactive || hasCursor ? 1 : 0.6
            color: tileMouse.pressed ? Style.pressedFillFor(grid.foreground, tint)
              : (hasCursor || tileMouse.containsMouse) ? Style.hoverFillFor(grid.foreground, tint)
              : matched ? Style.selectedFillFor(grid.foreground, grid.accent)
              : "transparent"
            borderSpec: hasCursor ? Border.controlSpec("hover-cursor", grid.foreground, tint, grid.urgent)
              : Border.controlSpec("normal", grid.foreground, grid.accent)

            Behavior on color { ColorAnimation { duration: Style.duration(120) } }

            MouseArea {
              id: tileMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: grid.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
              onContainsMouseChanged: if (containsMouse) grid.hovered(tile.fingerIndex)
              onClicked: if (grid.interactive) grid.activated(tile.fingerIndex)
            }

            Row {
              anchors.fill: parent
              anchors.leftMargin: tile.contentLeftInset + Style.spacing.controlPaddingX
              anchors.rightMargin: tile.contentRightInset + Style.spacing.sm
              spacing: Style.spacing.controlGap

              Text {
                id: digit
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: Commons.I18n.formatNumber(tile.fingerIndex + 1)
                color: grid.foreground
                opacity: 0.45
                font.family: grid.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                id: glyph
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "󰈷"
                color: tile.confirming ? grid.urgent : tile.enrolled ? grid.accent : grid.foreground
                opacity: tile.enrolled || tile.confirming ? 1 : 0.35
                font.family: grid.fontFamily
                font.pixelSize: Style.font.display
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - digit.width - glyph.width - trailing.width - parent.spacing * 3
                spacing: Style.spacing.xxs

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: grid.t("fingerprint." + tile.finger.kind)
                  horizontalAlignment: Text.AlignLeft
                  color: grid.foreground
                  font.family: grid.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: tile.hasCursor
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: grid.t(tile.confirming ? "fingerprint.confirmDelete"
                    : tile.enrolled ? "fingerprint.enrolled" : "fingerprint.notEnrolled")
                  horizontalAlignment: Text.AlignLeft
                  color: tile.confirming ? grid.urgent : grid.foreground
                  opacity: tile.confirming ? 1 : 0.6
                  font.family: grid.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              Item {
                id: trailing
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(26)
                height: width

                // Recognized by the last test.
                Text {
                  anchors.centerIn: parent
                  visible: tile.matched && !tile.confirming
                  textFormat: Text.PlainText
                  text: "󰄬"
                  color: grid.accent
                  font.family: grid.fontFamily
                  font.pixelSize: Style.font.iconLarge
                }

                Button {
                  anchors.centerIn: parent
                  visible: tile.enrolled && !tile.matched && (tileMouse.containsMouse || hovered_ || tile.hasCursor || tile.confirming)
                  property bool hovered_: false
                  iconText: "󰆴"
                  iconSize: Style.font.icon
                  horizontalPadding: Style.spacing.xs
                  verticalPadding: Style.spacing.xs
                  foreground: tile.confirming ? grid.urgent : grid.foreground
                  accent: grid.urgent
                  tooltipText: grid.t("fingerprint.delete")
                  onHovered: function(isHovered) { hovered_ = isHovered }
                  onClicked: if (grid.interactive) grid.deleteRequested(tile.fingerIndex)
                }
              }
            }
          }
        }
      }
    }
  }
}
