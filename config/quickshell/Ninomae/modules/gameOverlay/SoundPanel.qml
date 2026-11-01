import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

// The in-game overlay's Sound: the mic, where the sound goes (with more than one output), its volume, then each
// app playing sound: the game first (its streams' processes are among gamePids, or for a Flatpak game its app id is
// gameFlatpak: inside the sandbox its process ids are its own), voice chat next, the rest after.
// As tall as what it holds; the apps scroll when the overlay gives it less
OverlayPanel {
    id: root
    property var gamePids: []
    property string gameFlatpak: ""
    property string gameName: ""
    property string gameArt: ""
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
    implicitHeight: column.implicitHeight + 28
    ColumnLayout {
        id: column
        anchors { fill: parent; margins: 14 }
        spacing: 10
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
        }
        Flow { // Where the sound goes, when there's a choice
            Layout.fillWidth: true
            visible: root.outputs.length > 1
            spacing: 6
            Repeater {
                model: root.outputs
                OverlayChip {
                    required property var modelData
                    icon: root.outputIcon(modelData)
                    text: modelData.description || modelData.name
                    active: Pipewire.defaultAudioSink === modelData
                    onClicked: Pipewire.preferredDefaultAudioSink = modelData
                }
            }
        }
        QuickDialogGroup { // The output: its name and volume; its squircle mutes, as the shell's Sound menu
            Layout.fillWidth: true
            padding: 8
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                QuickDialogIcon {
                    readonly property bool muted: Audio.sink?.audio?.muted ?? false
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
                    spacing: -4
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: Audio.sink?.description || Audio.sink?.name || Translation.tr("Output")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledSlider {
                        Layout.fillWidth: true
                        value: Audio.sink?.audio?.volume ?? 0
                        onMoved: if (Audio.sink?.audio) Audio.sink.audio.volume = value
                        configuration: StyledSlider.Configuration.S
                        stopIndicatorValues: []
                    }
                }
            }
        }
        StyledText {
            visible: root.apps.length === 0
            text: Translation.tr("No apps are playing sound")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
        StyledFlickable { // The apps on a neutral group, scrolling when the overlay gives less room than they need
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: appsGroup.height
            visible: root.apps.length > 0
            clip: true
            contentHeight: appsGroup.height
            Rectangle {
                id: appsGroup
                width: parent.width
                height: apps.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2
                ColumnLayout {
                    id: apps
                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 10; leftMargin: 10; rightMargin: 12 }
                    spacing: 10
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
    }
}
