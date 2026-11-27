const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../../FingerprintModel.js")

test("six fingers, left hand first, thumb to middle", () => {
  assert.deepEqual(Model.FINGERS.map(f => f.id), [
    "left-thumb", "left-index-finger", "left-middle-finger",
    "right-thumb", "right-index-finger", "right-middle-finger",
  ])
  assert.equal(Model.fingerIndex("right-index-finger"), 4)
  assert.equal(Model.fingerIndex("left-little-finger"), -1)
})

test("arrows move within the 2x3 chooser and up to the print", () => {
  assert.equal(Model.move(0, "right", 0), 3)
  assert.equal(Model.move(3, "right", 1), 3)
  assert.equal(Model.move(4, "left", 1), 1)
  assert.equal(Model.move(1, "up", 0), 0)
  assert.equal(Model.move(1, "down", 0), 2)
  assert.equal(Model.move(2, "down", 0), 2)
  assert.equal(Model.move(0, "up", 0), Model.VERIFY_INDEX)
  assert.equal(Model.move(3, "up", 1), Model.VERIFY_INDEX)
})

test("down from the print returns to the top of the last column", () => {
  assert.equal(Model.move(Model.VERIFY_INDEX, "down", 0), 0)
  assert.equal(Model.move(Model.VERIFY_INDEX, "down", 1), 3)
  assert.equal(Model.move(Model.VERIFY_INDEX, "left", 1), Model.VERIFY_INDEX)
  assert.equal(Model.move(Model.VERIFY_INDEX, "up", 1), Model.VERIFY_INDEX)
})

test("Tab walks the print, then the fingers, and wraps", () => {
  assert.equal(Model.step(Model.VERIFY_INDEX, 1), 0)
  assert.equal(Model.step(2, 1), 3)
  assert.equal(Model.step(5, 1), Model.VERIFY_INDEX)
  assert.equal(Model.step(0, -1), Model.VERIFY_INDEX)
  assert.equal(Model.step(Model.VERIFY_INDEX, -1), 5)
})

test("digits 1-6 pick a finger", () => {
  assert.equal(Model.shortcutIndex("1"), 0)
  assert.equal(Model.shortcutIndex("6"), 5)
  for (const text of ["0", "7", "", "12", "a", undefined]) assert.equal(Model.shortcutIndex(text), -1)
})

test("scan feedback becomes the hints Omarchy's panel words", () => {
  assert.equal(Model.scanHint("enroll-retry-scan"), "again")
  assert.equal(Model.scanHint("verify-swipe-too-short"), "short")
  assert.equal(Model.scanHint("enroll-finger-not-centered"), "center")
  assert.equal(Model.scanHint("verify-remove-and-retry"), "lift")
  assert.equal(Model.scanHint("enroll-too-fast"), "fast")
  for (const result of ["enroll-stage-passed", "enroll-completed", "verify-match", "", undefined]) assert.equal(Model.scanHint(result), "")
  assert.equal(Model.hintKey("center"), "fingerprint.retryCenter")
  assert.equal(Model.hintKey(""), "")
})

test("the scanning line: the complaint first, then touch, then touch again", () => {
  assert.equal(Model.scanKey("press", 0, ""), "fingerprint.touch")
  assert.equal(Model.scanKey("press", 3, ""), "fingerprint.touchAgain")
  assert.equal(Model.scanKey("swipe", 0, ""), "fingerprint.swipe")
  assert.equal(Model.scanKey("swipe", 1, ""), "fingerprint.swipeAgain")
  assert.equal(Model.scanKey("press", 3, "lift"), "fingerprint.retryLift")
  assert.equal(Model.scanKey(undefined, 0, ""), "fingerprint.touch")
})

test("enrollment failures read as Omarchy's panel words them", () => {
  assert.equal(Model.enrollFailure("enroll-duplicate"), "duplicate")
  assert.equal(Model.enrollFailure("enroll-data-full"), "full")
  assert.equal(Model.enrollFailure("enroll-disconnected"), "disconnected")
  assert.equal(Model.enrollFailure("enroll-unknown-error"), "enroll")
  assert.equal(Model.failureKey("duplicate"), "fingerprint.failDuplicate")
  assert.equal(Model.failureKey("enroll"), "fingerprint.failEnroll")
  assert.equal(Model.failureKey("permission-denied"), "fingerprint.error.permissionDenied")
  assert.equal(Model.failureKey("whatever"), "fingerprint.error.generic")
})

test("a finished test is a match, no match, or a failure", () => {
  assert.equal(Model.verifyOutcome("verify-match"), "match")
  assert.equal(Model.verifyOutcome("verify-no-match"), "no-match")
  for (const result of ["verify-timeout", "verify-disconnected", "verify-unknown-error"]) assert.equal(Model.verifyOutcome(result), "failed")
})

test("helper error codes map to messages", () => {
  assert.equal(Model.errorKey("permission-denied"), "fingerprint.error.permissionDenied")
  assert.equal(Model.errorKey("no-service"), "fingerprint.noService")
  assert.equal(Model.errorKey("whatever"), "fingerprint.error.generic")
})

test("progress lights the print as Omarchy's panel does", () => {
  assert.equal(Model.progress(0, 10, false), 0)
  assert.equal(Model.progress(5, 10, false), 0.5)
  // Short of full until the reader says the print is in.
  assert.equal(Model.progress(10, 10, false), 0.96)
  assert.equal(Model.progress(12, 10, false), 0.96)
  assert.equal(Model.progress(3, 10, true), 1)
  // No stage count: closing in on full, never reaching it.
  assert.equal(Model.progress(0, -1, false), 0)
  assert.ok(Math.abs(Model.progress(1, -1, false) - 0.15) < 1e-9)
  assert.ok(Model.progress(20, -1, false) < 1)
  assert.equal(Model.progress(3, -1, true), 1)
})
