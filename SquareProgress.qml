import QtQuick
import qs.Commons
import "FingerprintModel.js" as Model

// A rounded square frame that fills clockwise from the top centre as the
// enrollment advances: a faint track, then the progress stroke over it.
// progress < 0 (the driver gives no stage count) spins a short stroke.
Canvas {
  id: frame

  property real progress: 0
  property real lineWidth: Style.space(5)
  property real cornerRadius: Style.space(18)
  property color trackColor: "gray"
  property color strokeColor: "white"

  readonly property bool indeterminate: progress < 0
  property real shownProgress: Math.max(0, progress)
  property real spin: 0

  Behavior on shownProgress {
    NumberAnimation { duration: Style.duration(260); easing.type: Easing.OutCubic }
  }

  NumberAnimation on spin {
    from: 0
    to: 1
    duration: 1400
    loops: Animation.Infinite
    running: frame.indeterminate && frame.visible && !Style.reduceMotion
  }

  onShownProgressChanged: requestPaint()
  onSpinChanged: if (indeterminate) requestPaint()
  onIndeterminateChanged: requestPaint()
  onTrackColorChanged: requestPaint()
  onStrokeColorChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  function trace(ctx, ops) {
    if (!ops.start) return
    ctx.moveTo(ops.start.x, ops.start.y)
    for (var i = 0; i < ops.ops.length; i++) {
      var op = ops.ops[i]
      if (op.type === "line") ctx.lineTo(op.x, op.y)
      else ctx.arc(op.cx, op.cy, op.r, op.a0, op.a1, false)
    }
  }

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var inset = lineWidth / 2
    var side = Math.min(width, height) - lineWidth
    var x = (width - side) / 2
    var y = (height - side) / 2
    var radius = Math.max(0, cornerRadius - inset)
    ctx.lineWidth = lineWidth
    ctx.lineCap = "round"
    ctx.lineJoin = "round"

    ctx.strokeStyle = trackColor
    ctx.beginPath()
    trace(ctx, Model.pathOps(x, y, side, radius, 0, 1))
    ctx.closePath()
    ctx.stroke()

    ctx.strokeStyle = strokeColor
    ctx.beginPath()
    if (indeterminate) {
      // A quarter of the frame chasing round; split where it wraps past the top.
      var from = spin
      var to = spin + 0.25
      trace(ctx, Model.pathOps(x, y, side, radius, from, Math.min(1, to)))
      if (to > 1) trace(ctx, Model.pathOps(x, y, side, radius, 0, to - 1))
    } else if (shownProgress > 0) {
      trace(ctx, Model.pathOps(x, y, side, radius, 0, shownProgress))
    }
    ctx.stroke()
  }
}
