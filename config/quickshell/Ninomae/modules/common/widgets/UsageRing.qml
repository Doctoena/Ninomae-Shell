import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Shapes

// A ring showing how full something is, from the top, clockwise, over a faint track, an icon inside: the bar player's
// progress round its cover and the volume / brightness pop-up. The fill glides to new values
Item {
    id: ring
    property real fraction: 0 // 0–1
    property real size: 44
    property real stroke: 4
    property color colour: Appearance.colors.colPrimary
    property color trackColour: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.88)
    property string icon
    property real iconSize: 19
    property color iconColour: colour
    property real iconFill: 0
    readonly property real centre: size / 2
    readonly property real arcRadius: (size - stroke) / 2
    property real shownFraction: Math.min(1, Math.max(0, fraction))
    Behavior on shownFraction { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
    implicitWidth: size
    implicitHeight: size
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer // Smooth edges without multisampling or a layer
        ShapePath { // The track
            strokeColor: ring.trackColour
            strokeWidth: ring.stroke
            fillColor: "transparent"
            PathAngleArc { centerX: ring.centre; centerY: ring.centre; radiusX: ring.arcRadius; radiusY: ring.arcRadius; startAngle: 0; sweepAngle: 360 }
        }
        ShapePath { // How full
            strokeColor: ring.colour
            strokeWidth: ring.stroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: ring.centre; centerY: ring.centre; radiusX: ring.arcRadius; radiusY: ring.arcRadius; startAngle: -90; sweepAngle: 360 * ring.shownFraction }
        }
    }
    MaterialSymbol {
        anchors.centerIn: parent
        text: ring.icon
        iconSize: ring.iconSize
        fill: ring.iconFill
        color: ring.iconColour
    }
}
