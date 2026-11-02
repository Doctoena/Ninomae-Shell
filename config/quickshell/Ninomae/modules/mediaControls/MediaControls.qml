pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Hyprland
Scope {
    id: root
    property bool visible: false
    // Window kept from opening until the drawer has slid back into the bar (a flag set on close
    // raced the window being removed, so it could vanish instead; see sessionScreen/SessionScreen.qml)
    property bool keepWindow: false
    Connections {
        target: GlobalStates
        function onMediaControlsOpenChanged() {
            if (GlobalStates.mediaControlsOpen) root.keepWindow = true;
        }
    }
    Timer { // Safety net in case the slide never finishes
        interval: 1500
        running: root.keepWindow && !GlobalStates.mediaControlsOpen
        onTriggered: root.keepWindow = false
    }
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property var realPlayers: Mpris.players.values.filter(player => isRealPlayer(player))
    readonly property var meaningfulPlayers: filterDuplicatePlayers(realPlayers)
    readonly property real osdWidth: Appearance.sizes.osdWidth
    readonly property real widgetWidth: Appearance.sizes.mediaControlsWidth
    property real popupRounding: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
    property var visualizerPoints: []
    property bool hasPlasmaIntegration: false
    Process {
        id: plasmaIntegrationAvailabilityCheckProc
        running: true
        command: ["bash", "-c", "command -v plasma-browser-integration-host"]
        onExited: (exitCode, exitStatus) => {
            root.hasPlasmaIntegration = (exitCode === 0);
        }
    }
    function isRealPlayer(player) {
        if (!Config.options.media.filterDuplicatePlayers) {
            return true;
        }
        return (
            // Remove unecessary native buses from browsers if there's plasma integration
            !(hasPlasmaIntegration && player.dbusName.startsWith('org.mpris.MediaPlayer2.firefox')) && !(hasPlasmaIntegration && player.dbusName.startsWith('org.mpris.MediaPlayer2.chromium')) &&
            // playerctld just copies other buses and we don't need duplicates
            !player.dbusName?.startsWith('org.mpris.MediaPlayer2.playerctld') &&
            // Non-instance mpd bus
            !(player.dbusName?.endsWith('.mpd') && !player.dbusName.endsWith('MediaPlayer2.mpd')));
    }
    function filterDuplicatePlayers(players) {
        let filtered = [];
        let used = new Set();
        for (let i = 0; i < players.length; ++i) {
            if (used.has(i))
                continue;
            let p1 = players[i];
            let group = [i];
            // Find duplicates by trackTitle prefix
            for (let j = i + 1; j < players.length; ++j) {
                let p2 = players[j];
                if (p1.trackTitle && p2.trackTitle && (p1.trackTitle.includes(p2.trackTitle) || p2.trackTitle.includes(p1.trackTitle)) || (p1.position - p2.position <= 2 && p1.length - p2.length <= 2)) {
                    group.push(j);
                }
            }
            // Pick the one with non-empty trackArtUrl, or fallback to the first
            let chosenIdx = group.find(idx => players[idx].trackArtUrl && players[idx].trackArtUrl.length > 0);
            if (chosenIdx === undefined)
                chosenIdx = group[0];
            filtered.push(players[chosenIdx]);
            group.forEach(idx => used.add(idx));
        }
        return filtered;
    }
    Process {
        id: cavaProc
        running: mediaControlsLoader.active
        onRunningChanged: {
            if (!cavaProc.running) {
                root.visualizerPoints = [];
            }
        }
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                // Parse `;`-separated values into the visualizerPoints array
                let points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
                root.visualizerPoints = points;
            }
        }
    }
    Loader {
        id: mediaControlsLoader
        active: GlobalStates.mediaControlsOpen || root.keepWindow
        onActiveChanged: {
            if (!mediaControlsLoader.active && Mpris.players.values.filter(player => isRealPlayer(player)).length === 0) {
                GlobalStates.mediaControlsOpen = false;
            }
        }
        sourceComponent: PanelWindow {
            id: mediaControlsRoot
            // ── Drawer that slides out of the bar (same animation as the launcher, overview/SearchWidget.qml) ──
            readonly property real sideMargin: 40 // Room for the gooey joins either side
            readonly property real hiddenExtra: 60
            readonly property real bottomRadius: root.popupRounding + 6
            readonly property real barBottom: GlobalStates.drawerTopOn(screen) // Below the bar, or near the top without one
            readonly property real panelWidth: playerColumnLayout.implicitWidth
            readonly property real fullHeight: playerColumnLayout.implicitHeight
            readonly property bool wanted: GlobalStates.mediaControlsOpen

            readonly property bool drawerReady: readiness.ready // Slide only once the window is on screen

            // 0 = out, 1 = tucked under the bar
            property real offsetScale: (wanted && drawerReady) ? 0 : 1
            Behavior on offsetScale {
                NumberAnimation {
                    duration: mediaControlsRoot.wanted ? Appearance.animationCurves.drawerOpenDuration : Appearance.animationCurves.drawerCloseDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: mediaControlsRoot.wanted ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
                }
            }
            onOffsetScaleChanged: if (offsetScale >= 1 && !wanted) root.keepWindow = false
            onWantedChanged: if (!wanted && offsetScale >= 1) Qt.callLater(() => { if (!GlobalStates.mediaControlsOpen) root.keepWindow = false; })
            readonly property real drawerTop: -(fullHeight + hiddenExtra) * offsetScale
            readonly property real drawerY: Math.min(0, drawerTop)
            readonly property real drawerHeight: fullHeight + Math.max(0, drawerTop) // Overshoot stretches
            readonly property real visibleHeight: Math.max(0, drawerY + drawerHeight)

            visible: true
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            implicitWidth: panelWidth + sideMargin * 2
            implicitHeight: Math.ceil(fullHeight * 1.12) // Headroom for the overshoot stretch
            color: "transparent"
            WlrLayershell.namespace: "quickshell:mediaControls"
            WlrLayershell.layer: WlrLayer.Overlay // Above the bar, so the drawer covers its border where they join
            anchors {
                top: true
                bottom: false
                left: false
                right: true
            }
            margins {
                top: mediaControlsRoot.barBottom // Directly below the bar: overlapping its last row drew that row twice (a dark line); the bar skips its border here instead (BarJoin)
                right: 0
            }
            mask: Region {
                item: maskArea
            }
            HyprlandFocusGrab {
                windows: [mediaControlsRoot]
                active: GlobalStates.mediaControlsOpen
                onCleared: () => {
                    if (!active) {
                        GlobalStates.mediaControlsOpen = false;
                    }
                }
            }
            Item {
                id: maskArea
                x: mediaControlsRoot.sideMargin
                width: mediaControlsRoot.panelWidth
                height: mediaControlsRoot.visibleHeight
            }
            Item {
                id: stage
                anchors.fill: parent
                clip: true
                DrawerReadiness { id: readiness } // The window is made for each opening: always active
                BarJoin { // Lets the bar skip its bottom border where the drawer joins it
                    name: "mediaControls"
                    active: mediaControlsRoot.visibleHeight > 0
                    joinX: (mediaControlsRoot.screen?.width ?? 0) - mediaControlsRoot.implicitWidth + mediaControlsRoot.sideMargin
                    joinWidth: mediaControlsRoot.panelWidth
                }
                DrawerBackground { // Shared with the launcher and the other drawers
                    followBar: true // A card while there's no bar (a fullscreen game)
                    id: background
                    anchors.fill: parent
                    screenWidth: mediaControlsRoot.screen?.width ?? 0
                    windowScreenX: (mediaControlsRoot.screen?.width ?? 0) - mediaControlsRoot.implicitWidth
                    drawerX: mediaControlsRoot.sideMargin
                    drawerY: mediaControlsRoot.drawerY
                    drawerWidth: mediaControlsRoot.panelWidth
                    drawerHeight: mediaControlsRoot.drawerHeight
                    drawerRadius: Math.min(mediaControlsRoot.bottomRadius, mediaControlsRoot.visibleHeight / 2)
                    fallbackRadius: mediaControlsRoot.bottomRadius
                }
            Item { // Content slides with the drawer
                x: mediaControlsRoot.sideMargin
                y: mediaControlsRoot.drawerY
                width: mediaControlsRoot.panelWidth
                height: mediaControlsRoot.fullHeight
                opacity: 1 - mediaControlsRoot.offsetScale
                transform: Matrix4x4 { // Wobble with the blob
                    matrix: background.deformMatrix
                }
            ColumnLayout {
                id: playerColumnLayout
                anchors {
                    top: parent.top
                    left: parent.left
                }
                spacing: 0
                Repeater {
                    model: ScriptModel {
                        values: root.meaningfulPlayers
                    }
                    delegate: PlayerControl {
                        required property MprisPlayer modelData
                        player: modelData
                        visualizerPoints: root.visualizerPoints
                        Layout.preferredWidth: root.widgetWidth
                        radius: root.popupRounding
                    }
                }
                Item { // No player placeholder
                    visible: root.meaningfulPlayers.length === 0
                    Layout.preferredWidth: root.widgetWidth
                    implicitHeight: placeholderLayout.implicitHeight + 48
                    ColumnLayout {
                        id: placeholderLayout
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.bottomMargin: 6
                            implicitWidth: 52; implicitHeight: 52; radius: 17
                            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                            MaterialSymbol { anchors.centerIn: parent; text: "music_off"; fill: 1; iconSize: 26; color: Appearance.colors.colPrimary }
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Nothing playing")
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            horizontalAlignment: Text.AlignHCenter
                            text: Translation.tr("Start music in an app with media controls (MPRIS)")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
            }
            }
        }
    }
    IpcHandler {
        target: "mediaControls"
        function toggle(): void {
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
            if (GlobalStates.mediaControlsOpen)
                Notifications.timeoutAll();
        }
        function close(): void {
            GlobalStates.mediaControlsOpen = false;
        }
        function open(): void {
            GlobalStates.mediaControlsOpen = true;
            Notifications.timeoutAll();
        }
    }
    GlobalShortcut {
        name: "mediaControlsToggle"
        description: "Toggles media controls on press"
        onPressed: {
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
        }
    }
    GlobalShortcut {
        name: "mediaControlsOpen"
        description: "Opens media controls on press"
        onPressed: {
            GlobalStates.mediaControlsOpen = true;
        }
    }
    GlobalShortcut {
        name: "mediaControlsClose"
        description: "Closes media controls on press"
        onPressed: {
            GlobalStates.mediaControlsOpen = false;
        }
    }
}
