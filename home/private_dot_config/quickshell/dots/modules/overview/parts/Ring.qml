import QtQuick
import QtQuick.Shapes
import qs.modules.overview
import "../js/Model.js" as Model

// Focus ring: a track plus an arc from 12 o'clock clockwise. Vector, so it is
// crisp at 20 px and measurable at 200 px. Static: the arc moves only when the
// owner passes new elapsed/target (a 1 s timer elsewhere), nothing animates.
Item {
    id: r
    property real diameter: Look.ringDiameter
    property real stroke: diameter * Look.ringStroke / Look.ringDiameter
    property real elapsed: 0
    property real target: 0
    property bool dim: false
    property color tone: Look.accent
    readonly property real angle: Model.ringAngle(elapsed, target)
    objectName: "ring"

    implicitWidth: diameter
    implicitHeight: diameter

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // Track
        ShapePath {
            strokeColor: Look.withAlpha(Look.fg, Look.aTrack)
            strokeWidth: r.stroke
            fillColor: "transparent"
            PathAngleArc {
                centerX: r.diameter / 2; centerY: r.diameter / 2
                radiusX: (r.diameter - r.stroke) / 2; radiusY: (r.diameter - r.stroke) / 2
                startAngle: 0; sweepAngle: 360
            }
        }
        // Progress. A full 360 sweep collapses to nothing in some renderers, so cap it.
        ShapePath {
            strokeColor: r.dim ? Look.fgFaint : r.tone
            strokeWidth: r.stroke
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathAngleArc {
                centerX: r.diameter / 2; centerY: r.diameter / 2
                radiusX: (r.diameter - r.stroke) / 2; radiusY: (r.diameter - r.stroke) / 2
                startAngle: -90
                sweepAngle: Math.min(r.angle, 359.9)
            }
        }
    }
}
