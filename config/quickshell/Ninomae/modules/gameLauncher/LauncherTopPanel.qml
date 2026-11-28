import qs.modules.common
import qs.modules.common.functions
import QtQuick

/**
 * A panel that grows up out of the game launcher's top edge, on the same blob and drawer curves as
 * the details page's side menus (flipped, so its "bar" edge is the launcher's top). Base of the
 * details page's Screenshots, Achievements, News, Customize and Launch options; children go inside it. Keys come from the details
 * page while it's open, through the panel's handleKey(key, modifiers) (returns whether it used the key).
 * After a click inside it (a button took the keys), the keys its controls don't use come up here instead.
 *
 * Placed by GameLauncher.qml (one at a time): as wide as the launcher, its bottom on the launcher's top
 * edge (its blob one shape with the launcher's, so there's no seam), riding with the launcher's own slide.
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
    // The launcher's blob group (from GameLauncher.qml): the panel's blob joins it, so the two are one shape and
    // every pixel is drawn once. Two shapes left a line where they met with glass on: stacked, a dark strip,
    // edge to edge, a bright hairline. Without it (null) the panel has its own stand-in edge, overlap px behind
    property var joinGroup: null
    property real overlap: joinGroup ? 0 : 3 // How far it reaches behind the launcher's top edge
    // Whole pixels, and centred on one: its edges then fall between pixels, where it and the launcher's
    // blob agree who draws (on a half pixel both did, a thin dark line up each side of the join)
    readonly property real paneW: Math.round(Math.min(panelWidth, maxWidth))
    readonly property real paneH: Math.round(Math.min(panelHeight, maxHeight))
    readonly property real paneX: Math.round((width - paneW) / 2)
    // For the contents' edge fades: the panel's own glass when Glass panels is on, so they don't show as a solid band
    readonly property color backgroundColor: Appearance.colors.glassOn ? ColorUtils.transparentize(Appearance.m3colors.m3background, 0.2) : Appearance.m3colors.m3background
    // Glass for the pieces a panel puts on a picture (its banner's buttons and switches)
    readonly property color glassOverArt: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.4)
    readonly property color glassOverArtHover: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.2)
    default property alias content: pane.data

    // ── Drawer animation (as the side menus') ──
    property real offset: shown ? 0 : 1 // 0 = out, 1 = tucked into the launcher
    // Out and still: hover only picks an item from then on, not whatever slides under the pointer as it rises
    readonly property bool settled: shown && offset === 0
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
    visible: offset < 1

    // ── The blob, flipped so its "bar" edge is the launcher's top edge (y = 0 at the bottom) ──
    Item {
        id: stage
        anchors.fill: parent
        transform: Scale { yScale: -1; origin.y: stage.height / 2 }
        clip: !root.joinGroup // Joined, what reaches into the launcher is the launcher's own fill
        Loader {
            anchors.fill: parent
            active: root.visible
            source: Qt.resolvedUrl("../overview/BlobDrawerBackground.qml")
            onLoaded: {
                item.barBottom = 0;
                item.barHeight = 40;
                item.barRadius = 0;
                item.joinGroup = Qt.binding(() => root.joinGroup);
                item.fillColor = Appearance.m3colors.m3background; // Same fill as the launcher, so they read as one
                item.fillOpacity = Qt.binding(() => Appearance.colors.glassOn ? 0.8 : 1.0); // Glass: the launcher's own 80 %
                item.drawerX = Qt.binding(() => root.paneX);
                item.drawerY = Qt.binding(() => root._y);
                item.drawerWidth = Qt.binding(() => root.paneW);
                item.drawerHeight = Qt.binding(() => root._len);
                item.drawerRadius = Qt.binding(() => Math.min(Appearance.rounding.windowRounding + 6, root._shown / 2));
            }
        }
    }

    // ── Contents, sliding up with the drawer (out of sight below the launcher's top edge) ──
    Item {
        anchors.fill: parent
        clip: true
        Item {
            id: pane
            x: root.paneX
            y: root.height - root._shown
            width: root.paneW
            height: root.paneH
            opacity: 1 - root.offset
            clip: root.clipContent
            // Clicks (and hover) here don't fall through to the launcher's click-off-to-close
            MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.AllButtons }
        }
    }
    // A click on one of its buttons gives that button the keys: what it doesn't use (Esc, the arrows) rises to here.
    // Esc closes it even when its own handler doesn't take it (Tags and Add a game keep theirs on one item)
    Keys.onPressed: event => {
        if (typeof root.handleKey === "function" && root.handleKey(event.key, event.modifiers)) event.accepted = true;
        else if (event.key === Qt.Key_Escape) { root.closeRequested(); event.accepted = true; }
    }
}
