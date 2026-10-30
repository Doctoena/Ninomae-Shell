import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * Hover popup that slides out of the top bar as a gooey drawer, the same way the
 * launcher (overview/SearchWidget.qml) does: set hoverTarget and give it the content. Assumes a horizontal bar at the top.
 */
LazyLoader {
    id: root
    property Item hoverTarget
    default property Item contentItem
    // false: the caller opens and closes it by binding `wanted` (e.g. the tray overflow, on click)
    property bool openOnHover: true

    // Hover with a short grace period: when a popup window maps, Hyprland can briefly take the
    // pointer off the bar (seen on the battery popup); without this the drawer would stutter.
    readonly property bool hovered: !!hoverTarget && hoverTarget.containsMouse
    property bool wanted: hovered
    onHoveredChanged: {
        if (!openOnHover) return;
        if (hovered) {
            closeDelay.stop();
            wanted = true;
        } else {
            closeDelay.restart();
        }
    }
    property Timer closeDelay: Timer {
        interval: 200
        onTriggered: root.wanted = root.hovered
    }
    // The window is kept from the moment the drawer is wanted until it has slid back under the bar.
    // (Setting a flag on close only if the window was still active raced the window being removed,
    // so the drawer could vanish instead of sliding back; same fix as sessionScreen/SessionScreen.qml.)
    property bool keepWindow: false
    onWantedChanged: if (wanted) keepWindow = true
    property Timer keepWindowTimeout: Timer { // Safety net in case the slide never finishes
        interval: 1500
        running: root.keepWindow && !root.wanted
        onTriggered: root.keepWindow = false
    }
    active: wanted || keepWindow

    component: PanelWindow {
        id: win
        readonly property real sideMargin: 40 // Room for the gooey joins beside the drawer
        readonly property real padding: 12
        readonly property real bottomRadius: 24
        readonly property real hiddenExtra: 60
        readonly property real barBottom: Appearance.sizes.barHeight - (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
        readonly property real panelWidth: root.contentItem.implicitWidth + padding * 2
        readonly property real fullHeight: root.contentItem.implicitHeight + padding * 2

        readonly property bool ready: readiness.ready // Slide only once the window is on screen

        // 0 = out, 1 = tucked under the bar
        property real offsetScale: (root.wanted && ready) ? 0 : 1
        Behavior on offsetScale {
            NumberAnimation {
                duration: root.wanted ? Appearance.animationCurves.drawerOpenDuration : Appearance.animationCurves.drawerCloseDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.wanted ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
            }
        }
        onOffsetScaleChanged: if (offsetScale >= 1 && !root.wanted) root.keepWindow = false
        Connections { // Closed before it ever slid out: nothing to animate
            target: root
            function onWantedChanged() {
                if (!root.wanted && win.offsetScale >= 1) Qt.callLater(() => { if (!root.wanted) root.keepWindow = false; });
            }
        }

        readonly property real drawerTop: -(fullHeight + hiddenExtra) * offsetScale
        readonly property real drawerY: Math.min(0, drawerTop)
        readonly property real drawerHeight: fullHeight + Math.max(0, drawerTop) // Overshoot stretches
        readonly property real visibleHeight: Math.max(0, drawerY + drawerHeight)

        color: "transparent"
        anchors { top: true; left: true }
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:barDrawer"
        WlrLayershell.layer: WlrLayer.Overlay
        implicitWidth: panelWidth + sideMargin * 2
        implicitHeight: Math.ceil(fullHeight * 1.12) // Headroom for the overshoot stretch
        margins {
            top: win.barBottom // Directly below the bar: overlapping its last row drew that row twice (a dark line); the bar skips its border here instead (BarJoin)
            left: {
                const centre = root.QsWindow?.mapFromItem(root.hoverTarget, root.hoverTarget.width / 2, 0).x ?? 0;
                const maxLeft = (win.screen?.width ?? 0) - win.implicitWidth;
                return Math.max(0, Math.min(centre - win.implicitWidth / 2, maxLeft));
            }
        }
        mask: Region { item: maskArea }

        Item {
            id: maskArea
            x: win.sideMargin
            width: win.panelWidth
            height: win.visibleHeight
        }

        Item {
            id: stage
            anchors.fill: parent
            clip: true

            DrawerReadiness { id: readiness } // The window is made for each opening: always active
            BarJoin { // Lets the bar skip its bottom border where the drawer joins it
                active: win.visibleHeight > 0
                joinX: win.margins.left + win.sideMargin
                joinWidth: win.panelWidth
            }

            DrawerBackground { // Shared with the launcher and the other drawers
                id: background
                anchors.fill: parent
                screenWidth: win.screen?.width ?? 0
                windowScreenX: win.margins.left
                drawerX: win.sideMargin
                drawerY: win.drawerY
                drawerWidth: win.panelWidth
                drawerHeight: win.drawerHeight
                drawerRadius: Math.min(win.bottomRadius, win.visibleHeight / 2)
                fallbackRadius: win.bottomRadius
            }

            Item {
                id: contentHolder
                x: win.sideMargin + win.padding
                y: win.drawerY + win.padding
                width: root.contentItem.implicitWidth
                height: root.contentItem.implicitHeight
                opacity: 1 - win.offsetScale
                children: [root.contentItem]
                transform: Matrix4x4 { // Wobble with the blob
                    matrix: background.deformMatrix
                }
            }
        }
    }
}
