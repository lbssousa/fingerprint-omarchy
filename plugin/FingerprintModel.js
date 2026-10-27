// Pure helpers for the fingerprint overlay, kept out of QML so node can test
// them (tests/js/).

// The six fingers offered, as fprintd names them. The grid shows the left
// hand in the first column and the right hand in the second, thumb to
// middle finger from the top; digits 1-6 pick them in this order.
var FINGERS = [
  { id: "left-thumb", hand: "left", kind: "thumb" },
  { id: "left-index-finger", hand: "left", kind: "index" },
  { id: "left-middle-finger", hand: "left", kind: "middle" },
  { id: "right-thumb", hand: "right", kind: "thumb" },
  { id: "right-index-finger", hand: "right", kind: "index" },
  { id: "right-middle-finger", hand: "right", kind: "middle" }
]
var ROWS = 3
// The cursor's stop after the grid: the verification area.
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
// "down" (already mirrored for right-to-left reading); lastColumn is the grid
// column to come back to from the verification area.
function move(index, direction, lastColumn) {
  if (index === VERIFY_INDEX) {
    if (direction === "up") return (lastColumn === 1 ? ROWS : 0) + ROWS - 1
    return index
  }
  var c = column(index)
  var r = row(index)
  if (direction === "left") c = 0
  else if (direction === "right") c = 1
  else if (direction === "up") r = Math.max(0, r - 1)
  else if (direction === "down") {
    if (r === ROWS - 1) return VERIFY_INDEX
    r += 1
  }
  return c * ROWS + r
}

// Tab order: the six fingers, then the verification area, then around.
function step(index, delta) {
  var stops = FINGERS.length + 1
  return ((index + delta) % stops + stops) % stops
}

// Digits 1-6 jump straight to a finger.
function shortcutIndex(text) {
  var digit = String(text || "")
  if (digit.length !== 1 || digit < "1" || digit > "6") return -1
  return digit.charCodeAt(0) - "1".charCodeAt(0)
}

function scanPromptKey(scanType) {
  return scanType === "swipe" ? "fingerprint.swipe" : "fingerprint.touch"
}

// fprintd's scan feedback shared by enroll and verify ("enroll-retry-scan",
// "verify-retry-scan"), keyed by the part after the prefix.
var SCAN_FEEDBACK = {
  "retry-scan": "fingerprint.retryScan",
  "swipe-too-short": "fingerprint.swipeTooShort",
  "finger-not-centered": "fingerprint.notCentered",
  "remove-and-retry": "fingerprint.removeAndRetry",
  "disconnected": "fingerprint.disconnected"
}

function feedbackKey(result, prefix) {
  var suffix = String(result || "").indexOf(prefix) === 0 ? result.slice(prefix.length) : ""
  return SCAN_FEEDBACK[suffix] || ""
}

// The status line for an enroll event, and how it reads: "info" while
// scanning, "success" once enrolled, "error" when the enrollment ended
// without a print.
function enrollStatus(result, scanType) {
  switch (result) {
  case "enroll-started": return { key: scanPromptKey(scanType), tone: "info" }
  case "enroll-stage-passed": return { key: "fingerprint.stagePassed", tone: "info" }
  case "enroll-completed": return { key: "fingerprint.enroll.completed", tone: "success" }
  case "enroll-duplicate": return { key: "fingerprint.enroll.duplicate", tone: "error" }
  case "enroll-data-full": return { key: "fingerprint.enroll.dataFull", tone: "error" }
  case "enroll-disconnected": return { key: "fingerprint.disconnected", tone: "error" }
  }
  var feedback = feedbackKey(result, "enroll-")
  if (feedback) return { key: feedback, tone: "info" }
  return { key: "fingerprint.enroll.failed", tone: "error" }
}

