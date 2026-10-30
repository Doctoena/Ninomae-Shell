import QtQuick
import QtQuick.Shapes
import qs.modules.common
import qs.modules.common.functions

/**
 * Small filled line graph over quiet guides at 50 % and the baseline (battery popup, resource monitor).
 * points: Qt.point(x, value), both 0–1 (x from the left edge, value from the bottom).
 * Until there are two points, or while hideLine is set, it shows emptyText instead.
 * Extra children (a current-value label) go on top.
 */
Item {
    id: root
    property var points: []
    property color color: Appearance.colors.colPrimary
    property bool hideLine: false
    property string emptyText
    implicitHeight: 64

    readonly property var linePoints: {
        if (points.length < 2 || width <= 0) return [];
        const pad = 2; // Room for the stroke at 0 % and 100 %
        const h = height - pad * 2;
        return points.map(p => Qt.point(width * p.x, pad + h * (1 - p.y)));
    }
    readonly property var fillPoints: linePoints.length
        ? linePoints.concat([Qt.point(width, height), Qt.point(linePoints[0].x, height)]) : []
    readonly property bool lineShown: linePoints.length > 1 && !hideLine

    Repeater {
        model: [0.5, 1]
        Rectangle {
            required property real modelData
            width: root.width
            height: 1
            y: Math.round((root.height - 1) * modelData)
            color: Appearance.colors.colLayer3
        }
    }
    Shape {
        anchors.fill: parent
        visible: root.lineShown
        preferredRendererType: Shape.CurveRenderer // Smooth edges without multisampling or a layer
        ShapePath {
            strokeColor: "transparent"
            fillColor: ColorUtils.transparentize(root.color, 0.85)
            PathPolyline { path: root.fillPoints }
        }
        ShapePath {
            strokeColor: root.color
            strokeWidth: 2
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathPolyline { path: root.linePoints }
        }
    }
    StyledText {
        anchors.centerIn: parent
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        visible: !root.lineShown
        text: root.emptyText
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }
}
