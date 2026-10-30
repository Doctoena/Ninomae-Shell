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
    property real useShortenedForm: (Appearance.sizes.barHellaShortenScreenWidthThreshold >= screen?.width) ? 2 : (Appearance.sizes.barShortenScreenWidthThreshold >= screen?.width) ? 1 : 0
    readonly property int centerSideModuleWidth: (useShortenedForm == 2) ? Appearance.sizes.barCenterSideModuleWidthHellaShortened : (useShortenedForm == 1) ? Appearance.sizes.barCenterSideModuleWidthShortened : Appearance.sizes.barCenterSideModuleWidth
    component VerticalBarSeparator: Rectangle {
        Layout.topMargin: Appearance.sizes.baseBarHeight / 3
        Layout.bottomMargin: Appearance.sizes.baseBarHeight / 3
        Layout.fillHeight: true
        implicitWidth: 1
        color: Appearance.colors.colOutlineVariant
    }
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
            margins: Config.options.bar.cornerStyle === 1 ? (Appearance.sizes.hyprlandGapsOut) : 0 // idk why but +1 is needed
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
        // Skip the bottom border where a drawer (launcher, sidebar, popups…) is attached;
        // painting the bar's own fill over it, so the join has no line through it.
        Repeater {
            model: Object.values(GlobalStates.barJoins)
            delegate: Rectangle {
                required property var modelData
                readonly property real joinLeft: Math.max(barBackground.radius, modelData[0] - barBackground.x)
                readonly property real joinRight: Math.min(barBackground.width - barBackground.radius, modelData[0] + modelData[1] - barBackground.x)
                visible: barBackground.border.width > 0 && joinRight > joinLeft
                x: joinLeft
                y: barBackground.height - barBackground.border.width
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
    Row { // Middle section
        id: middleSection
        anchors {
            top: parent.top
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
        }
        spacing: 4
        VerticalBarSeparator {
            visible: Config.options?.bar.borderless
        }
        // === Clock (truly centred on the bar) ===
        MouseArea {
            id: centerClock
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: clockWidget.implicitWidth
            implicitHeight: clockWidget.implicitHeight
            width: implicitWidth
            height: implicitHeight
            onPressed: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
            ClockWidget {
                id: clockWidget
                anchors.centerIn: parent
            }
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
        // One shared pill behind the right cluster (media, tray, battery, status). The widgets
        // themselves are transparent segments with hover highlights; this spans from the leftmost
        // visible one to the status segment.
        Rectangle {
            id: rightGroupBackground
            readonly property real pad: 3
            readonly property real leftEdge: {
                const items = [mediaWidget, trayPill, batteryWidget, rightSidebarButton].filter(i => i.visible);
                return items.length ? Math.min(...items.map(i => i.x)) : rightSidebarButton.x;
            }
            x: leftEdge - pad
            width: rightSidebarButton.x + rightSidebarButton.width - leftEdge + pad * 2
            height: 36
            anchors.verticalCenter: parent.verticalCenter
            radius: 12 // Rounded rectangle; its segments are 10, their chips 8
            color: Appearance.m3colors.m3surfaceContainerHigh
            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }
        // Visual content
        RowLayout {
            id: rightSectionRowLayout
            anchors.fill: parent
            spacing: 0
            layoutDirection: Qt.RightToLeft
            // === Status indicators pill (rightmost) ===
            RippleButton {
                id: rightSidebarButton
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: Appearance.rounding.screenRounding + rightGroupBackground.pad
                Layout.fillWidth: false
                implicitWidth: indicatorsRowLayout.implicitWidth + 9 * 2
                implicitHeight: 30
                buttonRadius: 10
                // A segment of the shared right-side pill; lavender while the sidebar is open
                colBackground: "transparent"
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
            }
            // === Systray: arrow + revealed icons ===
            Rectangle {
                id: trayPill
                visible: root.useShortenedForm === 0
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 30
                implicitWidth: trayRow.implicitWidth + 4
                radius: 10
                color: sysTrayToggleMa.containsMouse ? Appearance.m3colors.m3surfaceContainerHighest : "transparent"
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on implicitWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                clip: true
                Row {
                    id: trayRow
                    anchors { left: parent.left; leftMargin: 2; verticalCenter: parent.verticalCenter }
                    spacing: 0
                    Revealer {
                        reveal: GlobalStates.sysTrayOpen
                        anchors.verticalCenter: parent.verticalCenter
                        SysTray {
                            invertSide: Config?.options.bar.bottom
                            showSeparator: false
                        }
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
            // === Media info ===
            Media {
                id: mediaWidget
                visible: root.useShortenedForm < 2 && MprisController.activePlayer !== null // No "No media" segment
                Layout.fillWidth: false
                Layout.alignment: Qt.AlignVCenter
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
