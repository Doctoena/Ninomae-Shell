import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

// The in-game overlay's Sound: the mic and, with more than one output, the one in use beside it (a click opens
// outputMenuOpen: the overlay lists them out of the panel's side, beside outputButton), the output's volume, then each
// app playing sound: the game first (its streams' processes are among gamePids, or for a Flatpak game its app id is
// gameFlatpak: inside the sandbox its process ids are its own), voice chat next, the rest after. Each volume
// shows its percentage
ColumnLayout {
    id: root
    property var gamePids: []
    property string gameFlatpak: ""
    property string gameName: ""
    property string gameArt: ""
    property bool outputMenuOpen: false
    onOutputsChanged: if (outputs.length < 2) outputMenuOpen = false // Nothing to choose from any more
    readonly property Item outputButton: outputChip
    readonly property var outputs: Pipewire.nodes.values.filter(n => n.isSink && n.audio && !n.isStream)
    // Every app's streams, tracked here so their names and processes are in before they're grouped
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isSink && n.audio && n.isStream)
    PwObjectTracker { objects: root.streams }
    // Each app's streams together, the game's apart from the rest: [{ nodes, game }], game first, voice chat next
    readonly property var apps: {
        const groups = new Map();
        for (const n of root.streams) {
            const game = isGame(n);
            const key = game ? "\u0000game" : appKey(n);
            if (!groups.has(key)) groups.set(key, { nodes: [], game: game, rank: game ? 2 : isVoice(n) ? 1 : 0 });
            groups.get(key).nodes.push(n);
        }
        return [...groups.values()].sort((a, b) => b.rank - a.rank);
    }
    function appKey(node) {
        const p = node.properties;
        return p["pipewire.access.portal.app_id"] || p["application.name"] || p["application.process.binary"] || node.name;
    }
    function isGame(node) {
        if (root.gameFlatpak !== "" && node.properties["pipewire.access.portal.app_id"] === root.gameFlatpak) return true;
        const pid = Number(node.properties["application.process.id"] ?? 0);
        return pid > 0 && root.gamePids.includes(pid);
    }
    function isVoice(node) {
        return /discord|vesktop|webcord|teamspeak|mumble/i.test(`${node.properties["application.name"] ?? ""} ${node.properties["application.process.binary"] ?? ""}`);
    }
    function outputIcon(node) {
        return /hdmi|displayport/i.test(node.name) ? "tv"
            : /bluez|headphone|headset/i.test(`${node.name} ${node.description}`) ? "headphones" : "speaker";
    }
    spacing: 12
    RowLayout {
        Layout.fillWidth: true
        OverlayPanelTitle { Layout.fillWidth: true; icon: "volume_up"; text: Translation.tr("Sound") }
        OverlayChip { // The mic, for voice chat
            readonly property bool muted: Audio.source?.audio?.muted ?? false
            visible: Audio.source?.audio !== undefined
            icon: muted ? "mic_off" : "mic"
            text: muted ? Translation.tr("Mic muted") : Translation.tr("Mic on")
            warn: muted
            onClicked: Audio.source.audio.muted = !muted
        }
        OverlayChip { // Where the sound goes, when there's a choice: a click lists the outputs
            id: outputChip
            visible: root.outputs.length > 1
            Layout.maximumWidth: 190
            icon: Pipewire.defaultAudioSink ? root.outputIcon(Pipewire.defaultAudioSink) : "speaker"
            text: Pipewire.defaultAudioSink?.description || Pipewire.defaultAudioSink?.name || Translation.tr("Output")
            trailingIcon: root.outputMenuOpen ? "chevron_left" : "chevron_right"
            onClicked: root.outputMenuOpen = !root.outputMenuOpen
        }
    }
    Rectangle { // The output, then each app, on one neutral group
        Layout.fillWidth: true
        implicitHeight: volumes.implicitHeight + 20
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        ColumnLayout {
            id: volumes
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10; rightMargin: 12 }
            spacing: 10
            RowLayout { // The output: its name and volume; its squircle mutes, as the shell's Sound menu
                Layout.fillWidth: true
                spacing: 10
                QuickDialogIcon {
                    readonly property bool muted: Audio.sink?.audio?.muted ?? false
                    implicitWidth: 28; implicitHeight: 28; radius: Appearance.rounding.chip + 1
                    icon: muted ? "volume_off" : Audio.sink ? root.outputIcon(Audio.sink) : "volume_up"
                    active: !muted
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (Audio.sink?.audio) Audio.sink.audio.muted = !Audio.sink.audio.muted
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: Audio.sink?.description || Audio.sink?.name || Translation.tr("Output")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        VolumePercent { value: Audio.sink?.audio?.volume ?? 0 }
                    }
                    OverlaySlider {
                        value: Audio.sink?.audio?.volume ?? 0
                        onMoved: if (Audio.sink?.audio) Audio.sink.audio.volume = value
                    }
                }
            }
            Repeater {
                model: ScriptModel { values: root.apps }
                AppVolume {
                    required property var modelData
                    Layout.fillWidth: true
                    nodes: modelData.nodes
                    game: modelData.game
                    gameName: root.gameName
                    gameArt: root.gameArt
                }
            }
        }
    }
}
