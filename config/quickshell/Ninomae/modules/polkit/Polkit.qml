import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The password prompt (polkit): a drawer that drops out of the middle of the bar, like the app search, over a
 * light scrim on the focused screen. The card itself is PolkitContent. A wrong password shakes it.
 */
Scope {
    id: root
    readonly property bool open: PolkitService.active
    // Built when a request comes in, gone once the drawer has slid back after it
    property bool built: false
    onOpenChanged: if (open) built = true

    LazyLoader {
        active: root.built
        PanelWindow {
            id: win
            readonly property real sideMargin: 40 // Room for the gooey joins beside the drawer
            readonly property real panelWidth: 460
            readonly property real padding: 12
            readonly property real bottomRadius: 28
            readonly property real hiddenExtra: 60
            readonly property real fullHeight: content.implicitHeight + padding * 2
            readonly property real top: GlobalStates.drawerTopOn(screen) // Below the bar, or near the edge without one

            readonly property bool ready: readiness.ready // Slide only once the window is on screen
            // 0 = out, 1 = tucked under the bar
            property real offsetScale: (root.open && ready) ? 0 : 1
            Behavior on offsetScale {
                NumberAnimation {
                    duration: root.open ? Appearance.animationCurves.drawerOpenDuration : Appearance.animationCurves.drawerCloseDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.open ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
                }
            }
            readonly property real drawerTop: -(fullHeight + hiddenExtra) * offsetScale
            readonly property real drawerY: Math.min(0, drawerTop)
            readonly property real drawerHeight: fullHeight + Math.max(0, drawerTop) // Overshoot stretches
            readonly property real visibleHeight: Math.max(0, drawerY + drawerHeight)
            readonly property real drawerX: (width - panelWidth) / 2

            visible: root.open || offsetScale < 1 // Stay mapped while it slides back
            onVisibleChanged: if (!visible) root.built = false
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
            color: "transparent"
            WlrLayershell.namespace: "quickshell:polkit"
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }

            Rectangle { // Scrim: the rest of the screen dims a little, and clicks there do nothing
                anchors.fill: parent
                color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.55)
                opacity: 1 - win.offsetScale
                MouseArea { anchors.fill: parent }
            }

            DrawerReadiness {
                id: readiness
                active: win.visible
            }

            Item {
                id: stage
                anchors.fill: parent
                anchors.topMargin: GlobalStates.barAtBottom ? 0 : win.top
                anchors.bottomMargin: GlobalStates.barAtBottom ? win.top : 0
                clip: true
                transform: BarSideFlip { size: stage.height } // Bar along the bottom: rises from it

                BarJoin { // Lets the bar skip its bottom border where the drawer joins it
                    name: "polkit"
                    active: win.visible && win.visibleHeight > 0 && background.attached
                    joinX: win.drawerX
                    joinWidth: win.panelWidth
                }
                DrawerBackground { // Shared with the other drawers
                    id: background
                    anchors.fill: parent
                    active: win.visible
                    followBar: true // A card of its own over a fullscreen game
                    drawerX: win.drawerX
                    drawerY: win.drawerY
                    drawerWidth: win.panelWidth
                    drawerHeight: win.drawerHeight
                    drawerRadius: Math.min(win.bottomRadius, win.visibleHeight / 2)
                    fallbackRadius: win.bottomRadius
                }

                Item {
                    id: contentFrame
                    x: win.drawerX
                    y: win.drawerY
                    width: win.panelWidth
                    height: win.fullHeight
                    opacity: 1 - win.offsetScale
                    transform: [
                        BarSideFlip { size: win.fullHeight }, // Upright in a flipped stage
                        Matrix4x4 { matrix: background.deformMatrix }, // Wobble with the blob
                        Translate { id: shake }
                    ]
                    PolkitContent {
                        id: content
                        x: win.padding
                        y: win.padding
                        width: win.panelWidth - win.padding * 2
                    }
                }
            }

            Connections {
                target: PolkitService
                function onFailedChanged() {
                    if (PolkitService.failed) shakeAnim.restart();
                }
            }
            SequentialAnimation {
                id: shakeAnim
                NumberAnimation { target: shake; property: "x"; to: -14; duration: 50 }
                NumberAnimation { target: shake; property: "x"; to: 14; duration: 50 }
                NumberAnimation { target: shake; property: "x"; to: -7; duration: 40 }
                NumberAnimation { target: shake; property: "x"; to: 7; duration: 40 }
                NumberAnimation { target: shake; property: "x"; to: 0; duration: 30 }
            }
        }
    }
}
