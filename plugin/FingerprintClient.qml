import QtQuick
import Quickshell.Io

// Runs fprint-helper while `active` and relays its NDJSON events. Turning
// `active` off stops the helper (SIGTERM), which stops a running scan and
// releases the reader on its way out.
Item {
  id: client

  property bool active: false
  readonly property bool running: proc.running

  signal event(var message)
  // The helper ended while still wanted (python or python-gobject missing, a crash).
  signal lost()

  onActiveChanged: proc.running = active

  // Starts the helper again after it was lost; it reports the reader on start.
  function restart() {
    if (active && !proc.running) proc.running = true
  }

  function send(command) {
    if (proc.running) proc.write(JSON.stringify(command) + "\n")
  }

  Process {
    id: proc
    command: ["python3", "-I", String(Qt.resolvedUrl("fprint-helper")).replace(/^file:\/\//, "")]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        var message
        try {
          message = JSON.parse(line)
        } catch (e) {
          return
        }
        if (message && typeof message.type === "string") client.event(message)
      }
    }
    onExited: function(exitCode) {
      if (client.active) client.lost()
    }
  }
}
