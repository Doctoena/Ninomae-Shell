import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import qs.modules.sidebarRight.quickToggles
import qs.modules.sidebarRight.quickToggles.classicStyle
import qs.modules.sidebarRight.bluetoothDevices
import qs.modules.sidebarRight.nightLight
import qs.modules.sidebarRight.resourceMonitor
import qs.modules.sidebarRight.volumeMixer
import qs.modules.sidebarRight.wifiNetworks
Item {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    // When the blob drawer in SidebarRight.qml draws the background, skip our own card
    property bool drawnByDrawer: false
    property int sidebarPadding: 10
    property string openSettingsScript: Quickshell.shellPath("scripts/open-settings.sh")
    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false
    property bool editMode: false
    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                root.showWifiDialog = false;
                root.showBluetoothDialog = false;
                root.showAudioOutputDialog = false;
                root.showAudioInputDialog = false;
            }
        }
    }
    implicitHeight: sidebarRightBackground.implicitHeight
    implicitWidth: sidebarRightBackground.implicitWidth
    StyledRectangularShadow {
        visible: !root.drawnByDrawer
        target: sidebarRightBackground
    }
    Rectangle {
        id: sidebarRightBackground
        anchors.fill: parent
        implicitHeight: parent.height - Appearance.sizes.hyprlandGapsOut * 2
        implicitWidth: sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2
        color: root.drawnByDrawer ? "transparent" : Appearance.colors.colLayer0
        opacity: root.drawnByDrawer ? 1 : 0.92
        border.width: root.drawnByDrawer ? 0 : 1
        border.color: Appearance.colors.colLayer0Border
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
        ColumnLayout {
            id: mainColumn
            anchors.fill: parent
            anchors.margins: sidebarPadding
            spacing: sidebarPadding
            SystemButtonRow {
                Layout.fillHeight: false
                Layout.fillWidth: true
                Layout.topMargin: 5
                Layout.bottomMargin: 0
            }
            Loader {
                id: slidersLoader
                Layout.fillWidth: true
                visible: active
                active: {
                    const configQuickSliders = Config.options.sidebar.quickSliders
                    if (!configQuickSliders.enable) return false
                    if (!configQuickSliders.showMic && !configQuickSliders.showVolume && !configQuickSliders.showBrightness) return false;
                    return true;
                }
                sourceComponent: QuickSliders {}
            }
            LoaderedQuickPanelImplementation {
                styleName: "classic"
                sourceComponent: ClassicQuickPanel {}
            }
            LoaderedQuickPanelImplementation {
                styleName: "android"
                sourceComponent: AndroidQuickPanel {
                    editMode: root.editMode
                }
            }
            CenterWidgetGroup {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                Layout.fillWidth: true
                // Same edges as the quick toggles and resource tiles (their panel's 6 px inset)
                Layout.leftMargin: 6
                Layout.rightMargin: 6
            }
            ResourceMonitorWidget {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                visible: Config.options.sidebar.resourceMonitor.enable
            }
        }
    }
    ToggleDialog {
        shownPropertyString: "showAudioOutputDialog"
        dialog: VolumeDialog {
            isSink: true
        }
    }
    ToggleDialog {
        shownPropertyString: "showAudioInputDialog"
        dialog: VolumeDialog {
            isSink: false
        }
    }
    ToggleDialog {
        shownPropertyString: "showBluetoothDialog"
        dialog: BluetoothDialog {}
        onShownChanged: {
            if (!shown) {
                Bluetooth.defaultAdapter.discovering = false;
            } else {
                Bluetooth.defaultAdapter.enabled = true;
                Bluetooth.defaultAdapter.discovering = true;
            }
        }
    }
    ToggleDialog {
        shownPropertyString: "showNightLightDialog"
        dialog: NightLightDialog {}
    }
    ToggleDialog {
        shownPropertyString: "showWifiDialog"
        dialog: WifiDialog {}
        onShownChanged: {
            if (!shown) { Network.stopScan(); return; }
            Network.enableWifi();
            Network.rescanWifi();
        }
    }
    component ToggleDialog: Loader {
        id: toggleDialogLoader
        required property string shownPropertyString
        property alias dialog: toggleDialogLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]
        anchors.fill: parent
        onShownChanged: if (shown) toggleDialogLoader.active = true;
        active: shown
        onActiveChanged: {
            if (active) {
                item.show = true;
                item.forceActiveFocus();
            }
        }
        Connections {
            target: toggleDialogLoader.item
            function onDismiss() {
                toggleDialogLoader.item.show = false
                root[toggleDialogLoader.shownPropertyString] = false;
            }
            function onVisibleChanged() {
                if (!toggleDialogLoader.item.visible && !root[toggleDialogLoader.shownPropertyString]) toggleDialogLoader.active = false;
            }
        }
    }
    component LoaderedQuickPanelImplementation: Loader {
        id: quickPanelImplLoader
        required property string styleName
        Layout.alignment: item?.Layout.alignment ?? Qt.AlignHCenter
        Layout.fillWidth: item?.Layout.fillWidth ?? false
        visible: active
        active: Config.options.sidebar.quickToggles.style === styleName
        Connections {
            target: quickPanelImplLoader.item
            function onOpenAudioOutputDialog() {
                root.showAudioOutputDialog = true;
            }
            function onOpenAudioInputDialog() {
                root.showAudioInputDialog = true;
            }
            function onOpenBluetoothDialog() {
                root.showBluetoothDialog = true;
            }
            function onOpenNightLightDialog() {
                root.showNightLightDialog = true;
            }
            function onOpenWifiDialog() {
                root.showWifiDialog = true;
            }
        }
    }
    component SystemButtonRow: Rectangle {
        color: "transparent" // Sits on the drawer, like the top of the clock/battery popups
        implicitHeight: 50
        RowLayout {
            id: contentRow
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 6
                topMargin: 6
                bottomMargin: 6
            }
            spacing: 10
            // Distro icon in a quiet squircle, like the system buttons beside it (accent means "on")
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 36
                height: 36
                radius: 12
                color: Appearance.colors.colLayer2
                CustomIcon {
                    id: distroIcon
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    source: SystemInfo.distroIcon
                    colorize: true
                    color: Appearance.colors.colOnLayer2
                }
            }
            // Uptime
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                text: Translation.tr("Up %1").arg(DateTime.uptime)
                textFormat: Text.PlainText
            }
            Item { Layout.fillWidth: true }
            // System buttons
            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: 6
                Repeater {
                    model: [
                        { icon: "edit", tip: "edit" },
                        { icon: "restart_alt", tip: "reload" },
                        { icon: "settings", tip: "settings" },
                        { icon: "power_settings_new", tip: "session" },
                    ]
                    delegate: Item {
                        required property var modelData
                        required property int index
                        visible: modelData.icon !== "edit" || Config.options.sidebar.quickToggles.style === "android"
                        width: 36
                        height: 36
                        Rectangle { // A squircle, like the quick toggles' icons
                            anchors.fill: parent
                            radius: 12
                            color: {
                                const isToggled = modelData.icon === "edit" && root.editMode
                                if (isToggled) return Appearance.colors.colPrimary
                                return _btnMa.containsPress ? Appearance.colors.colLayer2Active
                                     : _btnMa.containsMouse ? Appearance.colors.colLayer2Hover
                                     : Appearance.colors.colLayer2
                            }
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: 20
                            fill: (modelData.icon === "edit" && root.editMode) ? 1 : 0
                            color: {
                                const isToggled = modelData.icon === "edit" && root.editMode
                                if (isToggled) return Appearance.colors.colOnPrimary
                                return _btnMa.containsMouse ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                            }
                            text: modelData.icon
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                        MouseArea {
                            id: _btnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                switch (modelData.icon) {
                                    case "edit": root.editMode = !root.editMode; break;
                                    case "restart_alt":
                                        Quickshell.execDetached(["hyprctl", "reload"]); // The Lua API has no reload dispatcher
                                        Quickshell.reload(true);
                                        break;
                                    case "settings":
                                        GlobalStates.sidebarRightOpen = false;
                                        Quickshell.execDetached([root.openSettingsScript]);
                                        break;
                                    case "power_settings_new":
                                        GlobalStates.sessionOpen = true;
                                        break;
                                }
                            }
                        }
                        StyledToolTip {
                            visible: _btnMa.containsMouse
                            text: {
                                switch (modelData.icon) {
                                    case "edit": return Translation.tr("Edit quick toggles") + (root.editMode ? Translation.tr("\nLMB to enable/disable\nRMB to toggle size\nScroll to swap position") : "");
                                    case "restart_alt": return Translation.tr("Reload Hyprland & Quickshell");
                                    case "settings": return Translation.tr("Settings");
                                    case "power_settings_new": return Translation.tr("Session");
                                    default: return "";
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
