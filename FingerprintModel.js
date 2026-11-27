// Pure helpers for the fingerprint panel, kept out of QML so node can test
// them (tests/js/).

// The six fingers offered, as fprintd names them. The chooser shows the left
// hand in the first column and the right hand in the second, thumb to middle
// finger from the top; digits 1-6 pick them in this order.
var FINGERS = [
  { id: "left-thumb", hand: "left", kind: "thumb" },
  { id: "left-index-finger", hand: "left", kind: "index" },
  { id: "left-middle-finger", hand: "left", kind: "middle" },
  { id: "right-thumb", hand: "right", kind: "thumb" },
  { id: "right-index-finger", hand: "right", kind: "index" },
  { id: "right-middle-finger", hand: "right", kind: "middle" }
]
var ROWS = 3
// The cursor's stop for the print itself, above the chooser: testing.
var VERIFY_INDEX = FINGERS.length

function column(index) {
  return Math.floor(index / ROWS)
}

function row(index) {
  return index % ROWS
}

function fingerIndex(id) {
  for (var i = 0; i < FINGERS.length; i++) if (FINGERS[i].id === id) return i
  return -1
}

// Where an arrow key takes the cursor. direction is "left", "right", "up" or
// "down" (already mirrored for right-to-left reading); lastColumn is the
// chooser column to come back to from the print.
function move(index, direction, lastColumn) {
  if (index === VERIFY_INDEX) {
    if (direction === "down") return (lastColumn === 1 ? ROWS : 0)
    return index
  }
  var c = column(index)
  var r = row(index)
  if (direction === "left") c = 0
  else if (direction === "right") c = 1
  else if (direction === "up") {
    if (r === 0) return VERIFY_INDEX
    r -= 1
  } else if (direction === "down") r = Math.min(ROWS - 1, r + 1)
  return c * ROWS + r
}

// Tab order: the print, then the six fingers, then around.
function step(index, delta) {
  var order = [VERIFY_INDEX, 0, 1, 2, 3, 4, 5]
  var at = order.indexOf(index)
  if (at < 0) at = 0
  return order[((at + delta) % order.length + order.length) % order.length]
}

// Digits 1-6 jump straight to a finger.
function shortcutIndex(text) {
  var digit = String(text || "")
  if (digit.length !== 1 || digit < "1" || digit > "6") return -1
  return digit.charCodeAt(0) - "1".charCodeAt(0)
}

// fprintd's scan feedback, shared by enroll and verify ("enroll-retry-scan",
// "verify-swipe-too-short"), as the hint Omarchy's fingerprint panel names it,
// or "" for a result that isn't a retry.
var HINTS = {
  "retry-scan": "again",
  "swipe-too-short": "short",
  "finger-not-centered": "center",
  "remove-and-retry": "lift",
  "too-fast": "fast"
}

function scanHint(result) {
  var text = String(result || "")
  var dash = text.indexOf("-")
  return dash > 0 ? HINTS[text.slice(dash + 1)] || "" : ""
}

var HINT_KEYS = {
  again: "fingerprint.retryAgain",
  short: "fingerprint.retryShort",
  center: "fingerprint.retryCenter",
  lift: "fingerprint.retryLift",
  fast: "fingerprint.retryFast"
}

function hintKey(hint) {
  return HINT_KEYS[hint] || ""
}

// How an enrollment that ended without a print failed, as Omarchy's panel
// names it: "duplicate", "full", "disconnected" or "enroll".
function enrollFailure(result) {
  switch (result) {
  case "enroll-duplicate": return "duplicate"
  case "enroll-data-full": return "full"
  case "enroll-disconnected": return "disconnected"
  }
  return "enroll"
}

var FAILURE_KEYS = {
  duplicate: "fingerprint.failDuplicate",
  full: "fingerprint.failFull",
  disconnected: "fingerprint.failDisconnected",
  enroll: "fingerprint.failEnroll"
}

// A helper error code (see fprint-helper) reads as itself; an enrollment
// failure as Omarchy's panel words it.
function failureKey(code) {
  return FAILURE_KEYS[code] || errorKey(code)
}

// The status line while scanning: the reader's last complaint, or what to do
// next ("Touch the sensor", then "Lift and touch again").
function scanKey(scanType, stage, hint) {
  if (hintKey(hint) !== "") return hintKey(hint)
  var swipe = scanType === "swipe"
  if (stage > 0) return swipe ? "fingerprint.swipeAgain" : "fingerprint.touchAgain"
  return swipe ? "fingerprint.swipe" : "fingerprint.touch"
}

// A finished test: "match", "no-match" or "failed" (timed out, disconnected,
// or a result fprintd ended it on that isn't a verdict).
function verifyOutcome(result) {
  if (result === "verify-match") return "match"
  if (result === "verify-no-match") return "no-match"
  return "failed"
}

var ERROR_KEYS = {
  "permission-denied": "fingerprint.error.permissionDenied",
  "in-use": "fingerprint.error.inUse",
  "no-prints": "fingerprint.error.noPrints",
  "not-deleted": "fingerprint.error.notDeleted",
  "no-device": "fingerprint.error.noDevice",
  "no-service": "fingerprint.noService"
}

function errorKey(code) {
  return ERROR_KEYS[code] || "fingerprint.error.generic"
}

// The share of the print to light, 0 to 1, as Omarchy's panel lights it:
// every accepted touch lights the same length of ridge, short of full until
// the reader says the print is in; with no stage count, it closes in on full.
function progress(stage, total, completed) {
  if (completed) return 1
  if (!(total > 0)) return 1 - Math.pow(0.85, Math.max(0, stage))
  return Math.max(0, Math.min(0.96, stage / total))
}

if (typeof module !== "undefined") {
  module.exports = {
    FINGERS: FINGERS,
    VERIFY_INDEX: VERIFY_INDEX,
    column: column,
    row: row,
    fingerIndex: fingerIndex,
    move: move,
    step: step,
    shortcutIndex: shortcutIndex,
    scanHint: scanHint,
    hintKey: hintKey,
    enrollFailure: enrollFailure,
    failureKey: failureKey,
    scanKey: scanKey,
    verifyOutcome: verifyOutcome,
    errorKey: errorKey,
    progress: progress
  }
}
