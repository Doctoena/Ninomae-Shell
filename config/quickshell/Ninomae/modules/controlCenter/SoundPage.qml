pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import qs.modules.common.functions

// Sound: the output and the mic, the apps playing or recording, and the devices to pick from
ColumnLayout {
    id: page
    spacing: 14
    readonly property string subtitle: Translation.tr("Speakers, mic and app volumes")

    readonly property var audioNodes: Pipewire.nodes.values.filter(node => node.audio)
    readonly property var outputs: audioNodes.filter(node => node.isSink && !node.isStream)
    readonly property var inputs: audioNodes.filter(node => !node.isSink && !node.isStream)
    readonly property var playing: audioNodes.filter(node => node.isSink && node.isStream)
    readonly property var recording: audioNodes.filter(node => !node.isSink && node.isStream)

    ContentSection {
        title: Translation.tr("Volume")
        VolumeRow { node: Audio.sink; isOutput: true }
        VolumeRow { node: Audio.source; isOutput: false }
    }
    ContentSection { // Always there (the page says it has app volumes): a quiet note while nothing plays
        title: Translation.tr("Apps")
        Repeater {
            model: ScriptModel { values: page.playing }
            delegate: AppRow {}
        }
        SettingRow {
            visible: page.playing.length === 0
            text: Translation.tr("No apps are playing")
            description: Translation.tr("Their volumes show up here while they play")
            leading: RowSquircle { symbol: "music_off"; opacity: 0.7 }
        }
    }
    ContentSection {
        visible: page.recording.length > 0
        title: Translation.tr("Apps using the mic")
        Repeater {
            model: ScriptModel { values: page.recording }
            delegate: AppRow {}
        }
    }
    RowLayout { // The devices, outputs and inputs side by side: only when there's more than one to pick from
        visible: page.outputs.length > 1 || page.inputs.length > 1
        Layout.fillWidth: true
        spacing: 10
        DeviceList {
            title: Translation.tr("Output device")
            devices: page.outputs
            isOutput: true
        }
        DeviceList {
            title: Translation.tr("Input device")
            devices: page.inputs
            isOutput: false
        }
    }
    ContentSection {
        RowButton {
            text: Translation.tr("Advanced mixer")
            description: Translation.tr("Every app and device, with more options")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Config.options.apps.volumeMixer}`]);
                GlobalStates.controlCenterOpen = false;
            }
            leading: RowSquircle { symbol: "tune" }
            MaterialSymbol {
                text: "open_in_new"
                iconSize: 18
                color: Appearance.colors.colSubtext
            }
        }
    }

    // The device in use: its squircle is Mute (accent while it's on), its volume, the slider under
    component VolumeRow: SliderRow {
        id: volumeRow
        required property var node
        required property bool isOutput
        readonly property bool muted: node?.audio?.muted ?? false
        visible: node?.audio !== undefined
        text: isOutput ? Translation.tr("Output") : Translation.tr("Mic")
        description: node?.description ?? ""
        level: node?.audio?.volume ?? 0
        dimmed: muted
        onMoved: value => { if (volumeRow.node?.audio) volumeRow.node.audio.volume = value; }
        leading: RippleButton { // Mute: the row's squircle, accent while the sound is on
            implicitWidth: 36
            implicitHeight: 36
            buttonRadius: 11
            toggled: !volumeRow.muted
            colBackground: volumeRow.glass ? ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9) : Appearance.m3colors.m3surfaceContainerHighest
            colBackgroundHover: volumeRow.glass ? ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.84) : Appearance.colors.colLayer4Hover
            onClicked: if (volumeRow.node?.audio) volumeRow.node.audio.muted = !volumeRow.node.audio.muted
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: volumeRow.muted ? (volumeRow.isOutput ? "volume_off" : "mic_off") : (volumeRow.isOutput ? "volume_up" : "mic")
                iconSize: 20
                fill: 1
                color: volumeRow.muted ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnPrimary
            }
            StyledToolTip {
                text: volumeRow.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
            }
        }
    }

    // An app: its icon, name and what it's playing (its media player's track and artist in the accent, when one
    // has the same app name, else the stream's own title unless it's a stock one), its volume. Its node goes null for a moment as the app
    // stops (the row is on its way out): everything reads it with ?.
    component AppRow: SliderRow {
        id: appRow
        required property PwNode modelData
        readonly property PwNode node: modelData
        text: AppSearch.streamAppName(node)
        readonly property MprisPlayer player: Mpris.players.values.find(p => p.trackTitle && AppSearch.playerName(p) === appRow.text) ?? null
        readonly property string track: !player ? ""
            : [StringUtils.cleanMusicTitle(player.trackTitle, player.trackArtist), player.trackArtist].filter(s => s).join(" · ")
        readonly property string streamTitle: node?.properties["media.name"] ?? ""
        description: track !== "" ? track
            : /^(playback|audiostream|audio stream|recordstream|record stream|playstream)$/i.test(streamTitle) ? "" : streamTitle
        descriptionSymbol: track === "" ? "" : player.isPlaying ? "graphic_eq" : "pause"
        descriptionColor: track !== "" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
        level: node?.audio?.volume ?? 0
        dimmed: node?.audio?.muted ?? false
        onMoved: value => { if (appRow.node?.audio) appRow.node.audio.volume = value; }
        PwObjectTracker { objects: [appRow.node] }
        leading: RowSquircle { // Its app icon on the squircle
          Image {
            anchors.centerIn: parent
            visible: source != ""
            sourceSize: Qt.size(24, 24)
            source: {
                if (!appRow.node) return "";
                const entryIcon = AppSearch.appEntry(AppSearch.streamNames(appRow.node))?.icon ?? ""; // Its launcher entry's
                if (AppSearch.iconExists(entryIcon)) return Quickshell.iconPath(entryIcon, "image-missing");
                const named = AppSearch.guessIcon(appRow.node.properties["application.icon-name"]);
                if (AppSearch.iconExists(named)) return Quickshell.iconPath(named, "image-missing");
                return Quickshell.iconPath(AppSearch.guessIcon(appRow.node.properties["node.name"]), "image-missing");
            }
          }
        }
    }

    // Click one to use it; the one in use has its name in accent and a check
    component DeviceList: ContentSection {
        id: deviceList
        required property var devices
        required property bool isOutput
        readonly property var inUse: isOutput ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource
        Layout.preferredWidth: 1 // Two equal halves
        Layout.alignment: Qt.AlignTop
        Repeater {
            model: ScriptModel { values: deviceList.devices }
            delegate: RowButton {
                id: deviceRow
                required property var modelData
                current: modelData.id === deviceList.inUse?.id
                text: modelData.description || modelData.name
                leading: RowSquircle {
                    accent: deviceRow.current
                    symbol: deviceList.isOutput ? (/blue/i.test(deviceRow.modelData.name) ? "headphones" : "speaker") : "mic"
                }
                onClicked: {
                    if (deviceList.isOutput) Pipewire.preferredDefaultAudioSink = modelData;
                    else Pipewire.preferredDefaultAudioSource = modelData;
                }
            }
        }
    }
}
