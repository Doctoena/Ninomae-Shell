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
    // Background
    Rectangle {
        id: barBackground
        anchors {
            fill: parent
            margins: Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0
        }
        color: Config.options.bar.showBackground ? Appearance.colors.colLayer0 : "transparent"
        opacity: Appearance.colors.glassOn ? 0.8 : 0.92 // Glass: over Hyprland's blur (GlassBlur)
        radius: Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: Config.options.bar.cornerStyle === 1 ? 1 : 0
        // Glass: no border; the edge light below instead (as the launcher's GlassEdge): none along the bottom, where the
        // drawers hang and carry the light on round themselves (DrawerBackground)
        border.color: "transparent"
        Item { // Glass: the light round the top and down the rounded ends to halfway (a rim clipped to the top half)
            visible: barBackground.border.width > 0 && !GlobalStates.barAtBottom
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: parent.height / 2
            clip: true
            Rectangle {
                width: parent.width
                height: barBackground.height
                radius: barBackground.radius
                color: "transparent"
                border { width: 1; color: Qt.rgba(1, 1, 1, 0.12) }
            }
        }
        Rectangle { // Glass: the light along the top, brightest in the middle (not with the bar along the bottom: the
            // drawers join that edge)
            visible: barBackground.border.width > 0 && !GlobalStates.barAtBottom
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 60; rightMargin: 60 }
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.35) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }
    LitCapsule { // The workspaces' (K1): their first and last cells concentric with its ends
        x: barLeftSideMouseArea.x + workspacesWidget.x
        width: workspacesWidget.width
    }
    // A lit capsule (W3, the player's first): 30 px, round ends, its colour strongest at the left end and fading out by
    // its middle, a fine rim of it. The player's in its cover's colour; the workspaces', status' and clock's in the accent
    component LitCapsule: Rectangle {
        id: capsule
        property color colour: Appearance.colors.colPrimary
        // How much of the colour: the accent is more vivid than a cover's colour, so the accent ones are at 0.75, as soft
        // as the player's glow at 1
        property real strength: 0.75
        visible: Config.options.bar.showBackground && width > 0 && opacity > 0
        anchors.verticalCenter: barBackground.verticalCenter
        height: 30
        radius: height / 2
        color: "transparent"
        border { width: 1; color: ColorUtils.transparentize(capsule.colour, 1 - 0.25 * capsule.strength) }
        Rectangle {
            anchors { fill: parent; margins: 1 }
            radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: ColorUtils.transparentize(capsule.colour, 1 - 0.28 * capsule.strength) }
                GradientStop { position: 0.55; color: ColorUtils.transparentize(capsule.colour, 1 - 0.08 * capsule.strength) }
                GradientStop { position: 1; color: ColorUtils.transparentize(capsule.colour, 1 - 0.05 * capsule.strength) }
            }
        }
    }
    LitCapsule { // The player's, fading and growing in and out with it: its round left end is the cover's ring
        anchors.horizontalCenter: middleSection.horizontalCenter
        width: middleSection.implicitWidth
        colour: mediaWidget.accentColour
        strength: 1
        opacity: mediaWidget.opacity
        scale: mediaWidget.scale
    }
    // The right side (R3): the tray, the battery and the status button in one capsule, the clock in its own
    readonly property real rightX: barRightSideMouseArea.x + rightSectionRowLayout.x
    LitCapsule {
        readonly property Item first: trayPill.visible ? trayPill : batteryWidget.visible ? batteryWidget : rightSidebarButton
        x: root.rightX + first.x
        width: rightSidebarButton.x + rightSidebarButton.width + 2 - first.x
    }
    LitCapsule {
        x: root.rightX + rightClock.x
        width: rightClock.width
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
        // The tray, battery, status (opens the sidebar) in one capsule and the clock in its own (R3), the accent line
        // under the one pointed at (HoverLine)
        RowLayout {
            id: rightSectionRowLayout
            anchors.fill: parent
            anchors.rightMargin: Appearance.rounding.screenRounding
            spacing: 0
            layoutDirection: Qt.RightToLeft
            // === The clock (rightmost) ===
            ClockWidget {
                id: rightClock
                Layout.alignment: Qt.AlignVCenter
            }
            Item { implicitWidth: 6 } // Between the clock's capsule and the status one
            // === Status indicators ===
            RippleButton {
                id: rightSidebarButton
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: false
                implicitWidth: indicatorsRowLayout.implicitWidth + 6 * 2 // Evened out with the battery's and the tray's
                // Inside the status capsule (30 px): its block while the sidebar is open sits 2 px in from the
                // capsule's edge (1 px let half-pixel rounding reach the rim), concentric with its round end
                implicitHeight: 26
                buttonRadius: 13
                // While the sidebar is open (S4): the workspaces' soft glass block, the icons in the accent and a
                // short accent line under them
                colBackground: "transparent"
                colBackgroundHover: "transparent"
                colRipple: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.7)
                colBackgroundToggled: Qt.rgba(1, 1, 1, 0.08)
                colBackgroundToggledHover: Qt.rgba(1, 1, 1, 0.12)
                colRippleToggled: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.7)
                toggled: GlobalStates.sidebarRightOpen
                property color colText: toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                readonly property bool online: Network.ethernet || Network.wifiStatus === "connected"
                Behavior on colText {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                onPressed: {
                    GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
                }
                HoverLine { shown: rightSidebarButton.hovered && !rightSidebarButton.toggled; capsule: true }
                Rectangle { // Open: the short accent line under the icons
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 3 }
                    width: rightSidebarButton.toggled ? 16 : 0
                    height: 2
                    radius: 1
                    color: Appearance.colors.colPrimary
                    opacity: rightSidebarButton.toggled ? 1 : 0
                    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
                RowLayout {
                    id: indicatorsRowLayout
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: rightSidebarButton.toggled ? -1 : 0 // Room for the line
                    property real realSpacing: 10
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
                implicitHeight: 36 // As every part of the bar
                implicitWidth: trayRow.implicitWidth + 3 // The arrow's own box pads its right
                color: "transparent"
                HoverLine { shown: sysTrayToggleMa.containsMouse; capsule: true }
                Behavior on implicitWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                clip: true
                Row {
                    id: trayRow
                    anchors { left: parent.left; leftMargin: 3; verticalCenter: parent.verticalCenter }
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
    // connected (like the small sidebar tiles), and every icon is accent while the sidebar is open
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
