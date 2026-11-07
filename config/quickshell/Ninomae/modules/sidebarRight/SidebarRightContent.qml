import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.sidebarRight.quickToggles
import qs.modules.sidebarRight.quickToggles.classicStyle
import qs.modules.sidebarRight.resourceMonitor
import qs.modules.sidebarRight.notifications
Item {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    // When the blob drawer in SidebarRight.qml draws the background, skip our own card
    property bool drawnByDrawer: false
    property int sidebarPadding: 10
    property string openSettingsScript: Quickshell.shellPath("scripts/open-settings.sh")
    property bool editMode: false
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
                Layout.fillWidth: true
                Layout.topMargin: 6
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                Layout.bottomMargin: 4
            }
            GroupBox { // Quick settings
                GroupLabel { text: Translation.tr("Quick settings") }
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
            }
            GroupBox { // Notifications: its label row carries the count, Do not disturb and Clear all
                Layout.fillHeight: true
                NotificationList {
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    // Same edges as the quick toggles and resource tiles (their panel's 6 px inset)
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                }
            }
            GroupBox { // System
                visible: Config.options.sidebar.resourceMonitor.enable
                GroupLabel { text: Translation.tr("System") }
                ResourceMonitorWidget {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                }
            }
        }
    }
    // A group in a soft box, as the page list in Settings and the control centre: its name, then what's in it
    component GroupBox: Rectangle {
        default property alias content: boxColumn.data
        Layout.fillWidth: true
        implicitHeight: boxColumn.implicitHeight + 16
        color: Appearance.m3colors.m3surfaceContainerLow
        radius: Appearance.rounding.large
        ColumnLayout {
            id: boxColumn
            anchors { fill: parent; topMargin: 10; bottomMargin: 6 }
            spacing: 4
        }
    }
    // A group's name, small and grey, in line with what's under it, as Settings' (ContentSection)
    component GroupLabel: StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 10
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.Medium
        color: Appearance.colors.colSubtext
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
            // The tiles' arrows: the control centre at their page (modules/controlCenter)
            function onOpenAudioOutputPage() { GlobalStates.openControlCenter("sound"); }
            function onOpenAudioInputPage() { GlobalStates.openControlCenter("sound"); }
            function onOpenBluetoothPage() { GlobalStates.openControlCenter("bluetooth"); }
            function onOpenNightLightPage() { GlobalStates.openControlCenter("display"); }
            function onOpenWifiPage() { GlobalStates.openControlCenter("wifi"); }
        }
    }
    // You (as Settings' page list shows you) and how long the system's been up, then round buttons as Settings'
    // Close: edit the quick toggles, reload, Settings, the session screen
    component SystemButtonRow: RowLayout {
        spacing: 12
        Avatar {}
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: SystemInfo.username
                font.family: Appearance.font.family.expressive
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Up %1").arg(DateTime.uptime)
                textFormat: Text.PlainText
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }
        RowLayout { // The buttons, closer together than the name: a set
            spacing: 6
            IconButton {
                visible: Config.options.sidebar.quickToggles.style === "android"
                symbol: "edit"
                toggled: root.editMode
                tip: Translation.tr("Edit quick toggles") + (root.editMode ? Translation.tr("\nClick to turn on or off\nRight-click to change the size\nScroll to move it") : "")
                onClicked: root.editMode = !root.editMode
            }
            IconButton {
                symbol: "restart_alt"
                tip: Translation.tr("Reload Hyprland and the shell")
                onClicked: {
                    Quickshell.execDetached(["hyprctl", "reload"]); // The Lua API has no reload dispatcher
                    Quickshell.reload(true);
                }
            }
            IconButton {
                symbol: "settings"
                tip: Translation.tr("Settings")
                onClicked: {
                    GlobalStates.sidebarRightOpen = false;
                    Quickshell.execDetached([root.openSettingsScript]);
                }
            }
            IconButton {
                symbol: "power_settings_new"
                tip: Translation.tr("Session")
                onClicked: GlobalStates.sessionOpen = true
            }
        }
    }
}
