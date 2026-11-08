import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.sidebarRight.quickToggles
import qs.modules.sidebarRight.resourceMonitor
import qs.modules.sidebarRight.notifications
// The sidebar's contents. The drawer it sits in (SidebarRight.qml) draws the background and fits its height to
// implicitHeight, up to the screen's
Item {
    id: root
    property string openSettingsScript: Quickshell.shellPath("scripts/open-settings.sh")
    property bool editMode: false
    implicitHeight: mainColumn.implicitHeight + mainColumn.anchors.margins * 2
    implicitWidth: Appearance.sizes.sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2
    // The sidebar in four blocks, as Settings joins its rows: quick toggles, sliders and what's playing,
    // notifications, system. No boxes around them, and only the notifications carry a name
    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12
        SystemButtonRow {
            Layout.fillWidth: true
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
        ColumnLayout { // Sliders over the player, joined
            id: soundBlock
            readonly property real outer: Appearance.rounding.normal
            readonly property real inner: Appearance.rounding.joined
            readonly property var sliderOptions: Config.options.sidebar.quickSliders
            readonly property bool slidersShown: sliderOptions.showVolume || sliderOptions.showBrightness || sliderOptions.showMic
            readonly property bool mediaShown: Config.options.sidebar.showMedia && MprisController.activePlayer !== null
            visible: slidersShown || mediaShown
            Layout.fillWidth: true
            spacing: 4
            Loader {
                Layout.fillWidth: true
                visible: active
                active: soundBlock.slidersShown
                sourceComponent: QuickSliders {
                    topLeftRadius: soundBlock.outer
                    topRightRadius: soundBlock.outer
                    bottomLeftRadius: soundBlock.mediaShown ? soundBlock.inner : soundBlock.outer
                    bottomRightRadius: bottomLeftRadius
                }
            }
            Loader {
                Layout.fillWidth: true
                visible: active
                active: soundBlock.mediaShown
                sourceComponent: SidebarMedia {
                    topLeftRadius: soundBlock.slidersShown ? soundBlock.inner : soundBlock.outer
                    topRightRadius: topLeftRadius
                    bottomLeftRadius: soundBlock.outer
                    bottomRightRadius: soundBlock.outer
                }
            }
        }
        NotificationList { // "Notifications · 3", Do not disturb and Clear all, then the cards
            Layout.fillHeight: true
            Layout.fillWidth: true
        }
        ResourceMonitorWidget {
            visible: Config.options.sidebar.resourceMonitor.enable
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
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
            // The tiles' arrows: the control centre at their page (modules/controlCenter)
            function onOpenAudioOutputPage() { GlobalStates.openControlCenter("sound"); }
            function onOpenAudioInputPage() { GlobalStates.openControlCenter("sound"); }
            function onOpenBluetoothPage() { GlobalStates.openControlCenter("bluetooth"); }
            function onOpenNightLightPage() { GlobalStates.openControlCenter("display"); }
            function onOpenWifiPage() { GlobalStates.openControlCenter("wifi"); }
        }
    }
    // You (as Settings' page list shows you), the date and how long the system's been up, then the system buttons:
    // edit the quick toggles, reload, Settings, the session screen
    component SystemButtonRow: RowLayout {
        spacing: 10
        Avatar {
            implicitWidth: 38
            implicitHeight: 38
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: -2
            StyledText {
                Layout.fillWidth: true
                text: SystemInfo.username
                font.family: Appearance.font.family.expressive
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("%1 · up %2").arg(Qt.locale().toString(DateTime.clock.date, "dddd d MMMM")).arg(DateTime.uptime)
                textFormat: Text.PlainText
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }
        RowLayout { // The buttons, closer together than the name: a set
            spacing: 4
            SideButton {
                visible: Config.options.sidebar.quickToggles.style === "android"
                symbol: "edit"
                toggled: root.editMode
                tip: Translation.tr("Edit quick toggles") + (root.editMode ? Translation.tr("\nClick to turn on or off\nDrag to move, or below the line to take out\nRight-click to change the size") : "")
                onClicked: root.editMode = !root.editMode
            }
            SideButton {
                symbol: "restart_alt"
                tip: Translation.tr("Reload Hyprland and the shell")
                onClicked: {
                    Quickshell.execDetached(["hyprctl", "reload"]); // The Lua API has no reload dispatcher
                    Quickshell.reload(true);
                }
            }
            SideButton {
                symbol: "settings"
                tip: Translation.tr("Settings")
                onClicked: {
                    GlobalStates.sidebarRightOpen = false;
                    Quickshell.execDetached([root.openSettingsScript]);
                }
            }
            SideButton {
                symbol: "power_settings_new"
                tip: Translation.tr("Session")
                onClicked: GlobalStates.sessionOpen = true
            }
        }
    }
    // A system button on the cards' surface
    component SideButton: IconButton {
        size: 32
        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: Appearance.colors.colLayer3Hover
        colRipple: Appearance.colors.colLayer3Active
    }
}
