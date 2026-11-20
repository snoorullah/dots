.pragma library
// Equalizer bar heights as a pure function of time, so 36 bars share one clock and a
// negative start delay is just an offset. Shape: the four keyframe curves of the board.
// Each row: [amplitude, curve, period (s), delay (s)]. Nothing here is audio-reactive yet.

var count = 36

var bars = [
  [0.40, "c", 1.07, -0.81],
  [0.47, "c", 0.66, -0.49],
  [0.43, "a", 0.96, -1.29],
  [0.58, "b", 0.64, -1.30],
  [0.62, "d", 1.33, -0.85],
  [0.62, "a", 0.91, -0.32],
  [0.66, "c", 1.18, -0.74],
  [0.69, "a", 1.07, -1.21],
  [0.63, "c", 1.26, -0.33],
  [0.61, "b", 1.13, -0.15],
  [0.58, "c", 0.75, -0.84],
  [0.60, "c", 0.99, -1.12],
  [0.61, "c", 0.67, -1.22],
  [0.58, "d", 1.26, -0.34],
  [0.50, "c", 1.27, -1.14],
  [0.46, "b", 1.22, -0.67],
  [0.50, "b", 1.30, -0.62],
  [0.59, "c", 0.99, -0.49],
  [0.60, "d", 0.84, -1.06],
  [0.68, "d", 0.89, -0.67],
  [0.72, "c", 1.01, -0.42],
  [0.77, "a", 1.18, -0.73],
  [0.79, "c", 1.24, -0.94],
  [0.85, "a", 1.13, -0.86],
  [0.77, "d", 1.07, -0.48],
  [0.78, "b", 0.72, -1.20],
  [0.76, "c", 1.23, -0.25],
  [0.71, "d", 0.62, -1.27],
  [0.70, "a", 0.90, -0.99],
  [0.62, "a", 1.28, -0.44],
  [0.53, "d", 1.09, -0.46],
  [0.54, "d", 1.04, -0.23],
  [0.42, "d", 0.91, -0.25],
  [0.42, "a", 0.70, -0.15],
  [0.37, "c", 0.64, -0.89],
  [0.41, "c", 1.00, -0.40]
]

// keyframes: [percent, factor]; factor 1 means the bar's own amplitude
var curves = {
  a: [[0, 0.22], [30, 0.95], [55, 0.4], [80, 1], [100, 0.22]],
  b: [[0, 0.7], [25, 0.18], [60, 1], [100, 0.7]],
  c: [[0, 0.35], [20, 1], [45, 0.25], [70, 0.8], [100, 0.35]],
  d: [[0, 0.9], [40, 0.3], [75, 0.6], [100, 0.9]]
}

// scaleY of bar i at t seconds, eased linearly between keyframes (board uses ease-in-out;
// the 20 fps tick makes the difference invisible)
function scale(i, t) {
  var b = bars[i % count]
  var period = b[2]
  var p = (((t - b[3]) / period) % 1 + 1) % 1 * 100
  var k = curves[b[1]]
  for (var j = 1; j < k.length; j++) {
    if (p <= k[j][0]) {
      var f = (p - k[j - 1][0]) / (k[j][0] - k[j - 1][0])
      var e = f * f * (3 - 2 * f)
      return b[0] * (k[j - 1][1] + (k[j][1] - k[j - 1][1]) * e)
    }
  }
  return b[0] * k[k.length - 1][1]
}

// paused: the board's rest height, amplitude * 0.4
function rest(i) { return bars[i % count][0] * 0.4 }
