import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
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
    // The sidebar (S2b, lit capsules in wells): you, straight on the glass, your buttons in a capsule; then three wells:
    // your machine as capsules filled to their level (RAM, CPU, GPU); the controls (the quick toggles as lit capsules,
    // then the sound: what's playing as a glass piece with the sliders in it, or the sliders alone, each a thick lit
    // capsule); the notifications last, so the one list that grows has the room under it
    ColumnLayout {
        id: mainColumn
        readonly property var sliderOptions: Config.options.sidebar.quickSliders
        readonly property bool slidersShown: sliderOptions.showVolume || sliderOptions.showBrightness || sliderOptions.showMic
        readonly property bool mediaShown: Config.options.sidebar.showMedia && MprisController.activePlayer !== null
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12
        SystemButtonRow {
            Layout.fillWidth: true
        }
        ResourceMonitorWidget {
            visible: Config.options.sidebar.resourceMonitor.enable
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
        }
        Item { // The controls, in their well: the quick toggles, then the sound
            Layout.fillWidth: true
            implicitHeight: controlsColumn.implicitHeight + 20
            GlassWell {
                anchors.fill: parent
            }
            ColumnLayout {
                id: controlsColumn
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                spacing: 8
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
                Loader { // What's playing, a glass piece with the sliders inside it (one block for sound)
                    Layout.fillWidth: true
                    visible: active
                    active: mainColumn.mediaShown
                    sourceComponent: SidebarMedia {
                        withSliders: mainColumn.slidersShown
                        radius: Appearance.rounding.normal - 4 // Concentric with the well, 6 px in
                        color: ColorUtils.mix(ColorUtils.transparentize(Appearance.m3colors.m3background, 0.45), tint, 0.86)
                    }
                }
                Loader { // Nothing playing: the sliders on their own, straight on the well
                    Layout.fillWidth: true
                    visible: active
                    active: mainColumn.slidersShown && !mainColumn.mediaShown
                    sourceComponent: QuickSliders {}
                }
            }
        }
        Item { // The notifications, in their well
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: notificationList.implicitHeight + 12
            GlassWell {
                anchors.fill: parent
            }
            NotificationList { // "Notifications 3", Do not disturb and Clear all, then the cards (or All caught up)
                id: notificationList
                anchors { fill: parent; margins: 6 }
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
            // The tiles' arrows: the control centre at their page (modules/controlCenter)
            function onOpenAudioOutputPage() { GlobalStates.openControlCenter("sound"); }
            function onOpenAudioInputPage() { GlobalStates.openControlCenter("sound"); }
            function onOpenBluetoothPage() { GlobalStates.openControlCenter("bluetooth"); }
            function onOpenNightLightPage() { GlobalStates.openControlCenter("display"); }
            function onOpenWifiPage() { GlobalStates.openControlCenter("wifi"); }
        }
    }
    // You, greeted, straight on the glass with a soft halo behind your picture: the date, the weather and how long the
    // system's been up under it, then the system buttons (edit the quick toggles, reload, Settings, the session screen)
    component SystemButtonRow: Rectangle {
        id: headerCard
        readonly property int hour: DateTime.clock.date.getHours()
        readonly property string greeting: hour < 6 ? Translation.tr("Good night")
            : hour < 12 ? Translation.tr("Good morning")
            : hour < 18 ? Translation.tr("Good afternoon") : Translation.tr("Good evening")
        readonly property bool showWeather: Weather.enabled && (Weather.data.temp ?? "") !== ""
        implicitHeight: 56
        color: "transparent"
        Halo { // The halo behind your picture
            colour: Appearance.colors.colPrimary
            strength: 0.32
            reach: 31
            // The picture's centre in the header (it sits in the row, which is set in from the header's edge)
            centreX: headerRow.x + avatar.x + avatar.width / 2
            centreY: headerRow.y + avatar.y + avatar.height / 2
        }
        RowLayout {
            id: headerRow
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 10
            Avatar {
                id: avatar
                implicitWidth: 40
                implicitHeight: 40
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("%1, %2").arg(headerCard.greeting).arg(SystemInfo.username)
                    textFormat: Text.PlainText
                    font.weight: Font.DemiBold
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer3
                    elide: Text.ElideRight
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    StyledText {
                        text: Qt.locale().toString(DateTime.clock.date, "ddd d MMM")
                        textFormat: Text.PlainText
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtextGlass
                    }
                    MaterialSymbol {
                        visible: headerCard.showWeather
                        Layout.leftMargin: 2
                        text: Weather.data.icon || "cloud"
                        iconSize: 13
                        fill: 1
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: (headerCard.showWeather ? String(Weather.data.temp).replace(/[CF]$/, "") + " · " : "· ")
                            + Translation.tr("up %1").arg(DateTime.uptime)
                        textFormat: Text.PlainText
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtextGlass
                        elide: Text.ElideRight
                    }
                }
            }
            Rectangle { // The buttons, a set in their own capsule
                implicitWidth: buttonRow.implicitWidth + 8
                implicitHeight: 36
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.04)
                border { width: 1; color: Qt.rgba(1, 1, 1, 0.1) }
                RowLayout {
                    id: buttonRow
                    anchors.centerIn: parent
                    spacing: 2
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
                        colSymbol: Appearance.colors.colPrimary // Leaving: the accent
                    }
                }
            }
        }
    }
    // A system button by your name, in the buttons' capsule: a plain icon, a round shade on hover
    component SideButton: IconButton {
        size: 30
        round: true
        colBackground: "transparent"
        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.86)
        colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.78)
    }
}