function verifyStatus(result, scanType) {
  switch (result) {
  case "verify-started": return { key: scanPromptKey(scanType), tone: "info" }
  case "verify-match": return { key: "fingerprint.verify.match", tone: "success" }
  case "verify-no-match": return { key: "fingerprint.verify.noMatch", tone: "error" }
  case "verify-disconnected": return { key: "fingerprint.disconnected", tone: "error" }
  }
  var feedback = feedbackKey(result, "verify-")
  if (feedback) return { key: feedback, tone: "info" }
  return { key: "fingerprint.verify.failed", tone: "error" }
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

// How much of the square to draw: 0-1, or -1 when the driver gives no stage
// count (the frame then spins instead).
function progress(stage, total, completed) {
  if (completed) return 1
  if (!(total > 0)) return -1
  return Math.max(0, Math.min(1, stage / total))
}

// The rounded square around the fingerprint, as drawing steps for a Canvas
// path. It starts at the top centre and runs clockwise (screen coordinates,
// y down): half the top edge, a corner, the right edge, ... back to the top
// centre. pathOps(x, y, side, radius, from, to) returns the stretch between
// the fractions from and to (0 <= from <= to <= 1) of the perimeter as a
// start point plus "line" and "arc" steps:
//   { start: {x, y}, ops: [{type: "line", x, y} |
//                          {type: "arc", cx, cy, r, a0, a1}] }
function squareSegments(x, y, side, radius) {
  var r = Math.max(0, Math.min(radius, side / 2))
  var straight = side - 2 * r
  var quarter = Math.PI * r / 2
  var half = Math.PI / 2
  return [
    { type: "line", length: straight / 2, x0: x + side / 2, y0: y, x1: x + side - r, y1: y },
    { type: "arc", length: quarter, cx: x + side - r, cy: y + r, r: r, a0: -half, a1: 0 },
    { type: "line", length: straight, x0: x + side, y0: y + r, x1: x + side, y1: y + side - r },
    { type: "arc", length: quarter, cx: x + side - r, cy: y + side - r, r: r, a0: 0, a1: half },
    { type: "line", length: straight, x0: x + side - r, y0: y + side, x1: x + r, y1: y + side },
    { type: "arc", length: quarter, cx: x + r, cy: y + side - r, r: r, a0: half, a1: Math.PI },
    { type: "line", length: straight, x0: x, y0: y + side - r, x1: x, y1: y + r },
    { type: "arc", length: quarter, cx: x + r, cy: y + r, r: r, a0: Math.PI, a1: Math.PI + half },
    { type: "line", length: straight / 2, x0: x + r, y0: y, x1: x + side / 2, y1: y }
  ]
}

function perimeter(side, radius) {
  var r = Math.max(0, Math.min(radius, side / 2))
  return 4 * (side - 2 * r) + 2 * Math.PI * r
}

function pointAt(segment, t) {
  if (segment.type === "line")
    return { x: segment.x0 + (segment.x1 - segment.x0) * t, y: segment.y0 + (segment.y1 - segment.y0) * t }
  var a = segment.a0 + (segment.a1 - segment.a0) * t
  return { x: segment.cx + segment.r * Math.cos(a), y: segment.cy + segment.r * Math.sin(a) }
}

function pathOps(x, y, side, radius, from, to) {
  var segments = squareSegments(x, y, side, radius)
  var total = perimeter(side, radius)
  var startLen = Math.max(0, Math.min(1, from)) * total
  var endLen = Math.max(0, Math.min(1, to)) * total
  var out = { start: null, ops: [] }
  var walked = 0
  for (var i = 0; i < segments.length; i++) {
    var s = segments[i]
    var segStart = walked
    var segEnd = walked + s.length
    walked = segEnd
    if (s.length <= 0 || segEnd <= startLen || segStart >= endLen) continue
    var t0 = (Math.max(startLen, segStart) - segStart) / s.length
    var t1 = (Math.min(endLen, segEnd) - segStart) / s.length
    if (!out.start) out.start = pointAt(s, t0)
    if (s.type === "line") {
      var p = pointAt(s, t1)
      out.ops.push({ type: "line", x: p.x, y: p.y })
    } else {
      out.ops.push({ type: "arc", cx: s.cx, cy: s.cy, r: s.r,
                     a0: s.a0 + (s.a1 - s.a0) * t0, a1: s.a0 + (s.a1 - s.a0) * t1 })
    }
  }
  return out
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
    enrollStatus: enrollStatus,
    verifyStatus: verifyStatus,
    errorKey: errorKey,
    progress: progress,
    perimeter: perimeter,
    pathOps: pathOps
  }
}
