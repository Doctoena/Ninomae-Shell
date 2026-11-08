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
        readonly property real maxHeight: height - Appearance.sizes.hyprlandGapsOut * 2
        // Only as tall as what's in it, up to the screen's height: notifications coming in, edit mode or the
        // system panel opening grow it. No animation of its own: the parts inside already animate their
        // heights, and following them frame by frame keeps the drawer's edge on them (a second animation lags)
        readonly property real fullHeight: Math.min(maxHeight, sidebarContentLoader.item?.implicitHeight ?? maxHeight)

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
        margins.top: GlobalStates.barAtBottom ? 0 : barBottom // Directly below the bar: overlapping its last row drew that row twice (a dark line); the bar skips its border here instead (BarJoin)
        margins.bottom: GlobalStates.barAtBottom ? barBottom : 0 // Or right above it, along the bottom
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
            y: GlobalStates.barAtBottom ? sidebarRoot.height - height : 0
            width: sidebarRoot.panelWidth
            height: sidebarRoot.visibleHeight
        }

        Item {
            id: stage
            anchors.fill: parent
            clip: true
            transform: BarSideFlip { size: stage.height } // Bar along the bottom: rises from it

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
                sourceComponent: SidebarRightContent {}
                transform: [
                    BarSideFlip { size: sidebarRoot.fullHeight }, // Upright in a flipped stage
                    Matrix4x4 { matrix: background.deformMatrix } // Wobble with the blob
                ]
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
