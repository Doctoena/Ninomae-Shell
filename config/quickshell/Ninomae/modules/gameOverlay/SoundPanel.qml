import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

// The in-game overlay's sound card, at the foot of the performance group: the output and its volume (with more
// than one output, a button beside its name lists them: outputMenuOpen, out of the panel's side beside
// outputButton), then each app playing sound: the game first (its streams' processes are among gamePids, or for a
// Flatpak game its app id is gameFlatpak: inside the sandbox its process ids are its own), voice chat next, the
// rest after, and last the mic, for voice chat. Each icon mutes its row
Rectangle {
    id: root
    property var gamePids: []
    property string gameFlatpak: ""
    property string gameName: ""
    property string gameArt: ""
    property bool outputMenuOpen: false
    onOutputsChanged: if (outputs.length < 2) outputMenuOpen = false // Nothing to choose from any more
    readonly property Item outputButton: outputChooser
    readonly property var outputs: Pipewire.nodes.values.filter(n => n.isSink && n.audio && !n.isStream)
    // Every app's streams, tracked here so their names and processes are in before they're grouped
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isSink && n.audio && n.isStream)
    PwObjectTracker { objects: root.streams }
    // Each app's streams together, the game's apart from the rest: [{ nodes, game, voice }], game first, voice chat next
    readonly property var apps: {
        const groups = new Map();
        for (const n of root.streams) {
            const game = isGame(n);
            const key = game ? "\u0000game" : appKey(n);
            if (!groups.has(key)) groups.set(key, { nodes: [], game: game, voice: !game && isVoice(n), rank: game ? 2 : isVoice(n) ? 1 : 0 });
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
    implicitHeight: volumes.implicitHeight + 24
    topLeftRadius: Appearance.rounding.joined
    topRightRadius: Appearance.rounding.joined
    bottomLeftRadius: Appearance.rounding.normal
    bottomRightRadius: Appearance.rounding.normal
    color: Appearance.colors.colLayer3

    ColumnLayout {
        id: volumes
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; topMargin: 12 }
        spacing: 12
        DeviceRow { // The output
            muted: Audio.sink?.audio?.muted ?? false
            icon: muted ? "volume_off" : Audio.sink ? root.outputIcon(Audio.sink) : "volume_up"
            name: Audio.sink?.description || Audio.sink?.name || Translation.tr("Output")
            subtitle: Translation.tr("Output")
            volume: Audio.sink?.audio?.volume ?? 0
            onToggleMute: if (Audio.sink?.audio) Audio.sink.audio.muted = !Audio.sink.audio.muted
            onMoved: value => { if (Audio.sink?.audio) Audio.sink.audio.volume = value; }
            RippleButton { // Where the sound goes, when there's a choice: a click lists the outputs
                id: outputChooser
                visible: root.outputs.length > 1
                implicitWidth: 26
                implicitHeight: 22
                buttonRadius: Appearance.rounding.verysmall
                colBackground: root.outputMenuOpen ? Appearance.colors.colLayer4 : "transparent"
                colBackgroundHover: Appearance.colors.colLayer3Hover
                colRipple: Appearance.colors.colLayer3Active
                onClicked: root.outputMenuOpen = !root.outputMenuOpen
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    text: root.outputMenuOpen ? "chevron_left" : "chevron_right"
                    iconSize: 18
                    color: Appearance.colors.colSubtext
                }
                StyledToolTip { text: Translation.tr("Choose the output") }
            }
        }
        Repeater {
            model: ScriptModel { values: root.apps }
            AppVolume {
                required property var modelData
                Layout.fillWidth: true
                nodes: modelData.nodes
                game: modelData.game
                subtitle: modelData.game ? Translation.tr("The game") : modelData.voice ? Translation.tr("Voice chat") : ""
                gameName: root.gameName
                gameArt: root.gameArt
            }
        }
        DeviceRow { // The mic
            visible: Audio.source?.audio !== undefined
            muted: Audio.source?.audio?.muted ?? false
            icon: muted ? "mic_off" : "mic"
            warnWhenMuted: true
            name: Translation.tr("Microphone")
            subtitle: muted ? Translation.tr("Muted") : (Audio.source?.description ?? "")
            volume: Audio.source?.audio?.volume ?? 0
            onToggleMute: if (Audio.source?.audio) Audio.source.audio.muted = !Audio.source.audio.muted
            onMoved: value => { if (Audio.source?.audio) Audio.source.audio.volume = value; }
        }
    }

    // A device's row: its icon on an accent squircle (a click mutes; red when a muted mic), its name and what it is,
    // anything extra after the name (the output's chooser), the slider and the percentage
    component DeviceRow: RowLayout {
        id: row
        property string icon
        property bool muted: false
        property bool warnWhenMuted: false
        property string name
        property string subtitle
        property real volume: 0
        default property alias extra: nameRow.data
        signal toggleMute()
        signal moved(real value)
        Layout.fillWidth: true
        spacing: 12
        Rectangle {
            readonly property color tint: row.muted && row.warnWhenMuted ? Appearance.colors.colError : Appearance.colors.colPrimary
            Layout.preferredWidth: 30; Layout.preferredHeight: 30
            radius: Appearance.rounding.chip + 1
            color: row.muted && !row.warnWhenMuted ? Appearance.colors.colLayer4
                : ColorUtils.transparentize(tint, iconMouse.containsMouse ? 0.7 : 0.82)
            MaterialSymbol {
                anchors.centerIn: parent
                text: row.icon
                iconSize: 18
                fill: 1
                color: row.muted && !row.warnWhenMuted ? Appearance.colors.colSubtext : parent.tint
            }
            MouseArea {
                id: iconMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: row.toggleMute()
            }
            StyledToolTip {
                extraVisibleCondition: iconMouse.containsMouse
                text: row.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            RowLayout {
                id: nameRow
                Layout.fillWidth: true
                spacing: 6
                StyledText {
                    Layout.maximumWidth: nameRow.width - (rowSub.visible ? rowSub.implicitWidth + 6 : 0) - 32
                    elide: Text.ElideRight
                    text: row.name
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer3
                }
                StyledText {
                    id: rowSub
                    Layout.fillWidth: true
                    visible: row.subtitle !== ""
                    elide: Text.ElideRight
                    text: row.subtitle
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: row.muted && row.warnWhenMuted ? Appearance.colors.colError : Appearance.colors.colSubtext
                }
            }
            OverlaySlider {
                opacity: row.muted ? 0.4 : 1
                value: row.volume
                onMoved: row.moved(value)
            }
        }
        VolumePercent { value: row.volume; muted: row.muted }
    }
}
