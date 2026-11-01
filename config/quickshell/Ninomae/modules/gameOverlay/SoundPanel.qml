import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

// The in-game overlay's Sound: the mic, where the sound goes (with more than one output), its volume, then each
// app playing sound: the game first (its streams' processes are among gamePids, or for a Flatpak game its app id is
// gameFlatpak: inside the sandbox its process ids are its own), voice chat next, the rest after.
// The apps scroll when there are more than fit
OverlayPanel {
    id: root
    property var gamePids: []
    property string gameFlatpak: ""
    property string gameName: ""
    property string gameArt: ""
    readonly property var outputs: Pipewire.nodes.values.filter(n => n.isSink && n.audio && !n.isStream)
    readonly property var apps: Pipewire.nodes.values.filter(n => n.isSink && n.audio && n.isStream)
        .sort((a, b) => rank(b) - rank(a))
    function isGame(node) {
        if (root.gameFlatpak !== "" && node.properties["pipewire.access.portal.app_id"] === root.gameFlatpak) return true;
        const pid = Number(node.properties["application.process.id"] ?? 0);
        return pid > 0 && root.gamePids.includes(pid);
    }
    function isVoice(node) {
        return /discord|vesktop|webcord|teamspeak|mumble/i.test(`${node.properties["application.name"] ?? ""} ${node.properties["application.process.binary"] ?? ""}`);
    }
    function rank(node) { return isGame(node) ? 2 : isVoice(node) ? 1 : 0; }
    ColumnLayout {
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
                    icon: /hdmi|displayport/i.test(modelData.name) ? "tv"
                        : /bluez|headphone|headset/i.test(`${modelData.name} ${modelData.description}`) ? "headphones" : "speaker"
                    text: modelData.description || modelData.name
                    active: Pipewire.defaultAudioSink === modelData
                    onClicked: Pipewire.preferredDefaultAudioSink = modelData
                }
            }
        }
        QuickDialogGroup { // The output's volume; its squircle mutes, as the shell's Sound menu
            Layout.fillWidth: true
            padding: 8
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                QuickDialogIcon {
                    readonly property bool muted: Audio.sink?.audio?.muted ?? false
                    icon: muted ? "volume_off" : "volume_up"
                    active: !muted
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (Audio.sink?.audio) Audio.sink.audio.muted = !Audio.sink.audio.muted
                    }
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
        StyledFlickable { // The apps on a neutral group, scrolling when there are more than fit
            Layout.fillWidth: true
            Layout.fillHeight: true
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
                            node: modelData
                            game: root.isGame(modelData)
                            gameName: root.gameName
                            gameArt: root.gameArt
                        }
                    }
                }
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.apps.length === 0
            OverlayEmptyState { icon: "graphic_eq"; text: Translation.tr("No apps are playing sound") }
        }
    }
}
