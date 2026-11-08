import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
Item { // Bar content region
    id: root
    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    readonly property int useShortenedForm: (Appearance.sizes.barHellaShortenScreenWidthThreshold >= screen?.width) ? 2 : (Appearance.sizes.barShortenScreenWidthThreshold >= screen?.width) ? 1 : 0
    // Something playing: the player shows in the middle of the bar (empty otherwise; the clock stays on the right)
    readonly property bool mediaShown: useShortenedForm < 2 && MprisController.activePlayer !== null
    // The right side's joined pieces, left to right as shown: round at the group's ends, slight between
    readonly property var rightPieces: [trayPill, batteryWidget, rightSidebarButton, rightClock].filter(i => i.visible)
    function pieceLeftRadius(item) { return rightPieces[0] === item ? Appearance.rounding.container : Appearance.rounding.joined; }
    function pieceRightRadius(item) { return rightPieces[rightPieces.length - 1] === item ? Appearance.rounding.container : Appearance.rounding.joined; }
    // Background shadow
    Loader {
        active: Config.options.bar.showBackground && Config.options.bar.cornerStyle === 1 && Config.options.bar.floatStyleShadow
        anchors.fill: barBackground
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
            target: barBackground
        }
    }
    // Background
    Rectangle {
        id: barBackground
        anchors {
            fill: parent
            margins: Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0
        }
        color: Config.options.bar.showBackground ? Appearance.colors.colLayer0 : "transparent"
        opacity: 0.92
        // Composite as one layer so the join fills below replace the border instead of
        // blending over it (with per-item opacity the border still showed through them).
        // Only while a join is drawn: the rest of the time it's just an offscreen texture per bar
        layer.enabled: border.width > 0 && Object.keys(GlobalStates.barJoins).length > 0
        radius: Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: Config.options.bar.cornerStyle === 1 ? 1 : 0
        border.color: Appearance.colors.colLayer0Border
        // Skip the border on the drawers' side (the bottom edge, or the top with the bar along the bottom) where a
        // drawer (launcher, sidebar, popups…) is attached, painting the bar's own fill over it, so the join has no line through it.
        Repeater {
            model: Object.values(GlobalStates.barJoins)
            delegate: Rectangle {
                required property var modelData
                readonly property real joinLeft: Math.max(barBackground.radius, modelData[0] - barBackground.x)
                readonly property real joinRight: Math.min(barBackground.width - barBackground.radius, modelData[0] + modelData[1] - barBackground.x)
                visible: barBackground.border.width > 0 && joinRight > joinLeft
                x: joinLeft
                y: GlobalStates.barAtBottom ? 0 : barBackground.height - barBackground.border.width
                width: joinRight - joinLeft
                height: barBackground.border.width
                color: barBackground.color
            }
        }
    }
    FocusedScrollMouseArea { // Left side | scroll to change brightness
        id: barLeftSideMouseArea
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
        }
        implicitWidth: leftSectionRowLayout.implicitWidth
        implicitHeight: Appearance.sizes.baseBarHeight
        onScrollDown: root.brightnessMonitor.setBrightness(root.brightnessMonitor.brightness - 0.05)
        onScrollUp: root.brightnessMonitor.setBrightness(root.brightnessMonitor.brightness + 0.05)
        onMovedAway: GlobalStates.osdBrightnessOpen = false
        // Visual content
        RowLayout {
            id: leftSectionRowLayout
            anchors.fill: parent
            spacing: 0
            Workspaces {
                id: workspacesWidget
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: Appearance.rounding.screenRounding
                Layout.fillHeight: true
                MouseArea {
                    // Right-click to toggle overview
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onPressed: event => {
                        if (event.button === Qt.RightButton) {
                            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
                        }
                    }
                }
            }
        }
    }
    Item { // Middle: what's playing, truly centred on the bar. It fades in growing into place, and out shrinking
        id: middleSection
        anchors.centerIn: parent
        implicitWidth: root.mediaShown ? mediaWidget.implicitWidth : 0
        implicitHeight: 36
        Media {
            id: mediaWidget
            anchors.centerIn: parent
            opacity: root.mediaShown ? 1 : 0
            scale: root.mediaShown ? 1 : 0.9
            visible: opacity > 0
            Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
            Behavior on scale { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
        }
    }
    FocusedScrollMouseArea { // Right side | scroll to change volume
        id: barRightSideMouseArea
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: middleSection.right
            right: parent.right
        }
        implicitWidth: rightSectionRowLayout.implicitWidth
        implicitHeight: Appearance.sizes.baseBarHeight
        onScrollDown: Audio.stepVolume(false)
        onScrollUp: Audio.stepVolume(true)
        onMovedAway: GlobalStates.osdVolumeOpen = false;
        onPressed: event => {
            if (event.button === Qt.LeftButton) {
                GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            }
        }
        // The tray, battery, status (opens the sidebar) and the clock: cards of their own joined into one group,
        // as the sidebar's blocks
        RowLayout {
            id: rightSectionRowLayout
            anchors.fill: parent
            anchors.rightMargin: Appearance.rounding.screenRounding
            spacing: 4
            layoutDirection: Qt.RightToLeft
            // === The clock (rightmost) ===
            ClockWidget {
                id: rightClock
                Layout.alignment: Qt.AlignVCenter
                radiusLeft: root.pieceLeftRadius(rightClock)
                radiusRight: root.pieceRightRadius(rightClock)
            }
            // === Status indicators ===
            RippleButton {
                id: rightSidebarButton
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: false
                implicitWidth: indicatorsRowLayout.implicitWidth + 11 * 2
                implicitHeight: 36 // As every card on the bar
                buttonRadiusLeft: root.pieceLeftRadius(rightSidebarButton)
                buttonRadiusRight: root.pieceRightRadius(rightSidebarButton)
                // Lavender while the sidebar is open
                colBackground: Appearance.m3colors.m3surfaceContainerHigh
                colBackgroundHover: Appearance.m3colors.m3surfaceContainerHighest
                colRipple: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.7)
                colBackgroundToggled: Appearance.colors.colPrimary
                colBackgroundToggledHover: Qt.lighter(Appearance.colors.colPrimary, 1.06)
                colRippleToggled: Appearance.colors.colPrimaryActive
                toggled: GlobalStates.sidebarRightOpen
                property color colText: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                readonly property bool online: Network.ethernet || Network.wifiStatus === "connected"
                Behavior on colText {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                onPressed: {
                    GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
                }
                RowLayout {
                    id: indicatorsRowLayout
                    anchors.centerIn: parent
                    property real realSpacing: 12
                    spacing: 0
                    Revealer {
                        reveal: Audio.sink?.audio?.muted ?? false
                        Layout.fillHeight: true
                        Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                        Behavior on Layout.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        MaterialSymbol {
                            text: "volume_off"
                            iconSize: Appearance.font.pixelSize.larger
                            color: rightSidebarButton.colText
                        }
                    }
                    Revealer {
                        reveal: Audio.source?.audio?.muted ?? false
                        Layout.fillHeight: true
                        Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                        Behavior on Layout.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        MaterialSymbol {
                            text: "mic_off"
                            iconSize: Appearance.font.pixelSize.larger
                            color: rightSidebarButton.colText
                        }
                    }
                    HyprlandXkbIndicator {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.rightMargin: indicatorsRowLayout.realSpacing
                        color: rightSidebarButton.colText
                    }
                    Revealer {
                        reveal: Notifications.silent || Notifications.unread > 0
                        Layout.fillHeight: true
                        Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                        implicitHeight: reveal ? notificationUnreadCount.implicitHeight : 0
                        implicitWidth: reveal ? notificationUnreadCount.implicitWidth : 0
                        Behavior on Layout.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        NotificationUnreadCount {
                            id: notificationUnreadCount
                            color: rightSidebarButton.colText
                            onAccent: rightSidebarButton.toggled
                        }
                    }
                    StatusChip {
                        visible: BluetoothStatus.available
                        Layout.rightMargin: 4
                        icon: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                        on: BluetoothStatus.connected
                        dim: !BluetoothStatus.enabled
                    }
                    StatusChip {
                        icon: Network.materialSymbol
                        on: rightSidebarButton.online
                        dim: !rightSidebarButton.online
                    }
                }
            }
            // === Battery ===
            BatteryIndicator {
                id: batteryWidget
                visible: Battery.available && Config.options.bar.indicators.battery.show
                Layout.alignment: Qt.AlignVCenter
                radiusLeft: root.pieceLeftRadius(batteryWidget)
                radiusRight: root.pieceRightRadius(batteryWidget)
            }
            // === Systray: arrow + revealed icons ===
            Rectangle {
                id: trayPill
                visible: root.useShortenedForm === 0
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 36 // As every card on the bar
                implicitWidth: trayRow.implicitWidth + 8
                topLeftRadius: root.pieceLeftRadius(trayPill)
                bottomLeftRadius: topLeftRadius
                topRightRadius: root.pieceRightRadius(trayPill)
                bottomRightRadius: topRightRadius
                color: sysTrayToggleMa.containsMouse ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerHigh
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on implicitWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                clip: true
                Row {
                    id: trayRow
                    anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                    spacing: 0
                    Revealer {
                        reveal: GlobalStates.sysTrayOpen
                        anchors.verticalCenter: parent.verticalCenter
                        SysTray {}
                    }
                    Item { // Expand/collapse arrow
                        width: 26; height: 26
                        anchors.verticalCenter: parent.verticalCenter
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: GlobalStates.sysTrayOpen ? "chevron_right" : "chevron_left"
                            iconSize: Appearance.font.pixelSize.larger
                            color: sysTrayToggleMa.containsMouse || GlobalStates.sysTrayOpen ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
                        }
                        MouseArea {
                            id: sysTrayToggleMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: GlobalStates.sysTrayOpen = !GlobalStates.sysTrayOpen
                        }
                    }
                }
            }
            // === Spacer: keeps the right-side pills against the right edge ===
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }

    // Wi-Fi / Bluetooth in the status segment: no background of their own, the icon turns accent while
    // connected (like the small sidebar tiles). While the sidebar is open the segment itself is accent
    component StatusChip: Item {
        id: chip
        property string icon
        property bool on: false
        property bool dim: false
        readonly property bool sidebarOpen: rightSidebarButton.toggled
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 24
        implicitHeight: 24
        MaterialSymbol {
            anchors.centerIn: parent
            text: chip.icon
            iconSize: Appearance.font.pixelSize.large
            fill: chip.on ? 1 : 0
            color: chip.sidebarOpen ? rightSidebarButton.colText
                : chip.on ? Appearance.colors.colPrimary
                : chip.dim ? Appearance.colors.colOnLayer1Inactive : Appearance.colors.colOnLayer0
        }
    }
}
