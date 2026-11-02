import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
Scope {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    PanelWindow {
        id: sidebarRoot
        function hide() {
            GlobalStates.sidebarRightOpen = false
        }
        // ── Drawer that drops out of the bar (same animation as the launcher, overview/SearchWidget.qml) ──
        readonly property real sideMargin: 40 // Room for the gooey joins either side
        readonly property real hiddenExtra: 60
        readonly property real bottomRadius: Appearance.rounding.screenRounding
        readonly property real barBottom: GlobalStates.drawerTopOn(screen) // Below the bar, or near the top without one
        readonly property real panelWidth: sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
        readonly property real fullHeight: height - Appearance.sizes.hyprlandGapsOut * 2

        readonly property bool drawerReady: readiness.ready // Slide only once the window is on screen

        // 0 = out, 1 = tucked under the bar
        property real offsetScale: (GlobalStates.sidebarRightOpen && drawerReady) ? 0 : 1
        Behavior on offsetScale {
            NumberAnimation {
                duration: GlobalStates.sidebarRightOpen ? Appearance.animationCurves.drawerOpenDuration + Appearance.animationCurves.drawerLargeExtra : Appearance.animationCurves.drawerCloseDuration + Appearance.animationCurves.drawerLargeExtra
                easing.type: Easing.BezierSpline
                easing.bezierCurve: GlobalStates.sidebarRightOpen ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
            }
        }
        readonly property real drawerTop: -(fullHeight + hiddenExtra) * offsetScale
        readonly property real drawerY: Math.min(0, drawerTop)
        readonly property real drawerHeight: fullHeight + Math.max(0, drawerTop) // Overshoot stretches
        readonly property real visibleHeight: Math.max(0, drawerY + drawerHeight)

        visible: GlobalStates.sidebarRightOpen || offsetScale < 1 // Stay mapped while sliding back in
        exclusionMode: ExclusionMode.Ignore // Cover the bar's zone so the drawer can attach to it
        exclusiveZone: 0
        implicitWidth: panelWidth + sideMargin * 2
        WlrLayershell.namespace: "quickshell:sidebarRight"
        WlrLayershell.layer: WlrLayer.Overlay // Above the bar, so the drawer covers its border where they join
        // Hyprland 0.49: Focus is always exclusive and setting this breaks mouse focus grab
        // WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "transparent"
        anchors {
            top: true
            right: true
            bottom: true
        }
        margins.top: barBottom // Directly below the bar: overlapping its last row drew that row twice (a dark line); the bar skips its border here instead (BarJoin)
        mask: Region { item: maskArea }
        HyprlandFocusGrab {
            id: grab
            windows: [ sidebarRoot ]
            active: GlobalStates.sidebarRightOpen
            onCleared: () => {
                if (!active) sidebarRoot.hide()
            }
        }

        Item {
            id: maskArea
            x: sidebarRoot.sideMargin
            width: sidebarRoot.panelWidth
            height: sidebarRoot.visibleHeight
        }

        Item {
            id: stage
            anchors.fill: parent
            clip: true

            DrawerReadiness {
                id: readiness
                active: sidebarRoot.visible
            }
            BarJoin { // Lets the bar skip its bottom border where the drawer joins it
                name: "sidebarRight"
                active: sidebarRoot.visible && sidebarRoot.visibleHeight > 0
                joinX: (sidebarRoot.screen?.width ?? 0) - sidebarRoot.implicitWidth + sidebarRoot.sideMargin
                joinWidth: sidebarRoot.panelWidth
            }

            DrawerBackground { // Shared with the launcher and the other drawers
                followBar: true // A card while there's no bar (a fullscreen game)
                id: background
                anchors.fill: parent
                active: sidebarRoot.visible
                screenWidth: sidebarRoot.screen?.width ?? 0
                windowScreenX: (sidebarRoot.screen?.width ?? 0) - sidebarRoot.implicitWidth
                drawerX: sidebarRoot.sideMargin
                drawerY: sidebarRoot.drawerY
                drawerWidth: sidebarRoot.panelWidth
                drawerHeight: sidebarRoot.drawerHeight
                drawerRadius: Math.min(sidebarRoot.bottomRadius, sidebarRoot.visibleHeight / 2)
                fallbackRadius: sidebarRoot.bottomRadius
            }

            Loader {
                id: sidebarContentLoader
                active: GlobalStates.sidebarRightOpen || sidebarRoot.visible || Config?.options.sidebar.keepRightSidebarLoaded
                x: sidebarRoot.sideMargin
                y: sidebarRoot.drawerY
                width: sidebarRoot.panelWidth
                height: sidebarRoot.fullHeight
                opacity: 1 - sidebarRoot.offsetScale
                focus: GlobalStates.sidebarRightOpen
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        sidebarRoot.hide();
                    }
                }
                sourceComponent: SidebarRightContent {
                    drawnByDrawer: true // The blob drawer draws the background
                }
                transform: Matrix4x4 { // Wobble with the blob
                    matrix: background.deformMatrix
                }
            }
        }
    }
    IpcHandler {
        target: "sidebarRight"
        function toggle(): void {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }
        function close(): void {
            GlobalStates.sidebarRightOpen = false;
        }
        function open(): void {
            GlobalStates.sidebarRightOpen = true;
        }
    }
    GlobalShortcut {
        name: "sidebarRightToggle"
        description: "Toggles right sidebar on press"
        onPressed: {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }
    }
    GlobalShortcut {
        name: "sidebarRightOpen"
        description: "Opens right sidebar on press"
        onPressed: {
            GlobalStates.sidebarRightOpen = true;
        }
    }
    GlobalShortcut {
        name: "sidebarRightClose"
        description: "Closes right sidebar on press"
        onPressed: {
            GlobalStates.sidebarRightOpen = false;
        }
    }
}
