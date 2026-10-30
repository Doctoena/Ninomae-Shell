import qs.modules.common
import QtQuick

/**
 * A panel that grows up out of the game launcher's top edge, on the same blob and drawer curves as
 * the details page's side menus (flipped, so its "bar" edge is the launcher's top). Base of the
 * details page's Screenshots, Achievements and News; children go inside it. Keys come from the details
 * page while it's open, through the panel's handleKey(key, modifiers) (returns whether it used the key).
 *
 * Placed by GameLauncher.qml (one at a time): as wide as the launcher, its bottom a few px behind the
 * launcher's top edge (same colour there, so there's no seam), riding with the launcher's own slide.
 */
Item {
    id: root
    property bool shown: false
    signal closeRequested()
    property real panelWidth: 1200   // Wanted size, capped by the room the launcher gives (max…)
    property real panelHeight: 640
    property bool clipContent: true
    property real maxWidth: 1200     // From the launcher: the room there is
    property real maxHeight: 560
    property real overlap: 3 // How far it reaches behind the launcher's top edge
    readonly property real paneW: Math.min(panelWidth, maxWidth)
    readonly property real paneH: Math.min(panelHeight, maxHeight)
    readonly property color backgroundColor: Appearance.m3colors.m3background // For the contents' edge fades
    default property alias content: pane.data

    // ── Drawer animation (as the side menus') ──
    property real offset: shown ? 0 : 1 // 0 = out, 1 = tucked into the launcher
    Behavior on offset {
        NumberAnimation {
            duration: root.shown ? Appearance.animationCurves.drawerOpenDuration + Appearance.animationCurves.drawerLargeExtra : Appearance.animationCurves.drawerCloseDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.shown ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
        }
    }
    readonly property real _top: -(paneH + 60) * offset
    readonly property real _y: Math.min(0, _top)
    readonly property real _len: paneH + Math.max(0, _top) // Overshoot stretches
    readonly property real _shown: Math.max(0, _y + _len)
    height: paneH + 40
    clip: true
    visible: offset < 1

    // ── The blob, flipped so its "bar" edge is the launcher's top edge (y = 0 at the bottom) ──
    Item {
        id: stage
        anchors.fill: parent
        transform: Scale { yScale: -1; origin.y: stage.height / 2 }
        Loader {
            anchors.fill: parent
            active: root.visible
            source: Qt.resolvedUrl("../overview/BlobDrawerBackground.qml")
            onLoaded: {
                item.barBottom = 0;
                item.barHeight = 40;
                item.barRadius = 0;
                item.fillColor = root.backgroundColor; // Same fill as the launcher, so they read as one
                item.fillOpacity = 1.0;
                item.drawerX = Qt.binding(() => (stage.width - root.paneW) / 2);
                item.drawerY = Qt.binding(() => root._y);
                item.drawerWidth = Qt.binding(() => root.paneW);
                item.drawerHeight = Qt.binding(() => root._len);
                item.drawerRadius = Qt.binding(() => Math.min(Appearance.rounding.windowRounding + 6, root._shown / 2));
            }
        }
    }

    // ── Contents, sliding up with the drawer ──
    Item {
        id: pane
        x: (root.width - root.paneW) / 2
        y: root.height - root._shown
        width: root.paneW
        height: root.paneH
        opacity: 1 - root.offset
        clip: root.clipContent
        // Clicks (and hover) here don't fall through to the launcher's click-off-to-close
        MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.AllButtons }
    }
}
