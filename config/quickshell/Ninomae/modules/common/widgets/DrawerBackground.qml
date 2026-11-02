import qs
import qs.modules.common
import QtQuick
import Quickshell

/**
 * Background of a drawer that slides out of the bar: the gooey blob (overview/BlobDrawerBackground.qml,
 * from the Ninomae.Blobs plugin) joined to the bar, or a plain rounded panel without the plugin.
 * Fill the drawer's window with it and bind the drawer's rectangle; give the content
 *     transform: Matrix4x4 { matrix: background.deformMatrix }
 * so it wobbles with the blob.
 * followBar: a drawer hanging from the bar, which becomes a free-standing card while there's no bar on its
 * screen (a fullscreen game, or the bar turned off), instead of a join to nothing.
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
    property real fillOpacity: 0.92
    property real fallbackRadius: drawerRadius
    property bool active: true
    property bool followBar: false
    readonly property bool attached: !followBar || GlobalStates.barShownOn(root.QsWindow.window?.screen ?? null)

    // The item, not the status: while the loader unloads, the status still says Ready for a moment
    readonly property matrix4x4 deformMatrix: blobLoader.item && attached ? blobLoader.item.deformMatrix : Qt.matrix4x4()

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
            item.screenWidth = Qt.binding(() => root.screenWidth);
            item.windowScreenX = Qt.binding(() => root.windowScreenX);
            item.drawerX = Qt.binding(() => root.drawerX);
            item.drawerY = Qt.binding(() => root.drawerY);
            item.drawerWidth = Qt.binding(() => root.drawerWidth);
            item.drawerHeight = Qt.binding(() => root.drawerHeight);
            item.drawerRadius = Qt.binding(() => root.drawerRadius);
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
