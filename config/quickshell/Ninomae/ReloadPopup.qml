import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Reload result: a drawer that drops out of the middle of the bar with the gooey blob animation,
// the same pieces as onScreenDisplay/OnScreenDisplay.qml. "Reloaded" is a small pill that goes
// away by itself; "Reload failed" is a card with the error, Copy and Close, that stays while hovered.
Scope {
    id: root
    property bool open: false
    property bool failed: false
    property string errorString: ""

    readonly property color accent: failed ? Appearance.colors.colError : Appearance.colors.colPrimary
    readonly property int lifetime: failed ? 10000 : 1800

    function show(isFailure, error) {
        failed = isFailure;
        errorString = (error ?? "").trim();
        open = true;
        countdown.restart();
    }

    Connections {
        target: Quickshell
        function onReloadCompleted() { root.show(false, ""); }
        function onReloadFailed(error: string) { root.show(true, error); }
    }

    // 1 → 0 over the lifetime; paused while the pointer is on the drawer
    property real remaining: 1
    NumberAnimation {
        id: countdown
        target: root; property: "remaining"
        from: 1; to: 0
        duration: root.lifetime
        paused: running && drawer.hovered
        onFinished: root.open = false
    }

    PanelWindow {
        id: drawer
        readonly property real sideMargin: 40 // Room for the gooey joins beside the drawer
        readonly property real padding: root.failed ? 16 : 10
        readonly property real bottomRadius: root.failed ? Appearance.rounding.large : 22
        readonly property real hiddenExtra: 60
        readonly property real barBottom: Appearance.sizes.barHeight - (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
        readonly property real panelWidth: content.implicitWidth + padding * 2
        readonly property real fullHeight: content.implicitHeight + padding * 2 + (root.failed ? 6 : 0) // + countdown line
        readonly property bool hovered: hoverArea.containsMouse

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

        visible: root.open || offsetScale < 1 // Stay mapped while retracting
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
        color: "transparent"
        WlrLayershell.namespace: "quickshell:reloadPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        anchors.top: true // Horizontally centred
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        margins.top: barBottom // Directly below the bar, which skips its border here (BarJoin)
        implicitWidth: panelWidth + sideMargin * 2
        implicitHeight: Math.ceil(fullHeight * 1.12) // Headroom for the overshoot stretch
        mask: Region { item: maskArea }

        Item {
            id: maskArea
            x: drawer.sideMargin
            width: drawer.panelWidth
            height: drawer.visibleHeight
            MouseArea { // Hover pauses the countdown; a click anywhere else on the drawer dismisses it
                id: hoverArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.open = false
            }
        }

        Item {
            id: stage
            anchors.fill: parent
            clip: true

            DrawerReadiness {
                id: readiness
                active: drawer.visible
            }
            BarJoin { // Lets the bar skip its bottom border where the drawer joins it
                name: "reloadPopup"
                active: drawer.visible && drawer.visibleHeight > 0
                joinX: ((drawer.screen?.width ?? 0) - drawer.implicitWidth) / 2 + drawer.sideMargin
                joinWidth: drawer.panelWidth
            }

            DrawerBackground { // Shared with the other drawers
                id: background
                anchors.fill: parent
                active: drawer.visible
                drawerX: drawer.sideMargin
                drawerY: drawer.drawerY
                drawerWidth: drawer.panelWidth
                drawerHeight: drawer.drawerHeight
                drawerRadius: Math.min(drawer.bottomRadius, drawer.visibleHeight / 2)
                fallbackRadius: drawer.bottomRadius
            }

            Item {
                id: contentFrame
                x: drawer.sideMargin
                y: drawer.drawerY
                width: drawer.panelWidth
                height: drawer.fullHeight
                opacity: 1 - drawer.offsetScale
                transform: Matrix4x4 { // Wobble with the blob
                    matrix: background.deformMatrix
                }

                ColumnLayout {
                    id: content
                    x: drawer.padding
                    y: drawer.padding
                    spacing: 12

                    // ── Header: status badge, title, and (on failure) the actions ──
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            implicitWidth: 30; implicitHeight: 30; radius: Appearance.rounding.segment
                            color: ColorUtils.transparentize(root.accent, 0.82)
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: root.failed ? "error" : "check"
                                iconSize: 18
                                fill: 1
                                color: root.accent
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: root.failed ? Translation.tr("Reload failed") : Translation.tr("Shell reloaded")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer0
                            }
                            StyledText {
                                visible: root.failed
                                text: Translation.tr("Still running the last working config")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                        }
                        Item { // Room for the buttons pinned in the corner
                            visible: root.failed
                            Layout.preferredWidth: actions.width + 16
                        }
                    }

                    // ── The error itself ──
                    Rectangle {
                        visible: root.failed && root.errorString !== ""
                        Layout.fillWidth: true
                        Layout.maximumWidth: 640
                        implicitWidth: Math.min(errorText.implicitWidth + 28, 640)
                        implicitHeight: errorText.implicitHeight + 20
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1
                        Rectangle { // Error accent down the left edge
                            x: 0; y: 10
                            width: 3; height: parent.height - 20
                            radius: 1.5
                            color: Appearance.colors.colError
                        }
                        StyledText {
                            id: errorText
                            x: 16; y: 10
                            width: Math.min(implicitWidth, 640 - 28)
                            text: root.errorString
                            wrapMode: Text.WrapAnywhere // Paths and type names have no spaces to break at
                            maximumLineCount: 12
                            elide: Text.ElideRight
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }

                Row { // Copy / Dismiss, pinned to the card's top-right corner
                    id: actions
                    visible: root.failed
                    anchors { top: parent.top; topMargin: drawer.padding - 1; right: parent.right; rightMargin: drawer.padding - 4 }
                    spacing: 4
                    DrawerIconButton {
                        id: copyButton
                        iconName: copied ? "check" : "content_copy"
                        tooltipText: Translation.tr("Copy error")
                        property bool copied: false
                        onClicked: {
                            Quickshell.clipboardText = root.errorString;
                            copied = true;
                            copiedReset.restart();
                        }
                        Timer { id: copiedReset; interval: 1500; onTriggered: copyButton.copied = false }
                    }
                    DrawerIconButton {
                        iconName: "close"
                        tooltipText: Translation.tr("Dismiss")
                        onClicked: root.open = false
                    }
                }

                // Countdown to auto-dismiss (paused while hovered)
                Rectangle {
                    visible: root.failed
                    anchors { bottom: parent.bottom; bottomMargin: 8; horizontalCenter: parent.horizontalCenter }
                    width: (parent.width - drawer.bottomRadius * 2) * root.remaining
                    height: 3
                    radius: 1.5
                    color: root.accent
                    opacity: drawer.hovered ? 0.35 : 0.7
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
            }
        }
    }

    component DrawerIconButton: RippleButton {
        id: iconButton
        property string iconName
        property string tooltipText
        implicitWidth: 32; implicitHeight: 32
        buttonRadius: 16
        padding: 0
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active
        contentItem: Item {
            MaterialSymbol {
                anchors.centerIn: parent
                text: iconButton.iconName
                iconSize: 18
                color: Appearance.colors.colOnLayer0
            }
        }
        StyledToolTip { text: iconButton.tooltipText }
    }
}
