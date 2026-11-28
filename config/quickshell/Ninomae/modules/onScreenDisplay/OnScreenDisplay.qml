import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
Scope {
    id: root
    property string protectionMessage: ""
    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)
    property string currentIndicator: "volume"
    // The one on screen (its own value, not bound to currentIndicator, so it can lag behind). While the drawer is
    // out, a new one swaps in with an animation: the old fades and slides up, the new one comes up after it. Another
    // swap mid-way restarts it from wherever it got to. With the drawer in, at once
    property string shownIndicator: "volume"
    onCurrentIndicatorChanged: {
        if (osdRoot.visible && osdRoot.offsetScale < 1) {
            if (currentIndicator !== shownIndicator) swapAnim.restart();
        } else {
            swapAnim.stop();
            osdIndicatorLoader.opacity = 1;
            swapShift.y = 0;
            shownIndicator = currentIndicator;
        }
    }
    property var indicators: [
        {
            id: "volume",
            sourceUrl: "indicators/VolumeIndicator.qml"
        },
        {
            id: "brightness",
            sourceUrl: "indicators/BrightnessIndicator.qml"
        },
        {
            id: "capslock",
            sourceUrl: "indicators/CapsLockIndicator.qml"
        },
    ]
    function triggerOsd() {
        GlobalStates.osdVolumeOpen = true;
        osdTimeout.restart();
    }
    Timer {
        id: osdTimeout
        interval: Config.options.osd.timeout
        repeat: false
        running: false
        onTriggered: {
            GlobalStates.osdVolumeOpen = false;
            root.protectionMessage = "";
        }
    }
    Connections {
        target: Brightness
        function onBrightnessChanged() {
            root.protectionMessage = "";
            root.currentIndicator = "brightness";
            root.triggerOsd();
        }
    }
    Connections {
        // Listen to volume changes
        target: Audio.sink?.audio ?? null
        function onVolumeChanged() {
            if (!Audio.ready)
                return;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
        function onMutedChanged() {
            if (!Audio.ready)
                return;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
    }
    Connections {
        // Listen to protection triggers
        target: Audio
        function onSinkProtectionTriggered(reason) {
            root.protectionMessage = reason;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
    }
    Connections {
        // Listen to caps lock changes
        target: CapsLock
        function onCapsLockChanged() {
            root.protectionMessage = "";
            root.currentIndicator = "capslock";
            root.triggerOsd();
        }
    }
    // Drawer that slides out of the middle of the bar with the gooey blob animation,
    // the same pieces as bar/BarDrawerPopup.qml. Assumes a bar at the top.
    PanelWindow {
        id: osdRoot
        readonly property real sideMargin: 40 // Room for the gooey joins beside the drawer
        readonly property real padding: 14
        readonly property real bottomRadius: 26
        readonly property real hiddenExtra: 60
        readonly property real barBottom: GlobalStates.drawerTopOn(screen) // Below the bar, or near the top without one
        readonly property real panelWidth: contentColumn.implicitWidth + padding * 2
        readonly property real fullHeight: contentColumn.implicitHeight + padding * 2

        readonly property bool ready: readiness.ready // Slide only once the window is on screen

        // 0 = out, 1 = tucked under the bar
        property real offsetScale: (GlobalStates.osdVolumeOpen && ready) ? 0 : 1
        Behavior on offsetScale {
            NumberAnimation {
                duration: GlobalStates.osdVolumeOpen ? Appearance.animationCurves.drawerOpenDuration : Appearance.animationCurves.drawerCloseDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: GlobalStates.osdVolumeOpen ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
            }
        }
        readonly property real drawerTop: -(fullHeight + hiddenExtra) * offsetScale
        readonly property real drawerY: Math.min(0, drawerTop)
        readonly property real drawerHeight: fullHeight + Math.max(0, drawerTop) // Overshoot stretches
        readonly property real visibleHeight: Math.max(0, drawerY + drawerHeight)

        visible: GlobalStates.osdVolumeOpen || offsetScale < 1 // Stay mapped while retracting
        screen: root.focusedScreen ?? null
        color: "transparent"
        WlrLayershell.namespace: "quickshell:onScreenDisplay"
        WlrLayershell.layer: WlrLayer.Overlay
        anchors.top: !GlobalStates.barAtBottom // Horizontally centred
        anchors.bottom: GlobalStates.barAtBottom
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        margins.bottom: GlobalStates.barAtBottom ? barBottom : 0 // Or right above it, along the bottom
        margins.top: GlobalStates.barAtBottom ? 0 : barBottom // Directly below the bar, which skips its border here (BarJoin)
        implicitWidth: panelWidth + sideMargin * 2
        implicitHeight: Math.ceil(fullHeight * 1.12) // Headroom for the overshoot stretch
        mask: Region { item: maskArea }

        Item {
            id: maskArea
            x: osdRoot.sideMargin
            y: GlobalStates.barAtBottom ? osdRoot.height - height : 0
            width: osdRoot.panelWidth
            height: osdRoot.visibleHeight
            MouseArea { // Get out of the way when the pointer goes there
                anchors.fill: parent
                hoverEnabled: true
                onEntered: GlobalStates.osdVolumeOpen = false
            }
        }

        Item {
            id: stage
            anchors.fill: parent
            clip: true
            transform: BarSideFlip { size: stage.height } // Bar along the bottom: rises from it

            DrawerReadiness {
                id: readiness
                active: osdRoot.visible
            }
            BarJoin { // Lets the bar skip its bottom border where the drawer joins it
                name: "onScreenDisplay"
                active: osdRoot.visible && osdRoot.visibleHeight > 0
                joinX: ((osdRoot.screen?.width ?? 0) - osdRoot.implicitWidth) / 2 + osdRoot.sideMargin
                joinWidth: osdRoot.panelWidth
            }

            DrawerBackground {
                followBar: true // A card while there's no bar (a fullscreen game)
                id: background
                anchors.fill: parent
                active: osdRoot.visible
                drawerX: osdRoot.sideMargin
                drawerY: osdRoot.drawerY
                drawerWidth: osdRoot.panelWidth
                drawerHeight: osdRoot.drawerHeight
                drawerRadius: Math.min(osdRoot.bottomRadius, osdRoot.visibleHeight / 2)
                fallbackRadius: osdRoot.bottomRadius
            }

            Column {
                id: contentColumn
                x: osdRoot.sideMargin + osdRoot.padding
                y: osdRoot.drawerY + osdRoot.padding
                spacing: 10
                opacity: 1 - osdRoot.offsetScale
                transform: [
                    BarSideFlip { size: contentColumn.height }, // Upright in a flipped stage
                    Matrix4x4 { matrix: background.deformMatrix } // Wobble with the blob
                ]
                Loader {
                    id: osdIndicatorLoader
                    active: osdRoot.visible
                    source: root.indicators.find(i => i.id === root.shownIndicator)?.sourceUrl
                    transform: Translate { id: swapShift }
                    SequentialAnimation {
                        id: swapAnim
                        ParallelAnimation {
                            NumberAnimation { target: osdIndicatorLoader; property: "opacity"; to: 0; duration: 90; easing.type: Easing.InQuad }
                            NumberAnimation { target: swapShift; property: "y"; to: -8; duration: 90; easing.type: Easing.InQuad }
                        }
                        ScriptAction { script: root.shownIndicator = root.currentIndicator }
                        PropertyAction { target: swapShift; property: "y"; value: 8 }
                        ParallelAnimation {
                            NumberAnimation { target: osdIndicatorLoader; property: "opacity"; to: 1; duration: 160; easing.type: Easing.OutCubic }
                            NumberAnimation { target: swapShift; property: "y"; to: 0; duration: 160; easing.type: Easing.OutCubic }
                        }
                    }
                }
                Rectangle { // Volume protection warning
                    visible: root.protectionMessage !== ""
                    width: osdIndicatorLoader.width
                    height: protectionRow.implicitHeight + 16
                    radius: 12
                    color: ColorUtils.transparentize(Appearance.colors.colError, 0.85)
                    Row {
                        id: protectionRow
                        anchors.centerIn: parent
                        width: parent.width - 24
                        spacing: 8
                        MaterialSymbol {
                            id: protectionIcon
                            anchors.verticalCenter: parent.verticalCenter
                            text: "dangerous"
                            iconSize: 20
                            color: Appearance.colors.colError
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - protectionIcon.width - parent.spacing
                            color: Appearance.colors.colError
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            wrapMode: Text.Wrap
                            text: root.protectionMessage
                        }
                    }
                }
            }
        }
    }
    IpcHandler {
        target: "osdVolume"
        function trigger() {
            root.triggerOsd();
        }
        function hide() {
            GlobalStates.osdVolumeOpen = false;
        }
        function toggle() {
            GlobalStates.osdVolumeOpen = !GlobalStates.osdVolumeOpen;
        }
    }
    GlobalShortcut {
        name: "osdVolumeTrigger"
        description: "Triggers volume OSD on press"
        onPressed: {
            root.triggerOsd();
        }
    }
    GlobalShortcut {
        name: "osdVolumeHide"
        description: "Hides volume OSD on press"
        onPressed: {
            GlobalStates.osdVolumeOpen = false;
        }
    }
}
