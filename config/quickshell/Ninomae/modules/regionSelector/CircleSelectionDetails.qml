import qs.modules.common
import QtQuick
import QtQuick.Shapes
Item {
    id: root
    required property color color
    required property color overlayColor
    required property list<point> points
    property int strokeWidth: Config.options.regionSelector.circle.strokeWidth
    property real pixelRatio: 1 // The monitor's scale: the card says the image's size in pixels
    property var action // What letting go does (RegionSelection.SnipAction), for the card
    property real bottomReserve: 0 // The toolbar's height: the card goes over the shape rather than under it
    // What letting go takes: the shape's bounds, padded as RegionSelection pads them
    readonly property real pad: Config.options.regionSelector.circle.padding + strokeWidth / 2
    readonly property var bounds: {
        if (points.length === 0) return null;
        const xs = points.map(p => p.x), ys = points.map(p => p.y);
        const x = Math.min(...xs) - pad, y = Math.min(...ys) - pad;
        return { x: x, y: y, w: Math.max(...xs) + pad - x, h: Math.max(...ys) + pad - y };
    }
    Rectangle {
        id: darkenOverlay
        z: 1
        anchors.fill: parent
        color: root.overlayColor
    }
    Shape {
        id: shape
        z: 2
        anchors.fill: parent
        // No layer: re-rendering a full-screen texture on every mouse move is what hung the Intel GPU
        // with the blob drawers. The curve renderer antialiases the stroke by itself
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            id: shapePath
            strokeWidth: root.strokeWidth
            pathHints: ShapePath.PathLinear
            fillColor: "transparent"
            strokeColor: root.color
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline {
                path: root.points
            }
        }
    }
    // What letting go does, under the shape (over it when there's no room, inside its foot when there's none either)
    readonly property var actionInfo: RegionFunctions.actionInfo(root.action)
    SelectionCard {
        z: 3
        visible: root.bounds !== null
        readonly property real below: (root.bounds?.y ?? 0) + (root.bounds?.h ?? 0) + 8
        readonly property real above: (root.bounds?.y ?? 0) - 8 - height
        x: Math.max(8, Math.min(root.width - width - 8, (root.bounds?.x ?? 0) + ((root.bounds?.w ?? 0) - width) / 2))
        y: below + height <= root.height - root.bottomReserve ? below
            : above >= 8 ? above
            : below - height - 16
        actionIcon: root.actionInfo.icon
        actionName: root.actionInfo.name
        size: `${Math.round((root.bounds?.w ?? 0) * root.pixelRatio)} × ${Math.round((root.bounds?.h ?? 0) * root.pixelRatio)}`
        release: root.actionInfo.release
    }
}
