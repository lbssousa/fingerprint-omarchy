import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "FingerprintModel.js" as Model

// Your fingerprints, full screen, as Omarchy's own fingerprint panel
// (omarchy.fingerprint, Omarchy 4.6) shows a registration: the big print on a
// dark scrim with one status line under it, arriving as a scratchy
// transmission and lighting up along its ridges with every touch the reader
// accepts. What this adds is what that panel doesn't do: choosing which of
// six fingers to enroll, testing the prints (the print lights up and the
// finger it recognized is named), and deleting them. Summoned with
// `omarchy-shell shell summon lbssousa.fingerprint '{}'` (omarchy-fingerprint).
//
// Everything works from the keyboard: arrows or 1-6 pick a finger, Enter
// enrolls it, Delete removes it (Enter confirms), V or Enter on the print
// tests, Tab walks the print and the fingers, Escape cancels or closes.
//
// fprintd is reached through fprint-helper (FingerprintClient.qml), which
// runs only while the panel is open. Nothing here needs root, so it sets no
// PAM up: Omarchy's setup does (omarchy-setup-security-fingerprint).
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

  // Keyboard cursor: 0-5 the fingers (Model.FINGERS), 6 the print (testing).
  property int cursor: Model.VERIFY_INDEX
  property int lastColumn: 1
  property int pendingDelete: -1

  // An enrollment: "" (none), "scanning", "done" or "failed".
  property string enrollPhase: ""
  property string enrollFinger: ""
  property int enrollStage: 0
  property int enrollTotal: -1
  property string enrollHint: ""
  property string enrollFailure: ""

  // A test: the reader's last complaint while it runs, then how it ended
  // ("match", "no-match" or "failed") and the finger it named.
  property string verifyHint: ""
  property string verifyOutcome: ""
  property string verifyFinger: ""
  property string verifyError: ""

  // A one-off message (a deleted print, an error), until the next move.
  property string statusText: ""
  property string statusTone: "info"
  property bool pamConfigured: true

  // The scrim is near-black whatever the theme, so this palette is fixed, as
  // on Omarchy's own fingerprint panel.
  readonly property color onScrimDim: Qt.rgba(1, 1, 1, 0.6)
  readonly property color onScrimUrgent: "#ff6b6b"

  function open(payloadJson) {
    resetOperation()
    root.enrollPhase = ""
    root.statusText = ""
    root.pendingDelete = -1
    root.verifyFinger = ""
    root.cursor = Model.VERIFY_INDEX
    view.settle()
    root.opened = true
    pamCheck.running = true
    Qt.callLater(function() { if (root.opened) view.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.enrollPhase = ""
    view.settle()
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

  function resetOperation() {
    root.op = ""
    root.verifyHint = ""
    root.verifyOutcome = ""
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
    root.statusText = ""
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
    view.settle()
    root.pendingDelete = -1
    root.statusText = ""
    resetOperation()
    root.verifyFinger = ""
    root.enrollFinger = Model.FINGERS[index].id
    root.enrollStage = 0
    root.enrollTotal = root.device.stages > 0 ? root.device.stages : -1
    root.enrollHint = ""
    root.enrollFailure = ""
    root.enrollPhase = "scanning"
    root.op = "enroll"
    client.send({ cmd: "enroll", finger: root.enrollFinger })
  }

  function retryEnroll() {
    startEnroll(Model.fingerIndex(root.enrollFinger))
  }

  // Back to the fingers, from an enrollment running or ended.
  function leaveEnroll() {
    if (root.op === "enroll") client.send({ cmd: "cancel" })
    if (root.op === "enroll") root.op = ""
    root.enrollPhase = ""
    view.settle()
  }

  function startVerify() {
    if (root.busy || !root.available || root.enrolled.length === 0) return
    moveCursor(Model.VERIFY_INDEX)
    resetOperation()
    root.verifyFinger = ""
    root.op = "verify"
    client.send({ cmd: "verify" })
  }

  function cancelVerify() {
    if (root.op !== "verify") return
    client.send({ cmd: "cancel" })
    root.op = ""
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
    resetOperation()
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
      if (m.total > 0) root.enrollTotal = m.total
      if (m.result === "enroll-stage-passed") {
        root.enrollStage = m.stage
        root.enrollHint = ""
      } else if (Model.scanHint(m.result) !== "") {
        root.enrollHint = Model.scanHint(m.result)
      }
      if (m.done) {
        root.op = ""
        if (m.result === "enroll-completed") {
          root.enrollPhase = "done"
        } else {
          root.enrollFailure = Model.enrollFailure(m.result)
          root.enrollPhase = "failed"
        }
      }
    } else if (m.type === "verify") {
      if (root.op !== "verify") return
      root.verifyHint = Model.scanHint(m.result)
      if (m.done) {
        root.op = ""
        root.verifyHint = ""
        root.verifyOutcome = Model.verifyOutcome(m.result)
        root.verifyFinger = root.verifyOutcome === "match" ? String(m.finger || "") : ""
      }
    } else if (m.type === "deleted") {
      root.op = ""
      setStatus(tr.t("fingerprint.deleted").arg(fingerName(m.finger)), "info")
    } else if (m.type === "cancelled") {
      if (root.op === m.op) root.op = ""
    } else if (m.type === "error") {
      if (m.op === "enroll" && root.enrollPhase === "scanning") {
        root.enrollFailure = m.code
        root.enrollPhase = "failed"
      } else if (m.op === "verify") {
        root.verifyError = m.code
        root.verifyOutcome = "failed"
      } else {
        setStatus(tr.t(Model.errorKey(m.code)), "error")
      }
      if (root.op === m.op) root.op = ""
    }
  }

  // -- what the panel shows ---------------------------------------------------

  readonly property bool matchedNamed: root.verifyOutcome === "match" && Model.fingerIndex(root.verifyFinger) >= 0

  // The print: how much of it is lit, and in what colour.
  readonly property var art: {
    if (root.enrollPhase === "scanning")
      return { progress: Model.progress(root.enrollStage, root.enrollTotal, false), urgent: false }
    if (root.enrollPhase === "done") return { progress: 1, urgent: false }
    if (root.enrollPhase === "failed") return { progress: 1, urgent: true }
    if (root.cursor === Model.VERIFY_INDEX && root.verifyOutcome !== "")
      return { progress: 1, urgent: root.verifyOutcome !== "match" }
    return { progress: 0, urgent: false }
  }

  // The one status line.
  readonly property var status: {
    if (!root.loaded) return { text: tr.t("fingerprint.preparing"), urgent: false }
    if (!root.available) return { text: root.unavailableText, urgent: false }
    var scanType = root.device.scanType
    switch (root.enrollPhase) {
    case "scanning": return { text: tr.t(Model.scanKey(scanType, root.enrollStage, root.enrollHint)), urgent: false }
    case "done": return { text: tr.t("fingerprint.done"), urgent: false }
    case "failed": return { text: tr.t(Model.failureKey(root.enrollFailure)), urgent: true }
    }
    if (root.op === "verify") return { text: tr.t(Model.scanKey(scanType, 0, root.verifyHint)), urgent: false }
    if (root.pendingDelete >= 0)
      return { text: fingerName(Model.FINGERS[root.pendingDelete].id) + " · " + tr.t("fingerprint.confirmDelete"), urgent: true }
    if (root.statusText !== "") return { text: root.statusText, urgent: root.statusTone === "error" }
    if (root.cursor === Model.VERIFY_INDEX) {
      if (root.enrolled.length === 0) return { text: tr.t("fingerprint.verify.none"), urgent: false }
      switch (root.verifyOutcome) {
      case "match":
        return { text: root.matchedNamed ? tr.t("fingerprint.verify.matchFinger").arg(fingerName(root.verifyFinger))
                                         : tr.t("fingerprint.verify.match"), urgent: false }
      case "no-match": return { text: tr.t("fingerprint.verify.noMatch"), urgent: true }
      case "failed":
        return { text: tr.t(root.verifyError !== "" ? Model.errorKey(root.verifyError) : "fingerprint.verify.failed"), urgent: true }
      }
      return { text: tr.t("fingerprint.verify.start"), urgent: false }
    }
    var finger = Model.FINGERS[root.cursor]
    return { text: fingerName(finger.id) + " · " + tr.t(isEnrolled(root.cursor) ? "fingerprint.enrolled" : "fingerprint.notEnrolled"), urgent: false }
  }

  readonly property string unavailableText: {
    if (root.unavailableReason === "no-service") return tr.t("fingerprint.noService")
    if (root.unavailableReason === "no-device") return tr.t("fingerprint.failNoReader")
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
      if (root.enrollPhase === "scanning") {
        root.enrollFailure = "generic"
        root.enrollPhase = "failed"
      }
    }
  }

  // sudo and polkit only ask for fingerprints once Omarchy's setup has run.
  Process {
    id: pamCheck
    command: ["grep", "-qs", "pam_fprintd.so", "/etc/pam.d/sudo"]
    onExited: function(exitCode) { root.pamConfigured = exitCode === 0 }
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "omarchy-fingerprint"

    // Open on the transmission settling, once the surface is on screen.
    onContentRevealedChanged: if (contentRevealed && root.opened) view.transmit()

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.82)

      // A stray click must not throw away a scan in flight.
      MouseArea {
        anchors.fill: parent
        onClicked: if (!root.busy) root.dismiss()
      }
    }

    Item {
      id: view
      anchors.fill: parent

      // The scratchy transmission, as on Omarchy's panel: noise is 1 at its
      // worst and 0 when the picture holds, redrawn on every frame of the
      // timer. The panel opens on it settling; once a finger is enrolled the
      // picture breaks up and comes back on the fingers. Skipped with
      // animations off.
      property real noise: 0
      property int frame: 0
      property bool signingOff: false

      function transmit() {
        forceActiveFocus()
        settle()
        if (Style.duration(1) > 0) noise = 1
      }

      function settle() {
        farewell.stop()
        signingOff = false
        noise = 0
      }

      // The print broke up after an enrollment: back to the fingers.
      function signedOff() {
        root.enrollPhase = ""
        transmit()
      }

      Timer {
        interval: 45
        repeat: true
        running: view.noise > 0 || view.signingOff
        onTriggered: {
          view.frame++
          if (view.signingOff) {
            view.noise = Math.min(1, view.noise + 0.06)
            if (view.noise === 1) {
              view.signingOff = false
              view.signedOff()
            }
          } else {
            view.noise = Math.max(0, view.noise - 0.045)
          }
        }
      }

      // Leaves the result up long enough to read before signing off.
      Timer {
        id: farewell
        interval: 1400
        onTriggered: {
          if (Style.duration(1) <= 0) view.signedOff()
          else view.signingOff = true
        }
      }

      Connections {
        target: root
        function onEnrollPhaseChanged() {
          if (root.enrollPhase === "done") farewell.restart()
          else farewell.stop()
        }
      }

      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        event.accepted = true
        var key = Util.readingKey(event)
        var enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space

        if (root.enrollPhase !== "") {
          if (event.key === Qt.Key_Escape) root.leaveEnroll()
          else if (enter && !event.isAutoRepeat && root.enrollPhase === "failed") root.retryEnroll()
          else if (enter && !event.isAutoRepeat && root.enrollPhase === "done") farewell.triggered()
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
        } else if (root.busy) {
          // A test or a deletion runs: only Escape (above) stops it.
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

      Column {
        anchors.centerIn: parent
        spacing: Style.space(28)

        // The print. Under the cursor it is the test: Enter, V or a click.
        Item {
          anchors.horizontalCenter: parent.horizontalCenter
          width: Style.space(264) + Style.space(40)
          height: width

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: printMouse.containsMouse && root.enrollPhase === "" ? Qt.rgba(1, 1, 1, 0.04) : "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.5)
            visible: root.available && root.enrollPhase === "" && root.cursor === Model.VERIFY_INDEX && view.noise === 0
          }

          FingerprintArt {
            anchors.centerIn: parent
            width: Style.space(264)
            height: width
            progress: root.art.progress
            tone: root.art.urgent ? root.onScrimUrgent : Commons.Color.accent
            noise: view.noise
            frame: view.frame
          }

          MouseArea {
            id: printMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.available && root.enrollPhase === ""
            cursorShape: root.enrolled.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
            onContainsMouseChanged: if (containsMouse && !root.busy) root.moveCursor(Model.VERIFY_INDEX)
            onClicked: root.activate(Model.VERIFY_INDEX)
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.horizontalCenter: parent.horizontalCenter
          width: Math.min(view.width - Style.space(48), Style.space(520))
          // Hold the line's height while it is empty, so the print never shifts.
          text: root.status.text !== "" ? root.status.text : " "
          opacity: { view.frame; return view.noise > 0 && Math.random() < 0.5 ? 0.3 : 1 }
          color: root.status.urgent ? root.onScrimUrgent : root.onScrimDim
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
        }

        // While the reader can't be reached: look for it again.
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: root.loaded && !root.available
          textFormat: Text.PlainText
          text: tr.t("fingerprint.refresh")
          color: refreshMouse.containsMouse ? "white" : root.onScrimDim
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.underline: true

          MouseArea {
            id: refreshMouse
            anchors.fill: parent
            anchors.margins: -Style.space(6)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.refresh()
          }
        }

        FingerGrid {
          anchors.horizontalCenter: parent.horizontalCenter
          width: implicitWidth
          visible: root.available
          opacity: root.enrollPhase !== "" ? 0.35 : 1
          strings: tr
          enrolled: root.enrolled
          cursor: root.enrollPhase !== "" ? Model.fingerIndex(root.enrollFinger) : root.cursor
          pendingDelete: root.pendingDelete
          matchedFinger: root.matchedNamed ? root.verifyFinger : ""
          interactive: !root.busy && root.enrollPhase === ""
          onHovered: function(index) { if (!root.busy && root.enrollPhase === "") root.moveCursor(index) }
          onActivated: function(index) { root.activate(index); view.forceActiveFocus() }
          onDeleteRequested: function(index) {
            if (root.pendingDelete === index) root.confirmDelete()
            else root.requestDelete(index)
            view.forceActiveFocus()
          }
        }
      }

      Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(40)
        width: Math.min(view.width - Style.space(48), Style.space(640))
        spacing: Style.space(10)

        Text {
          width: parent.width
          visible: root.available && !root.pamConfigured && root.enrolled.length > 0
          textFormat: Text.PlainText
          text: tr.t("fingerprint.pamHint")
          wrapMode: Text.Wrap
          horizontalAlignment: Text.AlignHCenter
          color: root.onScrimDim
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width
          visible: root.available
          textFormat: Text.PlainText
          text: tr.t("fingerprint.keys")
          wrapMode: Text.Wrap
          horizontalAlignment: Text.AlignHCenter
          color: root.onScrimDim
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
