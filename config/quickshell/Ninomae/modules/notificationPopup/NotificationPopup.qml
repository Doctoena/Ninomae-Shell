import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Notification popups in a drawer that grows out of the bar's right end with the gooey blob
 * animation (same pieces as the sidebar/media drawers). It resizes to fit the popups, and
 * retracts into the bar when the last one is gone.
 */
Scope {
    id: notificationPopup
    PanelWindow {
        id: root
        readonly property real sideMargin: 40 // Room for the gooey joins either side
        readonly property real padding: 10
        readonly property real barBottom: Appearance.sizes.barHeight - (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
        // No bar to hang from (a fullscreen window covers it, or it's toggled off): a free-standing card instead
        readonly property bool fullscreenActive: screen
            ? (Hyprland.monitorFor(screen)?.activeWorkspace?.toplevels?.values ?? []).some(w => w.wayland?.fullscreen)
            : false
        readonly property bool attached: GlobalStates.barOpen && !fullscreenActive
        readonly property real topEdge: attached ? barBottom : 10
        readonly property real panelWidth: Appearance.sizes.notificationPopupWidth
        readonly property bool hasPopups: Notifications.popupList.length > 0 && !GlobalStates.screenLocked

        // Height the drawer wants: the cards plus padding, capped to the screen
        readonly property real targetHeight: hasPopups && drawerReady
            ? Math.min(listview.contentHeight + listview.topMargin + padding * 2, (screen?.height ?? 1080) - topEdge - 20)
            : 0
        property real drawerHeight: 0
        Binding on drawerHeight { value: root.targetHeight }
        Behavior on drawerHeight {
            NumberAnimation {
                duration: root.targetHeight > root.drawerHeight ? Appearance.animationCurves.drawerOpenDuration : Appearance.animationCurves.drawerCloseDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.targetHeight > root.drawerHeight ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
            }
        }

        readonly property bool drawerReady: readiness.ready // Grow out only once the window is on screen

        visible: hasPopups || drawerHeight > 0.5 // Stay mapped while retracting
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
        WlrLayershell.namespace: "quickshell:notificationPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore // Cover the bar's zone so the drawer can attach to it
        exclusiveZone: 0
        anchors {
            top: true
            right: true
            bottom: true
        }
        margins.top: topEdge
        implicitWidth: panelWidth + sideMargin * 2
        color: "transparent"
        mask: Region { item: maskArea }

        Item {
            id: maskArea
            x: root.sideMargin
            width: root.panelWidth
            height: root.drawerHeight
        }

        Item {
            id: stage
            anchors.fill: parent
            clip: true

            DrawerReadiness {
                id: readiness
                active: root.visible
            }
            BarJoin { // Lets the bar skip its bottom border where the drawer joins it
                name: "notificationPopup"
                active: root.visible && root.drawerHeight > 0 && root.attached
                joinX: (root.screen?.width ?? 0) - root.implicitWidth + root.sideMargin
                joinWidth: root.panelWidth
            }

            DrawerBackground {
                anchors.fill: parent
                active: root.visible
                // Hidden, not unloaded, while it's a card: a freshly loaded blob didn't draw its join to the
                // bar until the drawer next changed size, so switching workspaces left it detached
                visible: root.attached
                screenWidth: root.screen?.width ?? 0
                windowScreenX: (root.screen?.width ?? 0) - root.implicitWidth
                drawerX: root.sideMargin
                drawerY: 0
                drawerWidth: root.panelWidth
                drawerHeight: root.drawerHeight
                drawerRadius: Math.min(Appearance.rounding.large + 4, root.drawerHeight / 2)
                fallbackRadius: Appearance.rounding.large
            }

            Rectangle { // Free-standing card while there's no bar to join
                visible: !root.attached
                x: root.sideMargin
                width: root.panelWidth
                height: root.drawerHeight
                radius: Math.min(Appearance.rounding.large + 4, root.drawerHeight / 2)
                color: Appearance.colors.colLayer0
                opacity: 0.92
            }

            Item { // Cards, revealed as the drawer grows
                x: root.sideMargin + root.padding
                y: root.padding
                width: root.panelWidth - root.padding * 2
                height: Math.max(0, root.drawerHeight - root.padding * 2)
                clip: true
                opacity: Math.min(1, root.drawerHeight / 60)
                NotificationListView {
                    id: listview
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: (root.screen?.height ?? 1080) - root.topEdge - 40
                    popup: true
                }
            }
        }
    }
}
