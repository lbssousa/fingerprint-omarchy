import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "FingerprintModel.js" as Model

// Fingerprint enrollment overlay, after GNOME Settings' fingerprint dialog
// and the Security page of lbssousa/noctalia: six finger tiles (thumb, index
// and middle finger of each hand), a test area, and an enrollment card
// whose square frame fills as the scans pass. Summoned with
// `omarchy-shell shell summon lbssousa.fingerprint '{}'` (omarchy-fingerprint).
//
// Everything works from the keyboard: arrows or 1-6 pick a finger, Enter
// enrolls it, Delete removes it (Enter confirms), V or Enter on the test area
// tests, Tab walks the tiles, Escape cancels or closes.
//
// fprintd is reached through fprint-helper (FingerprintClient.qml), which
// runs only while the overlay is open.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  Commons.Translations { id: tr; directory: Qt.resolvedUrl("i18n") }

  // The reader, as the helper last reported it.
  property bool loaded: false
  property bool available: false
  property string unavailableReason: ""
  property var device: ({})
  property var enrolled: []
  // The operation running in the helper: "", "enroll", "verify" or "delete".
  property string op: ""
  readonly property bool busy: op !== ""

  // Keyboard cursor: 0-5 the finger tiles (Model.FINGERS), 6 the test area.
  property int cursor: 4
  property int lastColumn: 1
  property int pendingDelete: -1

  property bool enrollOpen: false
  property string enrollFinger: ""
  property int enrollStage: 0
  property int enrollTotal: -1
  property string enrollResult: ""
  property string enrollError: ""
  property bool enrollDone: false

  property string verifyResult: ""
  property string verifyFinger: ""
  property string verifyError: ""

  property string statusText: ""
  property string statusTone: "info"
  property bool pamConfigured: true

  property string fontFamily: Style.font.menuFamily
  property color accent: Commons.Color.polkit.accent
  property color background: Commons.Color.polkit.background
  property color foreground: Commons.Color.polkit.text
  property color urgent: Commons.Color.polkit.textError
  property var borderSpec: Border.surfaceSpec("polkit", "border", Commons.Color.polkit.border, Math.max(1, Style.space(2)), "border-alpha")
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int cardWidth: Math.min(Style.space(560), Math.max(Style.space(320), panel.width - Style.gapsOut * 2))

  function open(payloadJson) {
    resetOperation()
    root.statusText = ""
    root.pendingDelete = -1
    root.opened = true
    pamCheck.running = true
    Qt.callLater(refocus)
  }

  function close() {
    root.opened = false
    root.enrollOpen = false
    resetOperation()
  }

  function dismiss() {
    close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "lbssousa.fingerprint")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function refocus() {
    if (root.opened) keyCatcher.forceActiveFocus()
  }

  function resetOperation() {
    root.op = ""
    root.verifyResult = ""
    root.verifyFinger = ""
    root.verifyError = ""
  }

  function fingerName(id) {
    return tr.t("fingerprint.finger." + id)
  }

  function isEnrolled(index) {
    return index >= 0 && index < Model.FINGERS.length && root.enrolled.indexOf(Model.FINGERS[index].id) >= 0
  }

  function setStatus(text, tone) {
    root.statusText = text
    root.statusTone = tone
  }

  function moveCursor(index) {
    root.pendingDelete = -1
    root.cursor = index
    if (index !== Model.VERIFY_INDEX) root.lastColumn = Model.column(index)
  }

  // -- actions ------------------------------------------------------------

  function refresh() {
    if (root.busy) return
    root.loaded = false
    if (client.running) client.send({ cmd: "refresh" })
    else client.restart()
  }

  function startEnroll(index) {
    if (root.busy || !root.available || index < 0 || index >= Model.FINGERS.length) return
    root.pendingDelete = -1
    root.verifyResult = ""
    root.verifyFinger = ""
    root.verifyError = ""
    root.statusText = ""
    root.enrollFinger = Model.FINGERS[index].id
    root.enrollStage = 0
    root.enrollTotal = root.device.stages > 0 ? root.device.stages : -1
    root.enrollResult = ""
    root.enrollError = ""
    root.enrollDone = false
    root.enrollOpen = true
    root.op = "enroll"
    client.send({ cmd: "enroll", finger: root.enrollFinger })
  }

  function retryEnroll() {
    startEnroll(Model.fingerIndex(root.enrollFinger))
  }

  function cancelEnroll() {
    if (root.op === "enroll") client.send({ cmd: "cancel" })
    root.op = ""
    root.enrollOpen = false
  }

  function closeEnroll() {
    root.enrollOpen = false
    if (root.enrollDone && root.enrollResult === "enroll-completed")
      setStatus(tr.t("fingerprint.enroll.completed") + " — " + fingerName(root.enrollFinger), "success")
  }

  function startVerify() {
    if (root.busy || !root.available || root.enrolled.length === 0) return
    moveCursor(Model.VERIFY_INDEX)
    root.statusText = ""
    root.verifyResult = "verify-started"
    root.verifyFinger = ""
    root.verifyError = ""
    root.op = "verify"
    client.send({ cmd: "verify" })
  }

  function cancelVerify() {
    if (root.op !== "verify") return
    client.send({ cmd: "cancel" })
    root.op = ""
    root.verifyResult = ""
  }

  function requestDelete(index) {
    if (root.busy || !isEnrolled(index)) return
    moveCursor(index)
    root.pendingDelete = index
  }

  function confirmDelete() {
    var index = root.pendingDelete
    root.pendingDelete = -1
    if (root.busy || !isEnrolled(index)) return
    root.verifyResult = ""
    root.verifyFinger = ""
    root.statusText = ""
    root.op = "delete"
    client.send({ cmd: "delete", finger: Model.FINGERS[index].id })
  }

  function activate(index) {
    if (index === Model.VERIFY_INDEX) {
      if (root.op === "verify") cancelVerify()
      else startVerify()
    } else if (root.pendingDelete === index) {
      confirmDelete()
    } else {
      moveCursor(index)
      startEnroll(index)
    }
  }

  // -- helper events --------------------------------------------------------

  function onHelperEvent(m) {
    if (m.type === "state") {
      root.loaded = true
      root.available = m.available === true
      root.unavailableReason = String(m.reason || "")
      root.device = m.device || ({})
      // Through the signal the list arrives as a QVariantList, not a JS array.
      var fingers = []
      var list = m.enrolled || []
      for (var i = 0; i < list.length; i++) fingers.push(String(list[i]))
      root.enrolled = fingers
    } else if (m.type === "enroll") {
      if (root.op !== "enroll" || m.finger !== root.enrollFinger) return
      root.enrollStage = m.stage
      if (m.total > 0) root.enrollTotal = m.total
      root.enrollResult = m.result
      if (m.done) {
        root.enrollDone = true
        root.op = ""
      }
    } else if (m.type === "verify") {
      if (root.op !== "verify") return
      root.verifyResult = m.result
      root.verifyFinger = String(m.finger || "")
      if (m.done) root.op = ""
    } else if (m.type === "deleted") {
      root.op = ""
      setStatus(tr.t("fingerprint.deleted", "%1 deleted").arg(fingerName(m.finger)), "info")
    } else if (m.type === "cancelled") {
      if (root.op === m.op) root.op = ""
    } else if (m.type === "error") {
      var text = tr.t(Model.errorKey(m.code))
      if (m.op === "enroll" && root.enrollOpen) {
        root.enrollError = m.code
        root.enrollDone = true
      } else if (m.op === "verify") {
        root.verifyError = m.code
      } else {
        setStatus(text, "error")
      }
      if (root.op === m.op) root.op = ""
    }
  }

  // -- what the views show ----------------------------------------------------

  readonly property var enrollState: {
    if (root.enrollError !== "") return { text: tr.t(Model.errorKey(root.enrollError)), tone: "error" }
    if (root.enrollResult === "") return { text: tr.t("fingerprint.preparing"), tone: "info" }
    var s = Model.enrollStatus(root.enrollResult, root.device.scanType)
    // A scan error that still ended the enrollment reads as a failure.
    return { text: tr.t(s.key), tone: root.enrollDone && s.tone === "info" ? "error" : s.tone }
  }

  readonly property var verifyState: {
    if (root.enrolled.length === 0) return { text: tr.t("fingerprint.verify.none"), tone: "idle" }
    if (root.verifyError !== "") return { text: tr.t(Model.errorKey(root.verifyError)), tone: "error" }
    if (root.verifyResult === "") return { text: tr.t("fingerprint.verify.start"), tone: "idle" }
    if (root.verifyResult === "verify-timeout") return { text: tr.t("fingerprint.verify.failed"), tone: "error" }
    var s = Model.verifyStatus(root.verifyResult, root.device.scanType)
    if (root.verifyResult === "verify-match" && Model.fingerIndex(root.verifyFinger) >= 0)
      return { text: tr.t("fingerprint.verify.matchFinger", "Recognized: %1").arg(fingerName(root.verifyFinger)), tone: "success" }
    return { text: tr.t(s.key), tone: root.op !== "verify" && s.tone === "info" ? "error" : s.tone }
  }

  readonly property string unavailableText: {
    if (!root.loaded) return tr.t("fingerprint.preparing")
    if (root.unavailableReason === "no-service") return tr.t("fingerprint.noService")
    if (root.unavailableReason === "no-device") return tr.t("fingerprint.noReader")
    return tr.t("fingerprint.error.generic")
  }

  FingerprintClient {
    id: client
    active: root.opened
    onEvent: function(message) { root.onHelperEvent(message) }
    onLost: {
      root.loaded = true
      root.available = false
      root.unavailableReason = "helper"
      root.op = ""
      if (root.enrollOpen) {
        root.enrollError = "generic"
        root.enrollDone = true
      }
    }
  }

  // sudo and polkit only ask for fingerprints once an administrator set that up.
  Process {
    id: pamCheck
    command: ["grep", "-qs", "pam_fprintd.so", "/etc/pam.d/sudo"]
    onExited: function(exitCode) { root.pamConfigured = exitCode === 0 }
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "omarchy-fingerprint"

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.polkit.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.enrollOpen ? root.refocus() : root.dismiss()
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        event.accepted = true
        var key = Util.readingKey(event)
        var enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space

        if (root.enrollOpen) {
          if (event.key === Qt.Key_Escape) {
            if (root.enrollDone) root.closeEnroll()
            else root.cancelEnroll()
          } else if (enter && !event.isAutoRepeat && root.enrollDone) {
            if (root.enrollState.tone === "success") root.closeEnroll()
            else root.retryEnroll()
          }
          return
        }

        if (root.pendingDelete >= 0) {
          if (enter && !event.isAutoRepeat) {
            root.confirmDelete()
            return
          }
          root.pendingDelete = -1
          if (event.key === Qt.Key_Escape) return
        }

        if (event.key === Qt.Key_Escape) {
          if (root.op === "verify") root.cancelVerify()
          else root.dismiss()
        } else if (!root.available) {
          if (enter || event.key === Qt.Key_R || event.key === Qt.Key_F5) root.refresh()
        } else if (key === Qt.Key_Left) {
          root.moveCursor(Model.move(root.cursor, "left", root.lastColumn))
        } else if (key === Qt.Key_Right) {
          root.moveCursor(Model.move(root.cursor, "right", root.lastColumn))
        } else if (event.key === Qt.Key_Up) {
          root.moveCursor(Model.move(root.cursor, "up", root.lastColumn))
        } else if (event.key === Qt.Key_Down) {
          root.moveCursor(Model.move(root.cursor, "down", root.lastColumn))
        } else if (event.key === Qt.Key_Tab) {
          root.moveCursor(Model.step(root.cursor, 1))
        } else if (event.key === Qt.Key_Backtab) {
          root.moveCursor(Model.step(root.cursor, -1))
        } else if (enter) {
          if (!event.isAutoRepeat) root.activate(root.cursor)
        } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
          root.requestDelete(root.cursor)
        } else if (event.key === Qt.Key_V) {
          root.startVerify()
        } else if (event.key === Qt.Key_R || event.key === Qt.Key_F5) {
          root.refresh()
        } else if (Model.shortcutIndex(event.text) >= 0) {
          root.moveCursor(Model.shortcutIndex(event.text))
        } else {
          event.accepted = false
        }
      }
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: content.implicitHeight + card.contentTopInset + card.contentBottomInset
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: root.refocus() }

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.spacing.panelGap

        // The reader.
        Row {
          width: parent.width
          spacing: Style.spacing.xxl

          Text {
            id: readerGlyph
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "󰈷"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - readerGlyph.width - parent.spacing
            spacing: Style.spacing.xxs

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.available ? (root.device.name || tr.t("fingerprint.title")) : tr.t("fingerprint.title")
              horizontalAlignment: Text.AlignLeft
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.available
                ? tr.t(root.device.scanType === "swipe" ? "fingerprint.scanType.swipe" : "fingerprint.scanType.press")
                : root.unavailableText
              horizontalAlignment: Text.AlignLeft
              wrapMode: Text.Wrap
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        Button {
          visible: root.loaded && !root.available
          anchors.right: parent.right
          text: tr.t("fingerprint.refresh")
          iconText: "󰑐"
          bordered: true
          onClicked: root.refresh()
        }

        FingerGrid {
          visible: root.available
          width: parent.width
          strings: tr
          enrolled: root.enrolled
          cursor: root.cursor
          pendingDelete: root.pendingDelete
          matchedFinger: root.verifyResult === "verify-match" ? root.verifyFinger : ""
          interactive: !root.busy
          fontFamily: root.fontFamily
          foreground: root.foreground
          accent: root.accent
          urgent: root.urgent
          onHovered: function(index) { if (!root.enrollOpen) root.moveCursor(index) }
          onActivated: function(index) { root.activate(index); root.refocus() }
          onDeleteRequested: function(index) {
            if (root.pendingDelete === index) root.confirmDelete()
            else root.requestDelete(index)
            root.refocus()
          }
        }

        VerifyArea {
          visible: root.available
          width: parent.width
          title: tr.t("fingerprint.verify.title")
          message: root.verifyState.text
          tone: root.op === "verify" ? "info" : root.verifyState.tone
          running: root.op === "verify"
          hasCursor: root.cursor === Model.VERIFY_INDEX
          interactive: root.enrolled.length > 0 && (!root.busy || root.op === "verify")
          fontFamily: root.fontFamily
          foreground: root.foreground
          accent: root.accent
          urgent: root.urgent
          onHovered: if (!root.enrollOpen) root.moveCursor(Model.VERIFY_INDEX)
          onActivated: { root.activate(Model.VERIFY_INDEX); root.refocus() }
        }

        Text {
          width: parent.width
          visible: root.statusText !== ""
          textFormat: Text.PlainText
          text: root.statusText
          wrapMode: Text.Wrap
          horizontalAlignment: Text.AlignLeft
          color: root.statusTone === "error" ? root.urgent : root.statusTone === "success" ? root.accent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          width: parent.width
          visible: root.available && !root.pamConfigured && root.enrolled.length > 0
          textFormat: Text.PlainText
          text: tr.t("fingerprint.pamHint")
          wrapMode: Text.Wrap
          horizontalAlignment: Text.AlignLeft
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          visible: root.available
          textFormat: Text.PlainText
          text: tr.t("fingerprint.keys")
          wrapMode: Text.Wrap
          horizontalAlignment: Text.AlignHCenter
          color: root.foreground
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    Rectangle {
      width: Math.min(titleText.implicitWidth + Style.space(24), panel.width - Style.gapsOut * 2)
      height: Style.space(28)
      anchors.horizontalCenter: card.horizontalCenter
      anchors.bottom: card.top
      anchors.bottomMargin: Style.space(10)
      radius: Style.cornerRadius
      color: root.background

      Text {
        id: titleText
        textFormat: Text.PlainText
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        text: tr.t("fingerprint.title")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideMiddle
      }
    }

    // The enrollment card, over the main one.
    Rectangle {
      anchors.fill: parent
      visible: root.enrollOpen
      color: Commons.Color.polkit.scrim

      MouseArea { anchors.fill: parent; onClicked: root.refocus() }

      EnrollDialog {
        width: Math.min(Style.space(380), parent.width - Style.gapsOut * 2)
        anchors.centerIn: parent
        color: root.background
        borderSpec: root.borderSpec
        strings: tr
        title: tr.t("fingerprint.enroll.title", "Enroll %1").arg(root.fingerName(root.enrollFinger))
        message: root.enrollState.text
        tone: root.enrollState.tone
        progress: root.enrollState.tone === "success" ? 1 : Model.progress(root.enrollStage, root.enrollTotal, false)
        stagesText: root.enrollTotal > 0 && root.enrollState.tone === "info"
          ? tr.t("fingerprint.enroll.stages", "Scan %1 of %2")
              .arg(Commons.I18n.formatNumber(Math.min(root.enrollStage + 1, root.enrollTotal)))
              .arg(Commons.I18n.formatNumber(root.enrollTotal))
          : ""
        fontFamily: root.fontFamily
        foreground: root.foreground
        accent: root.accent
        urgent: root.urgent
        onCancelRequested: { root.cancelEnroll(); root.refocus() }
        onRetryRequested: { root.retryEnroll(); root.refocus() }
        onDoneRequested: { root.closeEnroll(); root.refocus() }
      }
    }
  }
}
