const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../../plugin/FingerprintModel.js")

test("six fingers, left hand first, thumb to middle", () => {
  assert.deepEqual(Model.FINGERS.map(f => f.id), [
    "left-thumb", "left-index-finger", "left-middle-finger",
    "right-thumb", "right-index-finger", "right-middle-finger",
  ])
  assert.equal(Model.fingerIndex("right-index-finger"), 4)
  assert.equal(Model.fingerIndex("left-little-finger"), -1)
})

test("arrows move within the 2x3 grid and down to the test area", () => {
  assert.equal(Model.move(0, "right", 0), 3)
  assert.equal(Model.move(3, "right", 1), 3)
  assert.equal(Model.move(4, "left", 1), 1)
  assert.equal(Model.move(0, "up", 0), 0)
  assert.equal(Model.move(1, "down", 0), 2)
  assert.equal(Model.move(2, "down", 0), Model.VERIFY_INDEX)
  assert.equal(Model.move(5, "down", 1), Model.VERIFY_INDEX)
})

test("up from the test area returns to the last column", () => {
  assert.equal(Model.move(Model.VERIFY_INDEX, "up", 0), 2)
  assert.equal(Model.move(Model.VERIFY_INDEX, "up", 1), 5)
  assert.equal(Model.move(Model.VERIFY_INDEX, "left", 1), Model.VERIFY_INDEX)
  assert.equal(Model.move(Model.VERIFY_INDEX, "down", 1), Model.VERIFY_INDEX)
})

test("Tab walks every stop and wraps", () => {
  assert.equal(Model.step(5, 1), Model.VERIFY_INDEX)
  assert.equal(Model.step(Model.VERIFY_INDEX, 1), 0)
  assert.equal(Model.step(0, -1), Model.VERIFY_INDEX)
})

test("digits 1-6 pick a finger", () => {
  assert.equal(Model.shortcutIndex("1"), 0)
  assert.equal(Model.shortcutIndex("6"), 5)
  for (const text of ["0", "7", "", "12", "a", undefined]) assert.equal(Model.shortcutIndex(text), -1)
})

test("enroll results map to messages and tones", () => {
  assert.deepEqual(Model.enrollStatus("enroll-started", "press"), { key: "fingerprint.touch", tone: "info" })
  assert.deepEqual(Model.enrollStatus("enroll-started", "swipe"), { key: "fingerprint.swipe", tone: "info" })
  assert.equal(Model.enrollStatus("enroll-stage-passed").key, "fingerprint.stagePassed")
  assert.deepEqual(Model.enrollStatus("enroll-retry-scan"), { key: "fingerprint.retryScan", tone: "info" })
  assert.equal(Model.enrollStatus("enroll-finger-not-centered").key, "fingerprint.notCentered")
  assert.deepEqual(Model.enrollStatus("enroll-completed"), { key: "fingerprint.enroll.completed", tone: "success" })
  assert.deepEqual(Model.enrollStatus("enroll-duplicate"), { key: "fingerprint.enroll.duplicate", tone: "error" })
  assert.deepEqual(Model.enrollStatus("enroll-disconnected"), { key: "fingerprint.disconnected", tone: "error" })
  assert.deepEqual(Model.enrollStatus("enroll-unknown-error"), { key: "fingerprint.enroll.failed", tone: "error" })
})

test("verify results map to messages and tones", () => {
  assert.equal(Model.verifyStatus("verify-started", "press").key, "fingerprint.touch")
  assert.deepEqual(Model.verifyStatus("verify-match"), { key: "fingerprint.verify.match", tone: "success" })
  assert.deepEqual(Model.verifyStatus("verify-no-match"), { key: "fingerprint.verify.noMatch", tone: "error" })
  assert.deepEqual(Model.verifyStatus("verify-swipe-too-short"), { key: "fingerprint.swipeTooShort", tone: "info" })
  assert.equal(Model.verifyStatus("verify-unknown-error").tone, "error")
})

test("helper error codes map to messages", () => {
  assert.equal(Model.errorKey("permission-denied"), "fingerprint.error.permissionDenied")
  assert.equal(Model.errorKey("no-service"), "fingerprint.noService")
  assert.equal(Model.errorKey("whatever"), "fingerprint.error.generic")
})

test("progress is a clamped fraction, or -1 without a stage count", () => {
  assert.equal(Model.progress(0, 10, false), 0)
  assert.equal(Model.progress(5, 10, false), 0.5)
  assert.equal(Model.progress(12, 10, false), 1)
  assert.equal(Model.progress(3, -1, false), -1)
  assert.equal(Model.progress(3, -1, true), 1)
})

function length(ops) {
  let total = 0
  let at = ops.start
  for (const op of ops.ops) {
    if (op.type === "line") {
      total += Math.hypot(op.x - at.x, op.y - at.y)
      at = { x: op.x, y: op.y }
    } else {
      total += Math.abs(op.a1 - op.a0) * op.r
      at = { x: op.cx + op.r * Math.cos(op.a1), y: op.cy + op.r * Math.sin(op.a1) }
    }
  }
  return { total, end: at }
}

const close = (a, b) => assert.ok(Math.abs(a - b) < 1e-9, `${a} != ${b}`)

test("the square frame starts at the top centre and closes on itself", () => {
  const ops = Model.pathOps(10, 20, 100, 15, 0, 1)
  assert.deepEqual(ops.start, { x: 60, y: 20 })
  const walked = length(ops)
  close(walked.total, Model.perimeter(100, 15))
  close(walked.end.x, 60)
  close(walked.end.y, 20)
  assert.equal(ops.ops.filter(op => op.type === "arc").length, 4)
})

test("partial progress draws that share of the perimeter, clockwise", () => {
  for (const fraction of [0.1, 0.25, 0.5, 0.8]) close(length(Model.pathOps(0, 0, 100, 15, 0, fraction)).total, Model.perimeter(100, 15) * fraction)
  // A quarter of a sharp square: half the top edge, then half the right edge.
  const quarter = length(Model.pathOps(0, 0, 100, 0, 0, 0.25))
  close(quarter.end.x, 100)
  close(quarter.end.y, 50)
  // A stretch that starts mid-way (the spinner) starts on the frame.
  const spin = Model.pathOps(0, 0, 100, 0, 0.5, 0.75)
  close(spin.start.x, 50)
  close(spin.start.y, 100)
  assert.equal(Model.pathOps(0, 0, 100, 10, 0, 0).start, null)
})

test("a radius over half the side becomes a circle", () => {
  close(Model.perimeter(100, 80), Math.PI * 100)
})
