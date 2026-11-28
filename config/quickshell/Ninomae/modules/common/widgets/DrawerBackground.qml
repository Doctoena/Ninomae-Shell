import qs
import qs.modules.common
import QtQuick
import QtQuick.Shapes
import Quickshell

/**
 * Background of a drawer that slides out of the bar: the gooey blob (overview/BlobDrawerBackground.qml,
 * from the Ninomae.Blobs plugin) joined to the bar, or a plain rounded panel without the plugin.
 * Fill the drawer's window with it and bind the drawer's rectangle; give the content
 *     transform: Matrix4x4 { matrix: background.deformMatrix }
 * so it wobbles with the blob.
 * followBar: a drawer hanging from the bar, which becomes a free-standing card while there's no bar on its
 * screen (a fullscreen game, or the bar turned off), instead of a join to nothing.
 * edgeLight (glass): the bar's fine edge light carried on round the drawer, from the tip of one join curve to the
 * other's, as the game page's rail carries its own round its side menus. It grows with the drawer as it opens.
 */
Item {
    id: root
    property real drawerX
    property real drawerY
    property real drawerWidth
    property real drawerHeight
    property real drawerRadius
    // Where the window is on its screen, so the stand-in bar the blob merges with lines up with the
    // real one. Leave at 0 for windows that are centred on the screen
    property real screenWidth: 0
    property real windowScreenX: 0
    property real barHeight: Appearance.sizes.baseBarHeight
    property real barRadius: Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
    property color fillColor: Appearance.colors.colLayer0
    // The bar's own (BarContent): a drawer joined to it is the same glass, so there's no step at the join (with the
    // bar's wells, a different shade read as a line along it)
    property real fillOpacity: Appearance.colors.glassOn ? 0.8 : 0.92
    property real fallbackRadius: drawerRadius
    property real smoothing: 20 // How far its gooey joins reach (the curves' radius)
    property bool active: true
    property bool followBar: false
    property bool edgeLight: true
    readonly property bool attached: !followBar || GlobalStates.barShownOn(root.QsWindow.window?.screen ?? null)

    // The item, not the status: while the loader unloads, the status still says Ready for a moment
    readonly property matrix4x4 deformMatrix: blobLoader.item && attached ? blobLoader.item.deformMatrix : Qt.matrix4x4()
    // The blob's group, for a drawer growing out of this one to join (null without the plugin)
    readonly property var blobGroup: blobLoader.item && attached ? blobLoader.item.blobGroup : null

    Loader {
        id: blobLoader
        anchors.fill: parent
        active: root.active
        // Hidden, not unloaded, while it's a card: a freshly loaded blob didn't draw its join to the bar
        // until the drawer next changed size
        visible: root.attached
        source: Qt.resolvedUrl("../../overview/BlobDrawerBackground.qml")
        onLoaded: {
            item.barBottom = 0;
            item.barHeight = Qt.binding(() => root.barHeight);
            item.barRadius = Qt.binding(() => root.barRadius);
            item.fillColor = Qt.binding(() => root.fillColor);
            item.fillOpacity = Qt.binding(() => root.fillOpacity);
            item.smoothing = Qt.binding(() => root.smoothing);
            item.screenWidth = Qt.binding(() => root.screenWidth);
            item.windowScreenX = Qt.binding(() => root.windowScreenX);
            item.drawerX = Qt.binding(() => root.drawerX);
            item.drawerY = Qt.binding(() => root.drawerY);
            item.drawerWidth = Qt.binding(() => root.drawerWidth);
            item.drawerHeight = Qt.binding(() => root.drawerHeight);
            item.drawerRadius = Qt.binding(() => root.drawerRadius);
        }
    }
    // ── The edge light ──
    // Where the stand-in bar ends (as BlobDrawerBackground clamps it): a join curve only flares where there's bar
    // beside the drawer; at the bar's rounded end the side just runs up to it
    readonly property real _barGap: Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0
    readonly property real _barLeft: screenWidth > 0 ? _barGap - windowScreenX : -1e6
    readonly property real _barRight: screenWidth > 0 ? screenWidth - _barGap - windowScreenX : 1e6
    Shape {
        id: edgeLight
        readonly property real reach: 16 // How far the gooey curve flares out from the drawer along the bar
        readonly property real leftX: root.drawerX + 0.5
        readonly property real rightX: root.drawerX + root.drawerWidth - 0.5
        readonly property real bottomY: root.drawerY + root.drawerHeight - 0.5
        readonly property bool curveLeft: root.drawerX - reach >= root._barLeft + root.barRadius
        readonly property bool curveRight: root.drawerX + root.drawerWidth + reach <= root._barRight - root.barRadius
        readonly property real topLeft: curveLeft ? reach : 0 // Where the side starts, under its curve
        readonly property real topRight: curveRight ? reach : 0
        // The bottom corners, no rounder than the room left under the curves
        readonly property real corner: Math.max(0, Math.min(root.drawerRadius, root.drawerWidth / 2,
            bottomY - Math.max(topLeft, topRight)))
        visible: root.edgeLight && root.active && root.attached
            && blobLoader.status === Loader.Ready && bottomY > Math.max(topLeft, topRight) + 2
        anchors.fill: parent
        transform: Matrix4x4 { matrix: root.deformMatrix } // It wobbles with the blob
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Qt.rgba(1, 1, 1, 0.1) // The bar's rim (white 12 % under its 80 % glass)
            strokeWidth: 1
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            startX: edgeLight.curveLeft ? edgeLight.leftX - 0.5 - edgeLight.reach : edgeLight.leftX
            startY: 0
            PathArc { // Out of the bar, round the join curve into the drawer's side
                x: edgeLight.leftX; y: edgeLight.topLeft
                radiusX: edgeLight.reach; radiusY: edgeLight.reach
                direction: PathArc.Clockwise
            }
            PathLine { x: edgeLight.leftX; y: edgeLight.bottomY - edgeLight.corner }
            PathArc {
                x: edgeLight.leftX + edgeLight.corner; y: edgeLight.bottomY
                radiusX: edgeLight.corner; radiusY: edgeLight.corner
                direction: PathArc.Counterclockwise
            }
            PathLine { x: edgeLight.rightX - edgeLight.corner; y: edgeLight.bottomY }
            PathArc {
                x: edgeLight.rightX; y: edgeLight.bottomY - edgeLight.corner
                radiusX: edgeLight.corner; radiusY: edgeLight.corner
                direction: PathArc.Counterclockwise
            }
            PathLine { x: edgeLight.rightX; y: edgeLight.topRight }
            PathArc { // And back into the bar
                x: edgeLight.curveRight ? edgeLight.rightX + 0.5 + edgeLight.reach : edgeLight.rightX; y: 0
                radiusX: edgeLight.reach; radiusY: edgeLight.reach
                direction: PathArc.Clockwise
            }
        }
    }

    Rectangle { // No bar to join: a card where the drawer is
        visible: root.active && !root.attached && root.drawerHeight > 0
        x: root.drawerX
        y: root.drawerY
        width: root.drawerWidth
        height: root.drawerHeight
        radius: Math.min(root.drawerRadius, root.drawerHeight / 2) // The drawer's own corners
        color: root.fillColor
        opacity: root.fillOpacity
    }
    Rectangle { // Without the plugin (not while it's loading: this one doesn't join the bar)
        visible: blobLoader.status === Loader.Error && root.attached
        x: root.drawerX
        y: root.drawerY - 30 // Tucked up under the bar
        width: root.drawerWidth
        height: root.drawerHeight + 30
        radius: root.fallbackRadius
        color: root.fillColor
        opacity: root.fillOpacity
    }
}
