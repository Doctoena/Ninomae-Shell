import QtQuick
import QtQuick.Shapes
Item {
    id: root
    enum CornerEnum { TopLeft, TopRight, BottomLeft, BottomRight }
    property var corner: RoundCorner.CornerEnum.TopLeft
    property alias rightVisualMargin: shape.anchors.rightMargin
    property alias bottomVisualMargin: shape.anchors.bottomMargin
    property int implicitSize: 25
    property color color: "#000000"
    property bool drawCorner: true // Off: the item stays (for what's inside it) but draws nothing
    implicitWidth: implicitSize
    implicitHeight: implicitSize
    property bool isTopLeft: corner === RoundCorner.CornerEnum.TopLeft
    property bool isBottomLeft: corner === RoundCorner.CornerEnum.BottomLeft
    property bool isTopRight: corner === RoundCorner.CornerEnum.TopRight
    property bool isBottomRight: corner === RoundCorner.CornerEnum.BottomRight
    property bool isTop: isTopLeft || isTopRight
    property bool isBottom: isBottomLeft || isBottomRight
    property bool isLeft: isTopLeft || isBottomLeft
    property bool isRight: isTopRight || isBottomRight
    Shape {
        visible: root.drawCorner
        id: shape
        anchors {
            top: root.isTop ? parent.top : undefined
            bottom: root.isBottom ? parent.bottom : undefined
            left: root.isLeft ? parent.left : undefined
            right: root.isRight ? parent.right : undefined
        }
        preferredRendererType: Shape.CurveRenderer // Antialiases by itself: no layer needed
        ShapePath {
            id: shapePath
            strokeWidth: 0
            fillColor: root.color
            pathHints: ShapePath.PathSolid & ShapePath.PathNonIntersecting
            startX: switch (root.corner) {
                case RoundCorner.CornerEnum.TopLeft:
                case RoundCorner.CornerEnum.BottomLeft: return 0;
                case RoundCorner.CornerEnum.TopRight:
                case RoundCorner.CornerEnum.BottomRight: return root.implicitSize;
            }
            startY: switch (root.corner) {
                case RoundCorner.CornerEnum.TopLeft:
                case RoundCorner.CornerEnum.TopRight: return 0;
                case RoundCorner.CornerEnum.BottomLeft:
                case RoundCorner.CornerEnum.BottomRight: return root.implicitSize;
            }
            PathAngleArc {
                moveToStart: false
                centerX: root.implicitSize - shapePath.startX
                centerY: root.implicitSize - shapePath.startY
                radiusX: root.implicitSize
                radiusY: root.implicitSize
                startAngle: switch (root.corner) {
                    case RoundCorner.CornerEnum.TopLeft: return 180;
                    case RoundCorner.CornerEnum.TopRight: return -90;
                    case RoundCorner.CornerEnum.BottomLeft: return 90;
                    case RoundCorner.CornerEnum.BottomRight: return 0;
                }
                sweepAngle: 90
            }
            PathLine {
                x: shapePath.startX
                y: shapePath.startY
            }
        }
    }
}
