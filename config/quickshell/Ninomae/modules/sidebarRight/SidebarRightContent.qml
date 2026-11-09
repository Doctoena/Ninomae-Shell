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
    // The sidebar in blocks, as Settings joins its rows: you and the system buttons; the controls (quick toggles,
    // then what's playing with the sliders inside it, or the sliders alone, joined into one block); RAM, CPU and
    // GPU; the notifications last, so the one list that grows has the room under it
    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12
        ColumnLayout { // One joined stack, as in the mockup: you, the controls, RAM / CPU / GPU
            id: stack
            readonly property bool resourcesShown: Config.options.sidebar.resourceMonitor.enable
            // The volume (nothing playing) and RAM / CPU / GPU make one card, a hairline between them
            readonly property bool slidersOnStats: resourcesShown && controls.slidersShown && !controls.mediaShown
            Layout.fillWidth: true
            spacing: 4
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
                    && (slidersShown || mediaShown || stack.resourcesShown)
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
                        joinedAbove: true // The header card
                        joinedBelow: controls.joined
                    }
                }
                Loader { // What's playing, with the sliders inside it (one block for sound)
                    Layout.fillWidth: true
                    Layout.topMargin: controls.joined ? 0 : 8 // Apart from the tiles: the blocks' 12 px gap
                    visible: active
                    active: controls.mediaShown
                    sourceComponent: SidebarMedia {
                        withSliders: controls.slidersShown
                        topLeftRadius: controls.joined ? controls.inner : controls.outer
                        topRightRadius: topLeftRadius
                        bottomLeftRadius: stack.resourcesShown ? controls.inner : controls.outer
                        bottomRightRadius: bottomLeftRadius
                    }
                }
                Loader { // Nothing playing: the sliders on their own
                    Layout.fillWidth: true
                    Layout.topMargin: controls.joined ? 0 : 8
                    visible: active
                    active: controls.slidersShown && !controls.mediaShown
                    sourceComponent: QuickSliders {
                        topLeftRadius: controls.joined ? controls.inner : controls.outer
                        topRightRadius: topLeftRadius
                        bottomLeftRadius: stack.slidersOnStats ? 0 : stack.resourcesShown ? controls.inner : controls.outer
                        bottomRightRadius: bottomLeftRadius
                    }
                }
            }
            ResourceMonitorWidget {
                visible: stack.resourcesShown
                joinedAbove: true
                flushAbove: stack.slidersOnStats
                Layout.topMargin: flushAbove ? -stack.spacing : 0
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
            }
        }
        NotificationList { // "Notifications 3", Do not disturb and Clear all, then the cards (or All caught up)
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
    // You, greeted, in a card with a soft halo behind your picture: the date, the weather and how long the system's
    // been up under it, then the system buttons (edit the quick toggles, reload, Settings, the session screen)
    component SystemButtonRow: Rectangle {
        id: headerCard
        readonly property int hour: DateTime.clock.date.getHours()
        readonly property string greeting: hour < 6 ? Translation.tr("Good night")
            : hour < 12 ? Translation.tr("Good morning")
            : hour < 18 ? Translation.tr("Good afternoon") : Translation.tr("Good evening")
        readonly property bool showWeather: Weather.enabled && (Weather.data.temp ?? "") !== ""
        implicitHeight: 64
        topLeftRadius: Appearance.rounding.normal
        topRightRadius: Appearance.rounding.normal
        bottomLeftRadius: Appearance.rounding.joined // The tiles join under it
        bottomRightRadius: Appearance.rounding.joined
        color: ColorUtils.mix(Appearance.colors.colLayer3, Appearance.colors.colPrimary, 0.92)
        clip: true
        Halo { // The halo behind your picture
            colour: Appearance.colors.colPrimary
            strength: 0.32
            reach: 31
            centreX: avatar.x + avatar.width / 2
            centreY: avatar.y + avatar.height / 2
        }
        RowLayout {
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
                    font.family: Appearance.font.family.title
                    font.weight: Font.Black
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer3
                    elide: Text.ElideRight
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    StyledText {
                        text: Qt.locale().toString(DateTime.clock.date, "dddd d MMMM")
                        textFormat: Text.PlainText
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
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
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
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
    }
    // A system button on the header card: a plain icon, a shade on hover
    component SideButton: IconButton {
        size: 32
        colBackground: "transparent"
        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.86)
        colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.78)
    }
}
