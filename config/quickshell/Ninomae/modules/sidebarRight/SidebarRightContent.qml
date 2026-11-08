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
    // The sidebar in blocks, as Settings joins its rows: you and the system buttons; the controls (quick toggles,
    // then the sliders and what's playing, joined into one block); RAM, CPU and GPU; the notifications last, so
    // the one list that grows has the room under it. No boxes around them, and only the notifications carry a name
    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12
        SystemButtonRow {
            Layout.fillWidth: true
        }
        ColumnLayout { // The controls
            id: controls
            readonly property real outer: Appearance.rounding.normal
            readonly property real inner: Appearance.rounding.joined
            readonly property var sliderOptions: Config.options.sidebar.quickSliders
            readonly property bool slidersShown: sliderOptions.showVolume || sliderOptions.showBrightness || sliderOptions.showMic
            readonly property bool mediaShown: Config.options.sidebar.showMedia && MprisController.activePlayer !== null
            // The tiles join what's under them (not the classic style's buttons, nor while editing them)
            readonly property bool joined: Config.options.sidebar.quickToggles.style === "android" && !root.editMode
                && (slidersShown || mediaShown)
            Layout.fillWidth: true
            spacing: 4
            LoaderedQuickPanelImplementation {
                styleName: "classic"
                sourceComponent: ClassicQuickPanel {}
            }
            LoaderedQuickPanelImplementation {
                styleName: "android"
                sourceComponent: AndroidQuickPanel {
                    editMode: root.editMode
                    joinedBelow: controls.joined
                }
            }
            Loader {
                Layout.fillWidth: true
                visible: active
                active: controls.slidersShown
                Layout.topMargin: controls.joined ? 0 : 8 // Apart from the tiles: the blocks' 12 px gap
                sourceComponent: QuickSliders {
                    topLeftRadius: controls.joined ? controls.inner : controls.outer
                    topRightRadius: topLeftRadius
                    bottomLeftRadius: controls.mediaShown ? controls.inner : controls.outer
                    bottomRightRadius: bottomLeftRadius
                }
            }
            Loader {
                Layout.fillWidth: true
                Layout.topMargin: controls.joined || controls.slidersShown ? 0 : 8 // As the sliders' gap, when it's first
                visible: active
                active: controls.mediaShown
                sourceComponent: SidebarMedia {
                    topLeftRadius: controls.joined || controls.slidersShown ? controls.inner : controls.outer
                    topRightRadius: topLeftRadius
                    bottomLeftRadius: controls.outer
                    bottomRightRadius: controls.outer
                }
            }
        }
        ResourceMonitorWidget {
            visible: Config.options.sidebar.resourceMonitor.enable
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
        }
        NotificationList { // "Notifications · 3", Do not disturb and Clear all, then the cards
            Layout.fillHeight: true
            Layout.fillWidth: true
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
